import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'models.dart';
import 'parsers.dart';

/// Thrown when xorriso cannot be found or exits with a failure.
class XorrisoException implements Exception {
  final String message;

  /// The problem-level messages xorriso printed, oldest first.
  final List<XorrisoMessage> problems;
  final int? exitCode;

  const XorrisoException(this.message, {this.problems = const [], this.exitCode});

  /// The most useful single line to show a user: the last FAILURE/SORRY
  /// xorriso printed, falling back to [message].
  String get headline {
    for (final m in problems.reversed) {
      if (m.severity.index >= Severity.sorry.index &&
          !m.text.startsWith('aborting') &&
          !m.text.startsWith('-return_with')) {
        return m.text;
      }
    }
    return message;
  }

  @override
  String toString() => 'XorrisoException: $headline';
}

/// Finished, fully-buffered invocation (see [Xorriso.run]).
class XorrisoResult {
  final int exitCode;

  /// Every output line, packet prefix intact, in arrival order.
  final List<String> lines;

  const XorrisoResult(this.exitCode, this.lines);

  List<XorrisoMessage> get problems => [
    for (final l in lines)
      if (parseMessage(l) case final m? when m.isProblem) m,
  ];
}

/// A running invocation with live output (see [Xorriso.start]).
class XorrisoProcess {
  final Process _process;

  /// stdout+stderr merged, one line per event, packet prefix intact.
  /// Single-subscription — listen straight away.
  final Stream<String> lines;

  XorrisoProcess._(this._process, this.lines);

  Future<int> get exitCode => _process.exitCode;

  /// Asks xorriso to stop. It treats SIGINT as a request to abort cleanly:
  /// image generation stops at once, a burn ends the track as soon as the
  /// drive allows (a write-once disc is still used up).
  void cancel() => _process.kill(ProcessSignal.sigint);

  void kill() => _process.kill(ProcessSignal.sigkill);
}

/// The single chokepoint for xorriso invocations. Nothing else in the app
/// starts a process for burning.
class Xorriso {
  final String executable;

  const Xorriso(this.executable);

  /// Finds xorriso: `$CD_WRITER_XORRISO`, then the snap's bundled copy, then
  /// `PATH`. Returns null when none exists.
  static String? locate([Map<String, String>? environment]) {
    final env = environment ?? Platform.environment;
    final override = env['CD_WRITER_XORRISO'];
    if (override != null && override.isNotEmpty) {
      return File(override).existsSync() ? override : null;
    }
    final snap = env['SNAP'];
    final candidates = [
      if (snap != null) p.join(snap, 'usr', 'bin', 'xorriso'),
      for (final dir in (env['PATH'] ?? '').split(':'))
        if (dir.isNotEmpty) p.join(dir, 'xorriso'),
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return null;
  }

  /// Version line, e.g. "xorriso 1.5.6".
  Future<String> version() async {
    final r = await Process.run(executable, ['-version']);
    final lines = const LineSplitter().convert('${r.stdout}');
    return lines.firstWhere(
      (l) => l.startsWith('xorriso '),
      orElse: () => lines.isEmpty ? 'xorriso' : lines.first,
    );
  }

  /// Starts xorriso with packet output on so result lines (`R:`) and
  /// messages (`I:`) can be told apart reliably.
  Future<XorrisoProcess> start(List<String> args) async {
    final process = await Process.start(
      executable,
      ['-pkt_output', 'on', ...args],
      // Untranslated messages: the parsers match English text.
      environment: {'LC_ALL': 'C'},
    );
    final controller = StreamController<String>();
    var open = 2;
    void done() {
      if (--open == 0) controller.close();
    }

    for (final stream in [process.stdout, process.stderr]) {
      stream
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen(controller.add, onDone: done, onError: controller.addError);
    }
    return XorrisoProcess._(process, controller.stream);
  }

  /// Runs to completion and buffers the output. Throws [XorrisoException]
  /// on a non-zero exit unless [check] is false.
  Future<XorrisoResult> run(List<String> args, {bool check = true}) async {
    final proc = await start(args);
    final lines = await proc.lines.toList();
    final code = await proc.exitCode;
    final result = XorrisoResult(code, lines);
    if (check && code != 0) {
      throw XorrisoException('xorriso exited with code $code', problems: result.problems, exitCode: code);
    }
    return result;
  }

  /// Drives xorriso can open. "No drives found" is a normal empty list, not
  /// an error — xorriso reports it as SORRY and exits non-zero.
  Future<List<Drive>> devices() async {
    final r = await run(['-devices'], check: false);
    return parseDevices(r.lines);
  }

  Future<MediaInfo> toc(Drive drive) async {
    final r = await run(['-outdev', drive.address, '-toc'], check: false);
    final info = parseToc(r.lines);
    if (r.exitCode != 0 && !info.present) {
      final problems = r.problems;
      // An empty tray is a SORRY too; only surface genuine access failures.
      final hard = problems.where((m) => m.severity.index >= Severity.failure.index);
      if (hard.isNotEmpty) {
        throw XorrisoException('Cannot read the drive', problems: problems, exitCode: r.exitCode);
      }
    }
    return info;
  }
}

/// Fallback drive discovery from sysfs, for when xorriso is missing or the
/// user lacks permission to open the device (xorriso then lists nothing).
List<Drive> sysfsDrives({String root = '/sys/block'}) {
  final dir = Directory(root);
  List<FileSystemEntity> entries;
  try {
    entries = dir.listSync();
  } on FileSystemException {
    // Missing, or hidden by snap confinement; xorriso's own scan still runs.
    return const [];
  }
  final drives = <Drive>[];
  for (final entry in entries) {
    final name = p.basename(entry.path);
    if (!name.startsWith('sr')) continue;
    String read(String f) {
      try {
        return File(p.join(entry.path, 'device', f)).readAsStringSync().trim();
      } on FileSystemException {
        return '';
      }
    }

    drives.add(Drive(address: '/dev/$name', vendor: read('vendor'), model: read('model')));
  }
  drives.sort((a, b) => a.address.compareTo(b.address));
  return drives;
}

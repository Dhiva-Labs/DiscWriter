import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'models.dart';
import 'parsers.dart';
import 'xorriso.dart';

enum JobStatus { running, succeeded, failed, cancelled }

/// Snapshot of a job for the progress dialog.
class JobState {
  final String title;
  final JobStatus status;
  final int step;
  final List<String> stepLabels;
  final JobPhase phase;
  final double? fraction;
  final double? speed;
  final String? detail;

  /// Recent output, oldest first, capped at [JobRunner.logCap].
  final List<String> log;

  /// Set when [status] is failed.
  final String? error;

  /// Extra line shown on success ("Checksums match").
  final String? note;

  const JobState({
    required this.title,
    required this.stepLabels,
    this.status = JobStatus.running,
    this.step = 0,
    this.phase = JobPhase.preparing,
    this.fraction,
    this.speed,
    this.detail,
    this.log = const [],
    this.error,
    this.note,
  });

  bool get finished => status != JobStatus.running;

  String get stepLabel => stepLabels.isEmpty ? '' : stepLabels[step.clamp(0, stepLabels.length - 1)];

  JobState copyWith({
    JobStatus? status,
    int? step,
    JobPhase? phase,
    double? Function()? fraction,
    double? Function()? speed,
    String? Function()? detail,
    List<String>? log,
    String? error,
    String? note,
  }) => JobState(
    title: title,
    stepLabels: stepLabels,
    status: status ?? this.status,
    step: step ?? this.step,
    phase: phase ?? this.phase,
    fraction: fraction != null ? fraction() : this.fraction,
    speed: speed != null ? speed() : this.speed,
    detail: detail != null ? detail() : this.detail,
    log: log ?? this.log,
    error: error ?? this.error,
    note: note ?? this.note,
  );
}

/// Reports progress from inside a step.
typedef ProgressSink = void Function(Progress progress);

/// One unit of work inside a job.
sealed class JobStep {
  final String label;
  final JobPhase phase;

  const JobStep(this.label, this.phase);
}

/// Runs xorriso with [args], streaming its progress.
class XorrisoStep extends JobStep {
  final List<String> args;

  /// Total blocks of the session being checked, so `-check_md5`'s
  /// "N blocks read" lines turn into a percentage.
  final int? checkTotalBlocks;

  /// Turns the step's output into the success note, e.g. pulls "session data
  /// match recorded md5" out of a verify run.
  final String? Function(List<String> lines)? noteFrom;

  const XorrisoStep(super.label, super.phase, this.args, {this.checkTotalBlocks, this.noteFrom});
}

/// Arbitrary Dart work (file prep, byte comparison). Should poll
/// [isCancelled] and return early when it flips.
class DartStep extends JobStep {
  final Future<String?> Function(ProgressSink report, bool Function() isCancelled) body;

  const DartStep(super.label, super.phase, this.body);
}

/// Executes a list of steps in order, publishing [JobState]s. A failing step
/// stops the job; later steps (verify, eject) are skipped.
class JobRunner {
  static const logCap = 400;

  final Xorriso xorriso;
  final String title;
  final List<JobStep> steps;
  final void Function(JobState) onUpdate;

  XorrisoProcess? _current;
  bool _cancelled = false;
  late JobState _state;

  JobRunner({required this.xorriso, required this.title, required this.steps, required this.onUpdate}) {
    _state = JobState(title: title, stepLabels: [for (final s in steps) s.label]);
  }

  JobState get state => _state;

  void cancel() {
    _cancelled = true;
    _current?.cancel();
  }

  void _emit(JobState s) {
    _state = s;
    onUpdate(s);
  }

  void _log(String line) {
    final text = stripPacket(line).$2;
    if (text.trim().isEmpty) return;
    final log = [..._state.log, text];
    if (log.length > logCap) log.removeRange(0, log.length - logCap);
    _emit(_state.copyWith(log: log));
  }

  void _progress(Progress p) => _emit(
    _state.copyWith(
      phase: p.phase,
      fraction: () => p.fraction ?? _state.fraction,
      speed: () => p.speed ?? _state.speed,
      detail: () => p.detail ?? _state.detail,
    ),
  );

  Future<JobState> run() async {
    _emit(_state);
    String? note;
    for (var i = 0; i < steps.length; i++) {
      if (_cancelled) return _finish(JobStatus.cancelled);
      final step = steps[i];
      _emit(
        _state.copyWith(
          step: i,
          phase: step.phase,
          fraction: () => null,
          speed: () => null,
          detail: () => null,
        ),
      );
      try {
        final stepNote = switch (step) {
          XorrisoStep() => await _runXorriso(step),
          DartStep() => await step.body(_progress, () => _cancelled),
        };
        note = stepNote ?? note;
      } on XorrisoException catch (e) {
        if (_cancelled) return _finish(JobStatus.cancelled);
        return _finish(JobStatus.failed, error: e.headline);
      } on JobFailure catch (e) {
        return _finish(JobStatus.failed, error: e.message);
      } on FileSystemException catch (e) {
        return _finish(JobStatus.failed, error: '${e.message}${e.path == null ? '' : ': ${e.path}'}');
      } on ProcessException catch (e) {
        return _finish(JobStatus.failed, error: 'Could not start xorriso: ${e.message}');
      }
      if (_cancelled) return _finish(JobStatus.cancelled);
    }
    return _finish(JobStatus.succeeded, note: note);
  }

  JobState _finish(JobStatus status, {String? error, String? note}) {
    _current = null;
    final s = _state.copyWith(
      status: status,
      error: error,
      note: note,
      fraction: status == JobStatus.succeeded ? () => 1.0 : null,
    );
    _emit(s);
    return s;
  }

  Future<String?> _runXorriso(XorrisoStep step) async {
    final proc = await xorriso.start(step.args);
    _current = proc;
    final lines = <String>[];
    await for (final line in proc.lines) {
      lines.add(line);
      _log(line);
      final p = parseProgress(line, checkTotalBlocks: step.checkTotalBlocks);
      if (p != null) _progress(p);
    }
    final code = await proc.exitCode;
    _current = null;
    if (code != 0) {
      throw XorrisoException(
        'xorriso exited with code $code',
        problems: XorrisoResult(code, lines).problems,
        exitCode: code,
      );
    }
    return step.noteFrom?.call(lines);
  }
}

/// A step failure with a message meant for the user.
class JobFailure implements Exception {
  final String message;

  const JobFailure(this.message);

  @override
  String toString() => message;
}

/// Compares [imagePath] byte-for-byte with the start of [devicePath]. Used
/// after burning an image that carries no recorded MD5 (most downloaded
/// ISOs), where `-check_md5` has nothing to check against.
Future<String?> compareImageWithDevice(
  String imagePath,
  String devicePath,
  ProgressSink report,
  bool Function() isCancelled,
) async {
  const chunk = 1 << 20;
  final image = await File(imagePath).open();
  RandomAccessFile device;
  try {
    device = await File(devicePath).open();
  } on FileSystemException catch (e) {
    await image.close();
    throw JobFailure('Cannot read the disc back for verification: ${e.osError?.message ?? e.message}');
  }
  try {
    final total = await image.length();
    var done = 0;
    while (done < total) {
      if (isCancelled()) return null;
      final want = (total - done) < chunk ? total - done : chunk;
      final a = await image.read(want);
      final b = await _readFully(device, want);
      if (b.length < a.length) {
        throw JobFailure(
          'The disc ended after ${_mb(done + b.length)} — '
          'the image is ${_mb(total)}.',
        );
      }
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) {
          throw JobFailure(
            'Data differs at byte ${done + i} (sector '
            '${(done + i) ~/ sectorSize}). The disc is not a faithful copy.',
          );
        }
      }
      done += a.length;
      report(
        Progress(
          fraction: done / total,
          phase: JobPhase.verifying,
          detail: '${_mb(done)} of ${_mb(total)} compared',
        ),
      );
    }
    return 'Verified: disc matches the image byte for byte';
  } finally {
    await image.close();
    await device.close();
  }
}

Future<Uint8List> _readFully(RandomAccessFile f, int length) async {
  final builder = BytesBuilder(copy: false);
  while (builder.length < length) {
    final part = await f.read(length - builder.length);
    if (part.isEmpty) break;
    builder.add(part);
  }
  return builder.takeBytes();
}

String _mb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

/// Pulls the success line out of a `-check_md5` run.
String? md5Note(List<String> lines) {
  for (final l in lines) {
    final text = stripPacket(l).$2;
    if (text.contains('session data match recorded md5')) {
      return 'Verified: disc contents match the recorded checksums';
    }
  }
  return null;
}

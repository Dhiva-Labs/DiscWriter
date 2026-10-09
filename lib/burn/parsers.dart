/// Parsers for xorriso's text output. The runner always passes
/// `-pkt_output on`, so every line arrives as `R:1: …` (result channel) or
/// `I:1: …` (info/message channel); [stripPacket] peels that off first.
library;

import 'models.dart';

final _packet = RegExp(r'^([RIM]):[01]: ?(.*)$');

/// Splits a packet line into its channel letter and payload. Lines that are
/// not packets (the version banner xorriso prints before option parsing)
/// come back as channel `I`.
(String channel, String text) stripPacket(String line) {
  final m = _packet.firstMatch(line);
  if (m == null) return ('I', line);
  return (m.group(1)!, m.group(2)!);
}

// ---------------------------------------------------------------------------
// -devices

final _deviceLine = RegExp(
  r"^\s*\d+\s+-dev\s+'([^']+)'\s+(\S+)\s+:\s+'([^']*)'\s+'([^']*)'",
);

/// Parses `xorriso -devices` output into drives, e.g.
/// `0  -dev '/dev/sr0' rwrw-- :  'HL-DT-ST' 'DVDRAM GH24NSD1'`.
List<Drive> parseDevices(Iterable<String> lines) {
  final drives = <Drive>[];
  for (final raw in lines) {
    final m = _deviceLine.firstMatch(stripPacket(raw).$2);
    if (m == null) continue;
    drives.add(Drive(
      address: m.group(1)!,
      permissions: m.group(2)!,
      vendor: m.group(3)!.trim(),
      model: m.group(4)!.trim(),
    ));
  }
  return drives;
}

// ---------------------------------------------------------------------------
// -toc

final _kv = RegExp(r'^(Drive type|Media current|Media status|Media summary|'
    r'Media blocks|ISO session|Volume id)\s*:\s*(.*)$');
final _driveType =
    RegExp(r"vendor '([^']*)'\s+product '([^']*)'(?:\s+revision '([^']*)')?");
final _summary = RegExp(r'(\d+) sessions?,\s*(\d+) data blocks');
final _writable = RegExp(r'(\d+) writable');
final _isoSession = RegExp(r'^\s*\d+\s*,\s*\d+\s*,\s*\d+s\s*,\s*(.*)$');

/// Parses `xorriso -outdev <dev> -toc` (result and info lines both welcome)
/// into a [MediaInfo]. Missing disc, unknown fields and partial output all
/// degrade to sensible defaults rather than throwing.
MediaInfo parseToc(Iterable<String> lines) {
  String? profile;
  var vendor = '', model = '';
  var blank = false, appendable = false, closed = false, notPresent = false;
  var sessions = 0, dataBlocks = 0;
  int? writable;
  String? volumeId;

  for (final raw in lines) {
    final m = _kv.firstMatch(stripPacket(raw).$2.trim());
    if (m == null) continue;
    final key = m.group(1)!;
    final value = m.group(2)!.trim();
    switch (key) {
      case 'Drive type':
        final d = _driveType.firstMatch(value);
        if (d != null) {
          vendor = d.group(1)!.trim();
          model = d.group(2)!.trim();
        }
      case 'Media current':
        if (value == 'none' || value.contains('is not present')) {
          notPresent = true;
        } else {
          profile = value;
        }
      case 'Media status':
        if (value.contains('not present')) notPresent = true;
        blank = value.contains('is blank');
        appendable = value.contains('is appendable');
        closed = value.contains('is closed');
      case 'Media summary':
        final s = _summary.firstMatch(value);
        if (s != null) {
          sessions = int.parse(s.group(1)!);
          dataBlocks = int.parse(s.group(2)!);
        }
      case 'Media blocks':
        final w = _writable.firstMatch(value);
        if (w != null) writable = int.parse(w.group(1)!);
      case 'ISO session':
        final s = _isoSession.firstMatch(value);
        if (s != null) volumeId = s.group(1)!.trim();
      case 'Volume id':
        volumeId ??= value.replaceAll("'", '').trim();
    }
  }

  return MediaInfo(
    profile: notPresent ? null : profile,
    vendor: vendor,
    model: model,
    present: !notPresent && profile != null,
    blank: blank,
    appendable: appendable,
    closed: closed,
    sessions: sessions,
    dataBlocks: dataBlocks,
    writableBlocks: writable,
    volumeId: (volumeId == null || volumeId.isEmpty) ? null : volumeId,
  );
}

// ---------------------------------------------------------------------------
// -print_size

final _imageSize = RegExp(r'Image size\s*:\s*(\d+)s');

/// Exact ISO size in blocks from `-print_size`, or null.
int? parseImageSize(Iterable<String> lines) {
  for (final raw in lines) {
    final m = _imageSize.firstMatch(stripPacket(raw).$2);
    if (m != null) return int.parse(m.group(1)!);
  }
  return null;
}

// ---------------------------------------------------------------------------
// Messages and progress

final _message = RegExp(
  r'^(?:xorriso|libburn|libisofs|libisoburn)\s*:\s*'
  r'(NOTE|UPDATE|WARNING|HINT|SORRY|MISHAP|FAILURE|FATAL|ABORT)\s*:\s*(.*)$',
);

/// Recognises a severity-tagged message line, or returns null.
XorrisoMessage? parseMessage(String line) {
  final m = _message.firstMatch(stripPacket(line).$2.trim());
  if (m == null) return null;
  final severity = Severity.values.byName(m.group(1)!.toLowerCase());
  return XorrisoMessage(severity, m.group(2)!.trim());
}

final _percentDone = RegExp(r'^([\d.]+)% done');
final _nativeWriting = RegExp(r'^Writing:\s+(\d+)s\s+([\d.]+)%');
final _mbWritten = RegExp(r'^(\d+) of\s+(\d+) MB written');
final _parenDone = RegExp(r'^(Blanking|Formatting)\s*\(\s*([\d.]+)% done');
final _blocksRead = RegExp(r'^(\d+) blocks read');
final _speed = RegExp(r'([\d.]+)x[CDB]?\s*\.?\s*$');
final _filesAdded = RegExp(r'^(\d+) files added');

/// Turns one UPDATE line into a [Progress]. [checkTotalBlocks] lets MD5
/// verification (which only reports blocks read) produce a ratio.
///
/// The shapes handled, all after `xorriso : UPDATE :`:
/// * `32.00% done` — ISO image generation (`-as mkisofs`)
/// * `Writing:  11616s  7.9%  fifo 0%  buf 50%  173.9xD` — native `-commit`
/// * `91 of 382 MB written (fifo 99%) [buf 50%] 60.0x.` — `-as cdrecord`
/// * `Blanking  ( 23.4% done in 12 seconds )` / `Formatting ( … )`
/// * `1234 blocks read in 3 seconds , 12.3xD` — `-check_md5`
/// * `4 files added in 1 seconds` — tree building
Progress? parseProgress(String line, {int? checkTotalBlocks}) {
  final msg = parseMessage(line);
  if (msg == null || msg.severity != Severity.update) return null;
  final text = msg.text;
  final speed = double.tryParse(_speed.firstMatch(text)?.group(1) ?? '');

  var m = _nativeWriting.firstMatch(text);
  if (m != null) {
    return Progress(
      fraction: _pct(m.group(2)!),
      phase: JobPhase.writing,
      speed: speed,
      detail: '${_mb(int.parse(m.group(1)!))} written',
    );
  }
  m = _mbWritten.firstMatch(text);
  if (m != null) {
    final done = int.parse(m.group(1)!), total = int.parse(m.group(2)!);
    return Progress(
      fraction: total == 0 ? null : (done / total).clamp(0.0, 1.0),
      phase: JobPhase.writing,
      speed: speed,
      detail: '$done of $total MB written',
    );
  }
  m = _percentDone.firstMatch(text);
  if (m != null) {
    return Progress(fraction: _pct(m.group(1)!), phase: JobPhase.writing);
  }
  m = _parenDone.firstMatch(text);
  if (m != null) {
    return Progress(fraction: _pct(m.group(2)!), phase: JobPhase.blanking,
        detail: m.group(1));
  }
  m = _blocksRead.firstMatch(text);
  if (m != null) {
    final read = int.parse(m.group(1)!);
    return Progress(
      fraction: (checkTotalBlocks == null || checkTotalBlocks == 0)
          ? null
          : (read / checkTotalBlocks).clamp(0.0, 1.0),
      phase: JobPhase.verifying,
      speed: speed,
      detail: '${_mb(read)} checked',
    );
  }
  m = _filesAdded.firstMatch(text);
  if (m != null) {
    return Progress(phase: JobPhase.preparing, detail: '${m.group(1)} files added');
  }
  return null;
}

double _pct(String s) => (double.parse(s) / 100).clamp(0.0, 1.0);

String _mb(int blocks) =>
    '${(blocks * sectorSize / (1024 * 1024)).toStringAsFixed(0)} MB';

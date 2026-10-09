/// Plain data types shared by the xorriso layer and the UI. Nothing in here
/// touches a process or the filesystem.
library;

/// ISO 9660 / optical sector size. Every capacity and size xorriso reports in
/// "blocks" or "s" is in units of this.
const sectorSize = 2048;

/// One optical drive as reported by `xorriso -devices`.
class Drive {
  /// Address xorriso accepts for `-dev`/`-outdev`, e.g. `/dev/sr0`, or
  /// `stdio:/path/file.iso` for a file-backed pseudo drive.
  final String address;
  final String vendor;
  final String model;

  /// The `rwrw--` style permission string xorriso prints. Empty for drives
  /// found by the sysfs fallback or added by hand.
  final String permissions;

  const Drive({required this.address, this.vendor = '', this.model = '', this.permissions = ''});

  /// A file used as a drive. xorriso treats it like overwriteable media, which
  /// makes it the safe target for simulations and tests.
  factory Drive.imageFile(String path) => Drive(address: 'stdio:$path', vendor: 'Image file', model: path);

  bool get isImageFile => address.startsWith('stdio:');

  String get label {
    if (isImageFile) return 'Image file — ${address.substring(6)}';
    final name = [vendor, model].where((s) => s.isNotEmpty).join(' ');
    return name.isEmpty ? address : '$name ($address)';
  }

  @override
  bool operator ==(Object other) => other is Drive && other.address == address;

  @override
  int get hashCode => address.hashCode;
}

/// Broad disc family, used for capacity presets and wording.
enum DiscFamily { cd, dvd, bd, file, unknown }

/// What is in the drive, parsed from `xorriso -toc`.
class MediaInfo {
  /// libburn's media profile name: `CD-R`, `DVD+RW`, `BD-R sequential
  /// recording`, `stdio file, overwriteable`, … Null when no disc is loaded.
  final String? profile;
  final String vendor;
  final String model;
  final bool present;
  final bool blank;
  final bool appendable;
  final bool closed;
  final int sessions;

  /// Blocks already holding data (`Media summary`).
  final int dataBlocks;

  /// Blocks still writable, from `Media blocks`. Null when xorriso didn't say.
  final int? writableBlocks;

  /// Volume id of the last ISO session, if any.
  final String? volumeId;

  const MediaInfo({
    this.profile,
    this.vendor = '',
    this.model = '',
    this.present = false,
    this.blank = false,
    this.appendable = false,
    this.closed = false,
    this.sessions = 0,
    this.dataBlocks = 0,
    this.writableBlocks,
    this.volumeId,
  });

  static const none = MediaInfo();

  DiscFamily get family {
    final p = profile?.toUpperCase() ?? '';
    if (p.startsWith('STDIO')) return DiscFamily.file;
    if (p.startsWith('CD')) return DiscFamily.cd;
    if (p.startsWith('DVD') || p.startsWith('HD-DVD')) return DiscFamily.dvd;
    if (p.startsWith('BD')) return DiscFamily.bd;
    return DiscFamily.unknown;
  }

  /// Rewritable media that can be erased (CD-RW, DVD±RW, DVD-RAM, BD-RE).
  bool get erasable {
    final p = profile?.toUpperCase() ?? '';
    return p.startsWith('STDIO') ||
        p.contains('-RW') ||
        p.contains('+RW') ||
        p.contains('RAM') ||
        p.startsWith('BD-RE');
  }

  /// Can new data go onto this disc at all (blank, or open for more sessions)?
  bool get writable => present && (blank || appendable);

  /// Profile name without libburn's recording-mode suffixes; file-backed
  /// drives read as "Image file" rather than libburn's "stdio file".
  String get displayName {
    if (family == DiscFamily.file) return 'Image file';
    return (profile ?? 'Unknown media')
        .replaceAll(' sequential recording', '')
        .replaceAll(' restricted overwrite', '')
        .replaceAll(' random recording', '');
  }

  /// Short human description, e.g. "DVD+RW · blank".
  String get summary {
    if (!present) return 'No disc';
    final state = blank
        ? 'blank'
        : appendable
        ? 'appendable, $sessions session${sessions == 1 ? '' : 's'}'
        : closed
        ? 'closed'
        : 'written';
    return '$displayName · $state';
  }
}

/// Coarse phase a running job is in; drives the dialog's headline.
enum JobPhase { preparing, writing, blanking, verifying, finishing }

/// One progress observation pulled out of xorriso's chatter.
class Progress {
  /// 0..1, or null when xorriso reported activity without a ratio.
  final double? fraction;
  final JobPhase phase;

  /// Write speed as a multiple of the media's 1x (e.g. 8.0 for 8x).
  final double? speed;

  /// Free-form status text worth showing ("4 files added", "91 of 382 MB").
  final String? detail;

  const Progress({this.fraction, required this.phase, this.speed, this.detail});
}

/// Severity ladder xorriso uses for its messages, low to high.
enum Severity { note, update, warning, hint, sorry, mishap, failure, fatal, abort }

/// A severity-tagged message line, e.g. `xorriso : FAILURE : Cannot …`.
class XorrisoMessage {
  final Severity severity;
  final String text;

  const XorrisoMessage(this.severity, this.text);

  bool get isProblem => severity.index >= Severity.sorry.index;
}

/// Nominal capacities used before a disc is inserted. Once a disc is present
/// its own `writableBlocks` wins.
enum CapacityPreset {
  cd700('CD 700 MB', 360000),
  dvd5('DVD 4.7 GB', 2295104),
  dvd9('DVD DL 8.5 GB', 4173824),
  bd25('BD 25 GB', 12219392),
  bd50('BD DL 50 GB', 24438784);

  final String label;
  final int blocks;

  const CapacityPreset(this.label, this.blocks);

  int get bytes => blocks * sectorSize;
}

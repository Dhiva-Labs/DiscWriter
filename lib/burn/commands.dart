/// Argument builders for every xorriso invocation the app makes. Pure
/// functions so the exact argv can be unit-tested without a drive. The
/// runner prepends `-pkt_output on`; nothing here does.
library;

import '../project/disc_project.dart';
import 'models.dart';

/// Knobs shared by the burn jobs.
class BurnOptions {
  /// Speed as a multiple of the media's 1x; null means the drive's maximum.
  final int? speed;

  /// Run the whole burn with the laser off. Nothing is written.
  final bool simulate;

  /// Write-once media only: close the disc so no further sessions can be
  /// added. Closed discs read in more (older) players and drives.
  final bool closeDisc;

  /// Rewritable media only: blank whatever is on the disc first instead of
  /// adding a session after it.
  final bool eraseFirst;

  /// Read the disc back after writing and compare checksums.
  final bool verify;

  final bool eject;

  /// Verification is skipped for simulations: nothing was written.
  bool get willVerify => verify && !simulate;

  /// Eject as part of the write itself only when no verify pass follows.
  bool get ejectAfterWrite => eject && !willVerify;

  const BurnOptions({
    this.speed,
    this.simulate = false,
    this.closeDisc = true,
    this.eraseFirst = false,
    this.verify = true,
    this.eject = true,
  });

  BurnOptions copyWith({
    int? Function()? speed,
    bool? simulate,
    bool? closeDisc,
    bool? eraseFirst,
    bool? verify,
    bool? eject,
  }) =>
      BurnOptions(
        speed: speed != null ? speed() : this.speed,
        simulate: simulate ?? this.simulate,
        closeDisc: closeDisc ?? this.closeDisc,
        eraseFirst: eraseFirst ?? this.eraseFirst,
        verify: verify ?? this.verify,
        eject: eject ?? this.eject,
      );
}

/// Abort on the first FAILURE-level event instead of pressing on, and turn
/// off pattern expansion so paths containing `*` or `?` are taken literally.
const _strict = [
  '-abort_on', 'FAILURE',
  '-disk_pattern', 'off',
  '-iso_rr_pattern', 'off',
];

/// Joliet for Windows, Rock Ridge for Unix, ISO level 3 so single files over
/// 4 GiB are allowed (DVD/BD backups hit that limit quickly).
const _filesystem = [
  '-joliet', 'on',
  '-rockridge', 'on',
  '-compliance', 'iso_9660_level=3:joliet_long_names',
];

/// `xorriso -devices`: every drive the user may access.
List<String> devicesArgs() => ['-devices'];

/// Media status of [drive] without loading its file tree.
List<String> tocArgs(Drive drive) => ['-outdev', drive.address, '-toc'];

/// Exact image size the project would produce, for the capacity check.
///
/// `-print_size` needs an output drive, and xorriso commits any pending
/// image when the program ends, so the size is computed against
/// `stdio:/dev/null` and `-rollback_end` discards the tree instead of
/// streaming gigabytes into the null device.
List<String> printSizeArgs(DiscProject project) => [
      ..._strict,
      '-outdev', 'stdio:/dev/null',
      ..._filesystem,
      '-volid', project.label,
      ..._maps(project),
      '-print_size',
      '-rollback_end',
    ];

/// Writes [project] to an ISO file at [isoPath] with session MD5s recorded,
/// so a disc later burned from it can be verified with `-check_md5`.
///
/// Uses the `-as mkisofs` emulation rather than native `-outdev stdio:`:
/// native writes treat the file as overwriteable media and start the
/// session at LBA 32 behind a superblock copy, which mounts fine but is not
/// the plain ISO people expect to hand to other tools.
List<String> buildIsoArgs(DiscProject project, String isoPath) => [
      '-md5', 'on',
      '-abort_on', 'FAILURE',
      '-as', 'mkisofs',
      '-V', project.label,
      '-r', // Rock Ridge with world-readable permissions
      '-J', '-joliet-long',
      '-iso-level', '3',
      '-o', isoPath,
      '-graft-points',
      for (final e in project.entries)
        '${_graftEscape(e.isoPath)}=${_graftEscape(e.sourcePath)}',
    ];

/// Burns [project] straight to the disc in [drive] (no temporary ISO).
///
/// On appendable media the existing session is loaded with `-dev` so its
/// files stay visible next to the new ones; with [BurnOptions.eraseFirst]
/// (or blank media) a fresh `-outdev` session is written instead.
List<String> burnProjectArgs(
  DiscProject project,
  Drive drive,
  MediaInfo media,
  BurnOptions opts,
) {
  final append = media.appendable && !media.blank && !opts.eraseFirst;
  return [
    '-md5', 'on',
    ..._strict,
    append ? '-dev' : '-outdev', drive.address,
    if (opts.eraseFirst && media.erasable && !media.blank) ...[
      '-blank', 'as_needed',
    ],
    '-speed', _speedCode(opts.speed, media),
    '-dummy', opts.simulate ? 'on' : 'off',
    '-close', opts.closeDisc ? 'on' : 'off',
    ..._filesystem,
    '-volid', project.label,
    ..._maps(project),
    '-commit_eject', opts.ejectAfterWrite ? 'all' : 'none',
  ];
}

/// Burns an existing image file to disc via the cdrecord emulation, which
/// copies the bytes verbatim (bootable ISOs stay bootable).
List<String> burnImageArgs(
  String imagePath,
  Drive drive,
  MediaInfo media,
  BurnOptions opts,
) =>
    [
      '-abort_on', 'FAILURE',
      '-as', 'cdrecord',
      '-v',
      'dev=${drive.address}',
      if (opts.speed != null) 'speed=${opts.speed}',
      if (opts.simulate) '-dummy',
      if (opts.eraseFirst && media.erasable && !media.blank) 'blank=as_needed',
      if (!opts.closeDisc) '-multi',
      if (opts.ejectAfterWrite) '-eject',
      imagePath,
    ];

enum BlankMode {
  /// Invalidates the table of contents; seconds to a few minutes.
  fast,

  /// Overwrites the whole disc; as long as a full burn.
  full,
}

/// Erases rewritable media.
List<String> blankArgs(Drive drive, BlankMode mode, {bool simulate = false}) => [
      '-abort_on', 'FAILURE',
      '-outdev', drive.address,
      '-dummy', simulate ? 'on' : 'off',
      '-blank', mode == BlankMode.fast ? 'as_needed' : 'all',
    ];

/// Re-reads the newest session and compares it with the MD5 recorded when it
/// was written. `-md5 on` must come before `-indev`, or the recorded sums
/// are never loaded and every check reports a mismatch.
List<String> verifyArgs(Drive drive, {bool eject = false}) => [
      '-md5', 'on',
      '-abort_on', 'FAILURE',
      '-indev', drive.address,
      '-check_md5', 'FAILURE', '--',
      if (eject) ...['-eject', 'all'],
    ];

List<String> ejectArgs(Drive drive) =>
    ['-outdev', drive.address, '-eject', 'all'];

List<String> _maps(DiscProject project) => [
      for (final e in project.entries) ...['-map', e.sourcePath, e.isoPath],
    ];

/// xorriso's `-speed` takes a unit suffix: `c` (CD 1x = 176.4 kB/s), `d`
/// (DVD 1x = 1385 kB/s), `b` (BD 1x = 4495.625 kB/s). A bare number would
/// mean kB/s, which is never what a user picking "8x" wants.
String _speedCode(int? speed, MediaInfo media) {
  if (speed == null) return 'max';
  final unit = switch (media.family) {
    DiscFamily.dvd => 'd',
    DiscFamily.bd => 'b',
    _ => 'c',
  };
  return '$speed$unit';
}

/// mkisofs graft points split on the first unescaped `=`, and treat `\` as
/// the escape character, so both must be escaped in either half.
String _graftEscape(String s) =>
    s.replaceAll(r'\', r'\\').replaceAll('=', r'\=');

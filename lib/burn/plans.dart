/// Turns a user request ("burn this project to that drive") into the ordered
/// [JobStep]s the [JobRunner] executes.
library;

import 'dart:io';

import '../project/disc_project.dart';
import 'commands.dart';
import 'jobs.dart';
import 'models.dart';
import 'xorriso.dart';
import 'parsers.dart';

/// Size check → burn → (verify) → (eject).
///
/// The size check runs `-print_size` so an over-full project fails before
/// a single block of a write-once disc is used.
List<JobStep> burnProjectPlan(
  Xorriso xorriso,
  DiscProject project,
  Drive drive,
  MediaInfo media,
  BurnOptions opts,
) {
  final verify = opts.willVerify;
  return [
    DartStep('Checking size', JobPhase.preparing, (report, cancelled) async {
      final r = await xorriso.run(printSizeArgs(project));
      final blocks = parseImageSize(r.lines);
      final free = media.writableBlocks;
      if (blocks != null && free != null && blocks > free) {
        throw JobFailure('The data needs ${formatBlocks(blocks)} but the disc '
            'has ${formatBlocks(free)} free.');
      }
      return null;
    }),
    XorrisoStep(
      opts.simulate ? 'Simulating burn' : 'Writing disc',
      JobPhase.writing,
      burnProjectArgs(project, drive, media, opts),
    ),
    if (verify)
      XorrisoStep(
        'Verifying',
        JobPhase.verifying,
        verifyArgs(drive, eject: opts.eject),
        checkTotalBlocks: project.estimatedBlocks,
        noteFrom: md5Note,
      ),
    if (opts.simulate)
      DartStep('Done', JobPhase.finishing, (_, _) async =>
          'Simulation finished — nothing was written'),
  ];
}

/// Builds an ISO file from the project.
List<JobStep> buildIsoPlan(DiscProject project, String isoPath) => [
      DartStep('Preparing', JobPhase.preparing, (report, cancelled) async {
        // -as mkisofs on an existing file would treat it as media with a
        // session on it; the save dialog already confirmed the overwrite.
        final f = File(isoPath);
        if (await f.exists()) await f.delete();
        return null;
      }),
      XorrisoStep('Creating image', JobPhase.writing, buildIsoArgs(project, isoPath)),
      DartStep('Done', JobPhase.finishing, (_, _) async {
        final size = await File(isoPath).length();
        return 'Saved ${formatBytes(size)} image';
      }),
    ];

/// Burns an image file, then compares the disc against it byte for byte.
List<JobStep> burnImagePlan(
  Xorriso xorriso,
  String imagePath,
  Drive drive,
  MediaInfo media,
  BurnOptions opts,
) {
  final verify = opts.willVerify;
  return [
    DartStep('Checking size', JobPhase.preparing, (report, cancelled) async {
      final bytes = await File(imagePath).length();
      final free = media.writableBlocks;
      if (free != null && bytes > free * sectorSize) {
        throw JobFailure('The image is ${formatBytes(bytes)} but the disc has '
            '${formatBlocks(free)} free.');
      }
      return null;
    }),
    XorrisoStep(
      opts.simulate ? 'Simulating burn' : 'Writing disc',
      JobPhase.writing,
      burnImageArgs(imagePath, drive, media, opts),
    ),
    if (verify)
      DartStep('Verifying', JobPhase.verifying, (report, cancelled) {
        final device = drive.isImageFile ? drive.address.substring(6) : drive.address;
        return compareImageWithDevice(imagePath, device, report, cancelled);
      }),
    if (verify && opts.eject)
      XorrisoStep('Ejecting', JobPhase.finishing, ejectArgs(drive)),
    if (opts.simulate)
      DartStep('Done', JobPhase.finishing, (_, _) async =>
          'Simulation finished — nothing was written'),
  ];
}

List<JobStep> blankPlan(Drive drive, BlankMode mode, {bool simulate = false}) => [
      XorrisoStep(
        mode == BlankMode.fast ? 'Quick erase' : 'Full erase',
        JobPhase.blanking,
        blankArgs(drive, mode, simulate: simulate),
        noteFrom: (_) => simulate
            ? 'Simulation finished — the disc was not erased'
            : 'The disc is blank and ready to use',
      ),
    ];

String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = bytes.toDouble();
  var u = 0;
  while (v >= 1024 && u < units.length - 1) {
    v /= 1024;
    u++;
  }
  return u == 0 ? '$bytes B' : '${v.toStringAsFixed(v >= 100 ? 0 : 1)} ${units[u]}';
}

String formatBlocks(int blocks) => formatBytes(blocks * sectorSize);

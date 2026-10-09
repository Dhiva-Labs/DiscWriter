// End-to-end runs against the real xorriso, using file-backed "stdio:"
// drives so no optical hardware is needed. Skipped when xorriso is not on
// PATH and CD_WRITER_XORRISO is unset.
import 'dart:io';
import 'dart:math';

import 'package:cd_writer/burn/commands.dart';
import 'package:cd_writer/burn/jobs.dart';
import 'package:cd_writer/burn/models.dart';
import 'package:cd_writer/burn/plans.dart';
import 'package:cd_writer/burn/xorriso.dart';
import 'package:cd_writer/project/disc_project.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  final exe = Xorriso.locate();
  final skip = exe == null ? 'xorriso not found' : null;
  final x = Xorriso(exe ?? 'xorriso');

  late Directory tmp;
  late DiscProject project;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('cdw_e2e');
    final src = await Directory(p.join(tmp.path, 'src', 'Holiday Photos')).create(recursive: true);
    final rnd = Random(7);
    await File(p.join(src.path, 'beach.jpg'))
        .writeAsBytes(List.generate(3 * 1024 * 1024, (_) => rnd.nextInt(256)));
    await File(p.join(src.path, 'weird=name*?.txt')).writeAsString('odd but legal');
    final notes = await File(p.join(tmp.path, 'src', 'notes.txt')).writeAsString('hello disc');
    project = const DiscProject(label: 'E2E TEST').withAdded([entryFor(src.path), entryFor(notes.path)]);
    for (final e in project.entries) {
      final (b, n) = await measurePath(e.sourcePath);
      project = project.withSize(e.sourcePath, b, n);
    }
  });

  tearDown(() => tmp.delete(recursive: true));

  Future<JobState> runPlan(String title, List<JobStep> steps, {void Function(JobRunner)? onStart}) {
    final runner = JobRunner(xorriso: x, title: title, steps: steps, onUpdate: (_) {});
    onStart?.call(runner);
    return runner.run();
  }

  Future<List<String>> isoListing(Drive drive) async {
    final r = await x.run(['-indev', drive.address, '-find', '/', '-type', 'f', '--']);
    return [
      for (final l in r.lines)
        if (l.startsWith('R:1: ')) l.substring(5).replaceAll("'", ''),
    ]..sort();
  }

  test('burn a project, verify by MD5, then append a second session', () async {
    final drive = Drive.imageFile(p.join(tmp.path, 'disc.img'));
    var media = await x.toc(drive);
    expect(media.blank, isTrue);

    var result = await runPlan('Burn', burnProjectPlan(x, project, drive, media, const BurnOptions(closeDisc: false)));
    expect(result.status, JobStatus.succeeded, reason: result.error);
    expect(result.note, contains('match the recorded checksums'));
    expect(result.log, isNotEmpty);

    media = await x.toc(drive);
    expect(media.appendable, isTrue);
    expect(media.sessions, 1);
    expect(media.volumeId, 'E2E TEST');
    expect(await isoListing(drive), [
      '/Holiday Photos/beach.jpg',
      '/Holiday Photos/weird=name*?.txt',
      '/notes.txt',
    ]);

    // Second session keeps the first one's files visible.
    final extra = await File(p.join(tmp.path, 'later.txt')).writeAsString('added later');
    final second = const DiscProject(label: 'E2E TEST 2').withAdded([entryFor(extra.path)])
        .withSize(extra.path, 11, 1);
    result = await runPlan('Append', burnProjectPlan(x, second, drive, media, const BurnOptions()));
    expect(result.status, JobStatus.succeeded, reason: result.error);
    media = await x.toc(drive);
    expect(media.sessions, 2);
    expect(await isoListing(drive), contains('/later.txt'));
    expect(await isoListing(drive), contains('/notes.txt'));
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));

  test('save as ISO, burn the ISO, verify byte for byte', () async {
    final iso = p.join(tmp.path, 'out.iso');
    var result = await runPlan('ISO', buildIsoPlan(project, iso));
    expect(result.status, JobStatus.succeeded, reason: result.error);
    expect(result.note, startsWith('Saved'));
    // The ISO carries session MD5s, so it verifies on its own.
    final isoAsDrive = Drive.imageFile(iso);
    final check = await x.run(verifyArgs(isoAsDrive));
    expect(check.exitCode, 0);
    expect(await isoListing(isoAsDrive), contains('/Holiday Photos/beach.jpg'));

    final drive = Drive.imageFile(p.join(tmp.path, 'burned.img'));
    final media = await x.toc(drive);
    result = await runPlan('Image', burnImagePlan(x, iso, drive, media, const BurnOptions()));
    expect(result.status, JobStatus.succeeded, reason: result.error);
    expect(result.note, contains('byte for byte'));
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));

  test('verification catches a corrupted disc', () async {
    final drive = Drive.imageFile(p.join(tmp.path, 'disc.img'));
    final media = await x.toc(drive);
    final r = await runPlan('Burn', burnProjectPlan(x, project, drive, media, const BurnOptions(verify: false)));
    expect(r.status, JobStatus.succeeded, reason: r.error);

    final raf = await File(drive.address.substring(6)).open(mode: FileMode.append);
    await raf.setPosition(80 * sectorSize);
    await raf.writeFrom([0xde, 0xad, 0xbe, 0xef]);
    await raf.close();

    final v = await runPlan('Verify', [
      XorrisoStep('Verifying', JobPhase.verifying, verifyArgs(drive), noteFrom: md5Note),
    ]);
    expect(v.status, JobStatus.failed);
    expect(v.error, contains('MD5'));
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));

  test('an over-full project fails before writing anything', () async {
    final drive = Drive.imageFile(p.join(tmp.path, 'tiny.img'));
    const tiny = MediaInfo(profile: 'CD-R', present: true, blank: true, writableBlocks: 500);
    final r = await runPlan('Burn', burnProjectPlan(x, project, drive, tiny, const BurnOptions()));
    expect(r.status, JobStatus.failed);
    expect(r.error, contains('free'));
    expect(r.step, 0);
    expect(File(p.join(tmp.path, 'tiny.img')).existsSync(), isFalse);
  }, skip: skip);

  test('erase returns the disc to blank', () async {
    final drive = Drive.imageFile(p.join(tmp.path, 'rw.img'));
    var media = await x.toc(drive);
    await runPlan('Burn', burnProjectPlan(x, project, drive, media, const BurnOptions(verify: false)));
    media = await x.toc(drive);
    expect(media.blank, isFalse);

    final r = await runPlan('Erase', blankPlan(drive, BlankMode.fast));
    expect(r.status, JobStatus.succeeded, reason: r.error);
    expect((await x.toc(drive)).blank, isTrue);
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));

  test('cancelling stops a running burn', () async {
    final big = await File(p.join(tmp.path, 'big.bin')).create();
    await big.writeAsBytes(List.filled(1024 * 1024, 0));
    final raf = await big.open(mode: FileMode.append);
    for (var i = 0; i < 300; i++) {
      await raf.writeFrom(List.filled(1024 * 1024, i & 0xff));
    }
    await raf.close();
    final proj = const DiscProject().withAdded([entryFor(big.path)]).withSize(big.path, await big.length(), 1);
    final drive = Drive.imageFile(p.join(tmp.path, 'c.img'));
    final media = await x.toc(drive);

    late JobRunner runner;
    var cancelled = false;
    final states = <JobState>[];
    runner = JobRunner(
      xorriso: x,
      title: 'Burn',
      steps: burnProjectPlan(x, proj, drive, media, const BurnOptions(verify: false)),
      onUpdate: (s) {
        states.add(s);
        if (!cancelled && s.phase == JobPhase.writing && (s.fraction ?? 0) > 0) {
          cancelled = true;
          runner.cancel();
        }
      },
    );
    final r = await runner.run();
    expect(cancelled, isTrue, reason: 'never saw write progress');
    expect(r.status, JobStatus.cancelled);
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));
}

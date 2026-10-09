// Drives the real app on the Linux embedder: builds a data disc, burns it
// through the UI to a file-backed drive, verifies, and saves screenshots of
// every page to screenshots/.
//
//   CD_WRITER_XORRISO=/path/to/xorriso flutter test integration_test -d linux
//
// (CD_WRITER_XORRISO is only needed when xorriso is not on PATH.)
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cd_writer/app.dart';
import 'package:cd_writer/burn/models.dart';
import 'package:cd_writer/burn/xorriso.dart';
import 'package:cd_writer/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

const _boundaryKey = ValueKey('screenshot-boundary');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final outDir = Directory(p.join(Directory.current.path, 'screenshots'));

  Future<void> shoot(WidgetTester tester, String name) async {
    await tester.pump(const Duration(milliseconds: 300));
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_boundaryKey));
    final bytes = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.5);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    outDir.createSync(recursive: true);
    File(p.join(outDir.path, '$name.png')).writeAsBytesSync(bytes!);
    // ignore: avoid_print
    print('WROTE screenshots/$name.png');
  }

  Future<void> pumpUntil(WidgetTester tester, bool Function() done,
      {Duration timeout = const Duration(seconds: 60)}) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 200));
      if (done()) return;
    }
    fail('condition not met within $timeout');
  }

  testWidgets('build, burn and verify a data disc through the UI', (tester) async {
    expect(Xorriso.locate(), isNotNull, reason: 'xorriso is required for this test');
    final tmp = await Directory.systemTemp.createTemp('cdw_ui_');
    addTearDown(() => tmp.delete(recursive: true));

    // Realistic-looking content. Sparse files keep the run fast while the
    // capacity bar shows a believable fill.
    final photos = await Directory(p.join(tmp.path, 'Family Photos 2026')).create();
    for (var i = 1; i <= 24; i++) {
      final f = File(p.join(photos.path, 'IMG_${2400 + i}.jpg'));
      await (await f.open(mode: FileMode.write)).truncate(9 * 1024 * 1024 + i * 37);
    }
    final docs = await Directory(p.join(tmp.path, 'Tax Documents')).create();
    await File(p.join(docs.path, 'return-2025.pdf')).writeAsString('%PDF-1.7 pretend');
    final video = File(p.join(tmp.path, 'wedding-highlights.mp4'));
    await (await video.open(mode: FileMode.write)).truncate(420 * 1024 * 1024);

    final driveFile = p.join(tmp.path, 'rehearsal-disc.img');
    final drive = Drive.imageFile(driveFile);
    late WidgetRef ref;

    tester.view.physicalSize = const Size(1180, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(RepaintBoundary(
      key: _boundaryKey,
      child: ProviderScope(
        overrides: [imageFileDrivesProvider.overrideWith((_) => [drive])],
        child: Consumer(builder: (context, r, _) {
          ref = r;
          return const CdWriterApp();
        }),
      ),
    ));
    await pumpUntil(tester, () => find.textContaining('Image file ·').evaluate().isNotEmpty);

    // Empty state first.
    await shoot(tester, '00-empty');

    // Fill the project the same way a drop does.
    final label = find.widgetWithText(TextField, 'Disc label');
    await tester.enterText(label, 'FAMILY BACKUP 2026');
    ref.read(projectProvider.notifier).addPaths([photos.path, docs.path, video.path]);
    await pumpUntil(tester, () => !ref.read(projectProvider).sizing);
    await pumpUntil(tester, () => find.textContaining('items').evaluate().isNotEmpty);
    await shoot(tester, '01-data-disc');

    // Burn through the real button and dialog.
    await tester.tap(find.widgetWithText(FilledButton, 'Burn'));
    await pumpUntil(tester, () => find.byType(AlertDialog).evaluate().isNotEmpty);
    await pumpUntil(tester, () {
      final job = ref.read(jobProvider);
      return job != null && job.step >= 1 && (job.fraction ?? 0) > 0;
    }, timeout: const Duration(seconds: 30)).catchError((_) {});
    await shoot(tester, '02-burning');
    await pumpUntil(tester, () => ref.read(jobProvider)?.finished ?? false,
        timeout: const Duration(minutes: 3));
    final job = ref.read(jobProvider)!;
    expect(job.error, isNull);
    expect(job.note, contains('match the recorded checksums'));
    await tester.tap(find.text('Show details'));
    await tester.pump();
    await shoot(tester, '03-burn-verified');
    await tester.tap(find.widgetWithText(FilledButton, 'Close'));
    await pumpUntil(tester, () => find.byType(AlertDialog).evaluate().isEmpty);

    // The drive now reports one session with our label.
    await pumpUntil(tester, () => find.textContaining('appendable, 1 session').evaluate().isNotEmpty);

    await tester.tap(find.text('Disc info'));
    await pumpUntil(tester, () => find.text('FAMILY BACKUP 2026').evaluate().isNotEmpty);
    await shoot(tester, '04-disc-info');

    await tester.tap(find.text('Burn image'));
    await tester.pumpAndSettle();
    await shoot(tester, '05-burn-image');

    // Erase brings the rehearsal disc back to blank.
    await tester.tap(find.text('Erase'));
    await tester.pumpAndSettle();
    await shoot(tester, '06-erase');
    await tester.tap(find.widgetWithText(FilledButton, 'Erase disc'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Erase'));
    await pumpUntil(tester, () => ref.read(jobProvider)?.finished ?? false);
    expect(ref.read(jobProvider)!.status.name, 'succeeded');
    await tester.tap(find.widgetWithText(FilledButton, 'Close'));
    await pumpUntil(tester, () => find.textContaining('Image file · blank').evaluate().isNotEmpty);
  });
}

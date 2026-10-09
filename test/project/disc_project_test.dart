import 'dart:io';

import 'package:cd_writer/project/disc_project.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

DiscEntry _e(String path, {String? name, int? bytes, int files = 1}) => DiscEntry(
    sourcePath: path, name: name ?? p.basename(path), isDirectory: false, bytes: bytes, fileCount: files);

void main() {
  test('duplicate names get numbered, duplicate sources are skipped', () {
    final project = const DiscProject().withAdded([
      _e('/a/notes.txt'),
      _e('/b/notes.txt'),
      _e('/c/notes.txt'),
      _e('/a/notes.txt'),
      _e('/d/music'),
      _e('/e/music'),
    ]);
    expect(project.entries.map((e) => e.name),
        ['notes.txt', 'notes (2).txt', 'notes (3).txt', 'music', 'music (2)']);
  });

  test('rename rejects clashes and invalid names', () {
    final project = const DiscProject().withAdded([_e('/a/x'), _e('/a/y')]);
    expect(project.withRenamed('/a/x', 'y').entries.first.name, 'x');
    expect(project.withRenamed('/a/x', 'a/b').entries.first.name, 'x');
    expect(project.withRenamed('/a/x', '  z  ').entries.first.name, 'z');
  });

  test('size totals and estimate', () {
    var project = const DiscProject().withAdded([_e('/a/x'), _e('/a/y')]);
    expect(project.sizing, isTrue);
    project = project.withSize('/a/x', 4096, 1).withSize('/a/y', 1, 1);
    expect(project.sizing, isFalse);
    expect(project.totalBytes, 4097);
    expect(project.totalFiles, 2);
    // 3 data blocks + fixed overhead + per-file slack.
    expect(project.estimatedBlocks, greaterThanOrEqualTo(203));
    expect(project.withoutPath('/a/x').entries.single.sourcePath, '/a/y');
  });

  test('label validation', () {
    expect(validateLabel('BACKUP 2026'), isNull);
    expect(validateLabel(''), isNotNull);
    expect(validateLabel('x' * 33), isNotNull);
    expect(validateLabel('x' * 32), isNull);
  });

  test('measurePath counts files recursively without following links', () async {
    final dir = await Directory.systemTemp.createTemp('cdw_measure');
    addTearDown(() => dir.delete(recursive: true));
    await File(p.join(dir.path, 'a')).writeAsBytes(List.filled(1000, 1));
    await Directory(p.join(dir.path, 'sub')).create();
    await File(p.join(dir.path, 'sub', 'b')).writeAsBytes(List.filled(500, 1));
    await Link(p.join(dir.path, 'loop')).create(dir.path);
    final (bytes, files) = await measurePath(dir.path);
    expect(bytes, 1500);
    expect(files, 4); // a, sub, sub/b, loop
    expect(await measurePath(p.join(dir.path, 'a')), (1000, 1));
  });

  test('entryFor resolves a picked symlink but keeps its name', () async {
    final dir = await Directory.systemTemp.createTemp('cdw_entry');
    addTearDown(() => dir.delete(recursive: true));
    final target = await Directory(p.join(dir.path, 'real')).create();
    await Link(p.join(dir.path, 'shortcut')).create(target.path);
    final e = entryFor(p.join(dir.path, 'shortcut'));
    expect(e.name, 'shortcut');
    expect(e.sourcePath, target.resolveSymbolicLinksSync());
    expect(e.isDirectory, isTrue);
  });
}

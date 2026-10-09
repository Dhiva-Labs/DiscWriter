import 'dart:io';

import 'package:path/path.dart' as p;

import '../burn/models.dart';

/// One file or folder placed at the root of the disc.
class DiscEntry {
  /// Absolute path on the local disk.
  final String sourcePath;

  /// Name it gets on the disc. Defaults to the source's basename; renamed
  /// automatically when two sources share a name.
  final String name;
  final bool isDirectory;

  /// Total bytes (recursively for folders). Null while still being counted.
  final int? bytes;

  /// Files inside (1 for a plain file). Feeds the size estimate.
  final int fileCount;

  const DiscEntry({
    required this.sourcePath,
    required this.name,
    required this.isDirectory,
    this.bytes,
    this.fileCount = 1,
  });

  DiscEntry copyWith({String? name, int? bytes, int? fileCount}) => DiscEntry(
    sourcePath: sourcePath,
    name: name ?? this.name,
    isDirectory: isDirectory,
    bytes: bytes ?? this.bytes,
    fileCount: fileCount ?? this.fileCount,
  );

  /// Path on the disc, always absolute in ISO terms.
  String get isoPath => '/$name';
}

/// The contents of a data disc being assembled. Immutable; edits return a
/// new project.
class DiscProject {
  final String label;
  final List<DiscEntry> entries;

  const DiscProject({this.label = defaultLabel, this.entries = const []});

  static const defaultLabel = 'DATA_DISC';

  /// ISO 9660 caps the volume id at 32 characters. Joliet readers show it as
  /// typed, so only length and control characters are policed.
  static const maxLabelLength = 32;

  bool get isEmpty => entries.isEmpty;

  /// True while any folder is still being measured.
  bool get sizing => entries.any((e) => e.bytes == null);

  int get totalBytes => entries.fold(0, (sum, e) => sum + (e.bytes ?? 0));

  int get totalFiles => entries.fold(0, (sum, e) => sum + e.fileCount);

  /// Estimated image size in blocks: each file rounded up to whole sectors,
  /// plus directory records and the fixed ISO/Joliet/Rock Ridge headers.
  /// Exact numbers come from `-print_size` right before burning; this is the
  /// live figure for the capacity bar and errs on the large side.
  int get estimatedBlocks {
    const fixedOverhead = 200;
    final dataBlocks = (totalBytes / sectorSize).ceil();
    // Rounding slack (half a sector per file on average) plus roughly one
    // directory record sector per 20 files across the three name trees.
    final perFile = (totalFiles / 2).ceil() + (totalFiles * 3 / 20).ceil();
    return fixedOverhead + dataBlocks + perFile;
  }

  DiscProject withLabel(String label) => DiscProject(label: label, entries: entries);

  /// Adds sources, skipping ones already present and giving each a unique
  /// root-level name ("photos", "photos (2)", …).
  DiscProject withAdded(Iterable<DiscEntry> added) {
    final next = [...entries];
    for (final e in added) {
      if (next.any((x) => x.sourcePath == e.sourcePath)) continue;
      next.add(e.copyWith(name: uniqueName(e.name, next)));
    }
    return DiscProject(label: label, entries: next);
  }

  DiscProject withoutPath(String sourcePath) =>
      DiscProject(label: label, entries: entries.where((e) => e.sourcePath != sourcePath).toList());

  /// Renames an entry. Returns this project unchanged when [name] is
  /// invalid or already used by another entry.
  DiscProject withRenamed(String sourcePath, String name) {
    final trimmed = name.trim();
    if (validateEntryName(trimmed) != null) return this;
    if (entries.any((e) => e.sourcePath != sourcePath && e.name == trimmed)) {
      return this;
    }
    return DiscProject(
      label: label,
      entries: [for (final e in entries) e.sourcePath == sourcePath ? e.copyWith(name: trimmed) : e],
    );
  }

  DiscProject withSize(String sourcePath, int bytes, int fileCount) => DiscProject(
    label: label,
    entries: [
      for (final e in entries)
        e.sourcePath == sourcePath ? e.copyWith(bytes: bytes, fileCount: fileCount) : e,
    ],
  );

  DiscProject cleared() => DiscProject(label: label);
}

/// Picks [wanted], or "wanted (n)" with the extension kept, so that no two
/// root entries collide.
String uniqueName(String wanted, List<DiscEntry> existing) {
  final taken = existing.map((e) => e.name).toSet();
  if (!taken.contains(wanted)) return wanted;
  final ext = p.extension(wanted);
  final stem = ext.isEmpty ? wanted : wanted.substring(0, wanted.length - ext.length);
  for (var n = 2; ; n++) {
    final candidate = '$stem ($n)$ext';
    if (!taken.contains(candidate)) return candidate;
  }
}

/// Null when [label] is a usable volume label, otherwise the reason.
String? validateLabel(String label) {
  if (label.trim().isEmpty) return 'Enter a disc label';
  if (label.length > DiscProject.maxLabelLength) {
    return 'At most ${DiscProject.maxLabelLength} characters';
  }
  if (label.runes.any((r) => r < 0x20)) return 'No control characters';
  return null;
}

/// Null when [name] can be a root-level file or folder name on the disc.
String? validateEntryName(String name) {
  if (name.isEmpty) return 'Name cannot be empty';
  if (name == '.' || name == '..') return 'Not a valid name';
  if (name.contains('/')) return 'Name cannot contain "/"';
  if (name.runes.any((r) => r < 0x20)) return 'No control characters';
  // Joliet stores names as UCS-2 and xorriso truncates past 103 characters
  // even with -joliet-long; Rock Ridge would keep it, Windows would not.
  if (name.length > 103) return 'At most 103 characters';
  return null;
}

/// Measures a source: (bytes, fileCount). Symlinks are not followed, which
/// matches how xorriso maps them (as links, not their targets). Unreadable
/// subdirectories are skipped rather than failing the whole count.
Future<(int, int)> measurePath(String path) async {
  final type = await FileSystemEntity.type(path, followLinks: false);
  if (type == FileSystemEntityType.file) {
    return (await File(path).length(), 1);
  }
  if (type != FileSystemEntityType.directory) return (0, 1);
  var bytes = 0, files = 0;
  final stream = Directory(
    path,
  ).list(recursive: true, followLinks: false).handleError((_) {}, test: (e) => e is FileSystemException);
  await for (final entity in stream) {
    files++;
    if (entity is File) {
      try {
        bytes += await entity.length();
      } on FileSystemException {
        // Vanished or unreadable mid-walk; xorriso will report it properly.
      }
    }
  }
  return (bytes, files);
}

/// Builds an unmeasured entry for [path]. A symlink the user picked directly
/// is resolved so its target's contents get burned (links *inside* folders
/// stay links), but the entry keeps the name the user saw.
DiscEntry entryFor(String path) {
  final normalized = p.normalize(p.absolute(path));
  var source = normalized;
  try {
    source = File(normalized).resolveSymbolicLinksSync();
  } on FileSystemException {
    // Dangling link: keep the path and let xorriso report it.
  }
  return DiscEntry(
    sourcePath: source,
    name: p.basename(normalized),
    isDirectory: FileSystemEntity.isDirectorySync(source),
  );
}

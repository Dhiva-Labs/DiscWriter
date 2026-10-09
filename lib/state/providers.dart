import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../burn/commands.dart';
import '../burn/jobs.dart';
import '../burn/models.dart';
import '../burn/xorriso.dart';
import '../project/disc_project.dart';

/// The xorriso the app drives, or null when it is not installed.
final xorrisoProvider = Provider<Xorriso?>((ref) {
  final exe = Xorriso.locate();
  return exe == null ? null : Xorriso(exe);
});

final xorrisoVersionProvider = FutureProvider<String?>((ref) async {
  final x = ref.watch(xorrisoProvider);
  return x?.version();
});

/// File-backed drives the user added by hand (Drive menu → "Use image file
/// as drive"). Handy for rehearsing a burn without wasting a disc.
final imageFileDrivesProvider = StateProvider<List<Drive>>((ref) => const []);

/// Real drives xorriso can open, plus any the kernel sees that xorriso
/// can't (usually a permissions problem — surfaced in the Disc info page).
class DrivesNotifier extends AsyncNotifier<List<Drive>> {
  @override
  Future<List<Drive>> build() async {
    final manual = ref.watch(imageFileDrivesProvider);
    final x = ref.watch(xorrisoProvider);
    final found = x == null ? <Drive>[] : await x.devices();
    for (final d in sysfsDrives()) {
      if (!found.contains(d)) found.add(d);
    }
    return [...found, ...manual];
  }

  Future<void> rescan() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }
}

final drivesProvider = AsyncNotifierProvider<DrivesNotifier, List<Drive>>(DrivesNotifier.new);

/// The drive the user picked; falls back to the first one found.
final selectedDriveAddressProvider = StateProvider<String?>((ref) => null);

final selectedDriveProvider = Provider<Drive?>((ref) {
  final drives = ref.watch(drivesProvider).valueOrNull ?? const [];
  if (drives.isEmpty) return null;
  final wanted = ref.watch(selectedDriveAddressProvider);
  return drives.firstWhere((d) => d.address == wanted, orElse: () => drives.first);
});

/// Kernel-visible drives xorriso could not open: the user is probably not
/// in the `cdrom` group (or the snap lacks the optical-drive interface).
final inaccessibleDrivesProvider = Provider<List<Drive>>((ref) {
  final drives = ref.watch(drivesProvider).valueOrNull ?? const [];
  return [
    for (final d in drives)
      if (!d.isImageFile && d.permissions.isEmpty) d,
  ];
});

/// What is in the selected drive. Refreshed on demand and after every job —
/// polling `-toc` would keep grabbing the drive and spinning the disc.
class MediaNotifier extends AsyncNotifier<MediaInfo> {
  @override
  Future<MediaInfo> build() async {
    final drive = ref.watch(selectedDriveProvider);
    final x = ref.watch(xorrisoProvider);
    if (drive == null || x == null) return MediaInfo.none;
    // A busy drive is common for a second after a tray closes; retry once.
    try {
      return await x.toc(drive);
    } on XorrisoException {
      await Future<void>.delayed(const Duration(seconds: 2));
      return x.toc(drive);
    }
  }

  Future<void> refresh() async {
    state = const AsyncLoading<MediaInfo>().copyWithPrevious(state);
    state = await AsyncValue.guard(build);
  }
}

final mediaProvider = AsyncNotifierProvider<MediaNotifier, MediaInfo>(MediaNotifier.new);

/// Capacity of the selected disc in blocks, or of [capacityPresetProvider]
/// when no disc (or an image-file drive) is in use.
final capacityPresetProvider = StateProvider<CapacityPreset>((ref) => CapacityPreset.dvd5);

final capacityBlocksProvider = Provider<int>((ref) {
  final media = ref.watch(mediaProvider).valueOrNull;
  if (media != null && media.present && media.family != DiscFamily.file) {
    final w = media.writableBlocks;
    if (w != null) return w;
  }
  return ref.watch(capacityPresetProvider).blocks;
});

/// The data disc being assembled. Adding entries kicks off background size
/// measurement; results land via [DiscProject.withSize].
class ProjectNotifier extends Notifier<DiscProject> {
  @override
  DiscProject build() => const DiscProject();

  void setLabel(String label) => state = state.withLabel(label);

  void addPaths(Iterable<String> paths) {
    final entries = [
      for (final path in paths)
        if (FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound) entryFor(path),
    ];
    final before = state.entries.map((e) => e.sourcePath).toSet();
    state = state.withAdded(entries);
    for (final e in state.entries) {
      if (!before.contains(e.sourcePath) && e.bytes == null) _measure(e.sourcePath);
    }
  }

  Future<void> _measure(String path) async {
    final (bytes, files) = await measurePath(path);
    // The entry may have been removed while it was being measured.
    if (state.entries.any((e) => e.sourcePath == path)) {
      state = state.withSize(path, bytes, files);
    }
  }

  void remove(String sourcePath) => state = state.withoutPath(sourcePath);

  bool rename(String sourcePath, String name) {
    final next = state.withRenamed(sourcePath, name);
    final changed = !identical(next, state);
    state = next;
    return changed;
  }

  void clear() => state = state.cleared();
}

final projectProvider = NotifierProvider<ProjectNotifier, DiscProject>(ProjectNotifier.new);

final burnOptionsProvider = StateProvider<BurnOptions>((ref) => const BurnOptions());

/// Image picked on the Burn Image page.
final imagePathProvider = StateProvider<String?>((ref) => null);

/// The one job that may run at a time. Null when idle.
class JobNotifier extends Notifier<JobState?> {
  JobRunner? _runner;

  @override
  JobState? build() => null;

  bool get busy => state != null && !state!.finished;

  Future<JobState?> start(String title, List<JobStep> steps) async {
    final x = ref.read(xorrisoProvider);
    if (x == null || busy) return null;
    final runner = JobRunner(
      xorriso: x,
      title: title,
      steps: steps,
      onUpdate: (s) => state = s,
    );
    _runner = runner;
    final result = await runner.run();
    _runner = null;
    // The disc changed (or was ejected); re-read it.
    unawaited(ref.read(mediaProvider.notifier).refresh());
    return result;
  }

  void cancel() => _runner?.cancel();

  void dismiss() {
    if (!busy) state = null;
  }
}

final jobProvider = NotifierProvider<JobNotifier, JobState?>(JobNotifier.new);

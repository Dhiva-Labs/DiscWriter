import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../burn/iso_info.dart';
import '../burn/models.dart';
import '../burn/plans.dart';
import '../state/providers.dart';
import 'job_dialog.dart';
import 'widgets.dart';

final _imageInfoProvider = FutureProvider.autoDispose<DiscImageInfo?>((ref) async {
  final path = ref.watch(imagePathProvider);
  return path == null ? null : readImageInfo(path);
});

class ImagePage extends ConsumerStatefulWidget {
  const ImagePage({super.key});

  @override
  ConsumerState<ImagePage> createState() => _ImagePageState();
}

class _ImagePageState extends ConsumerState<ImagePage> {
  var _dragging = false;

  Future<void> _pick() async {
    final f = await openFile(acceptedTypeGroups: const [
      XTypeGroup(label: 'Disc images', extensions: ['iso', 'img']),
      XTypeGroup(label: 'All files'),
    ]);
    if (f != null) ref.read(imagePathProvider.notifier).state = f.path;
  }

  Future<void> _burn() async {
    final x = ref.read(xorrisoProvider)!;
    final path = ref.read(imagePathProvider)!;
    final drive = ref.read(selectedDriveProvider)!;
    final media = ref.read(mediaProvider).value!;
    final opts = ref.read(burnOptionsProvider);
    final verb = opts.simulate ? 'Simulating' : 'Burning';
    await runJobWithDialog(context, ref, '$verb ${p.basename(path)}',
        burnImagePlan(x, path, drive, media, opts));
  }

  @override
  Widget build(BuildContext context) {
    final path = ref.watch(imagePathProvider);
    final info = ref.watch(_imageInfoProvider);
    final capacity = ref.watch(capacityBlocksProvider);
    final busy = ref.watch(jobProvider.select((j) => j != null && !j.finished));
    final theme = Theme.of(context);

    final imageBlocks = info.valueOrNull == null ? null : (info.value!.bytes / sectorSize).ceil();
    final blocker = path == null
        ? 'Choose an image to burn'
        : info.hasError
            ? 'The image cannot be read'
            : driveBlocker(ref) ??
                ((imageBlocks ?? 0) > capacity ? 'The image is larger than the disc' : null);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: DropTarget(
              enable: !busy,
              onDragEntered: (_) => setState(() => _dragging = true),
              onDragExited: (_) => setState(() => _dragging = false),
              onDragDone: (d) {
                setState(() => _dragging = false);
                if (d.files.isNotEmpty) ref.read(imagePathProvider.notifier).state = d.files.first.path;
              },
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _dragging ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
                    width: _dragging ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(Icons.album_outlined, size: 64, color: theme.colorScheme.outline),
                        const SizedBox(height: 12),
                        if (path == null) ...[
                          Text('Drop an ISO image here', textAlign: TextAlign.center,
                              style: theme.textTheme.titleMedium),
                          const SizedBox(height: 4),
                          Text('Linux installers, backups, anything saved as .iso or .img',
                              textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
                        ] else ...[
                          Text(p.basename(path), textAlign: TextAlign.center,
                              style: theme.textTheme.titleMedium),
                          const SizedBox(height: 4),
                          Text(p.dirname(path), textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
                          const SizedBox(height: 12),
                          info.when(
                            loading: () => const LinearProgressIndicator(),
                            error: (e, _) => Text('$e', style: TextStyle(color: theme.colorScheme.error)),
                            data: (i) => i == null
                                ? const SizedBox.shrink()
                                : Text(
                                    [
                                      formatBytes(i.bytes),
                                      if (i.isIso) 'ISO 9660 · "${i.volumeId}"'
                                      else 'Not an ISO 9660 image — it will be copied as-is',
                                    ].join('  ·  '),
                                    textAlign: TextAlign.center,
                                  ),
                          ),
                          if (imageBlocks != null) ...[
                            const SizedBox(height: 20),
                            CapacityBar(usedBlocks: imageBlocks, capacityBlocks: capacity),
                          ],
                        ],
                        const SizedBox(height: 20),
                        Center(
                          child: OutlinedButton.icon(
                            onPressed: busy ? null : _pick,
                            icon: const Icon(Icons.folder_open),
                            label: Text(path == null ? 'Choose image…' : 'Choose another…'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        SizedBox(
          width: 320,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const BurnOptionsPanel(),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: busy || blocker != null ? null : _burn,
                  icon: const Icon(Icons.local_fire_department_outlined),
                  label: Text(ref.watch(burnOptionsProvider).simulate ? 'Simulate burn' : 'Burn image'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                ),
                const SizedBox(height: 10),
                BlockedReason(blocker),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

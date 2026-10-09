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
import 'theme.dart';
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
    final f = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Disc images', extensions: ['iso', 'img']),
        XTypeGroup(label: 'All files'),
      ],
    );
    if (f != null) ref.read(imagePathProvider.notifier).state = f.path;
  }

  Future<void> _burn() async {
    final x = ref.read(xorrisoProvider)!;
    final path = ref.read(imagePathProvider)!;
    final drive = ref.read(selectedDriveProvider)!;
    final media = ref.read(mediaProvider).value!;
    final opts = ref.read(burnOptionsProvider);
    final verb = opts.simulate ? 'Simulating' : 'Burning';
    await runJobWithDialog(
      context,
      ref,
      '$verb ${p.basename(path)}',
      burnImagePlan(x, path, drive, media, opts),
    );
  }

  @override
  Widget build(BuildContext context) {
    final path = ref.watch(imagePathProvider);
    final info = ref.watch(_imageInfoProvider);
    final capacity = ref.watch(capacityBlocksProvider);
    final busy = ref.watch(jobProvider.select((j) => j != null && !j.finished));
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = DiscColors.of(context);

    final imageBlocks = info.valueOrNull == null ? 0 : (info.value!.bytes / sectorSize).ceil();
    final blocker = path == null
        ? 'Choose an image to burn'
        : info.hasError
        ? 'The image cannot be read'
        : driveBlocker(ref) ?? (imageBlocks > capacity ? 'The image is larger than the disc' : null);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const PageHeader(
                title: 'Burn image',
                subtitle:
                    'Write an .iso or .img file to disc exactly as it is — bootable installers stay bootable.',
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                  child: DropTarget(
                    enable: !busy,
                    onDragEntered: (_) => setState(() => _dragging = true),
                    onDragExited: (_) => setState(() => _dragging = false),
                    onDragDone: (d) {
                      setState(() => _dragging = false);
                      if (d.files.isNotEmpty) ref.read(imagePathProvider.notifier).state = d.files.first.path;
                    },
                    child: DropSurface(
                      active: _dragging,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: path == null
                              ? Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 76,
                                      height: 76,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: colors.laserSoft,
                                      ),
                                      child: Icon(Icons.album_outlined, size: 36, color: colors.laser),
                                    ),
                                    const SizedBox(height: 18),
                                    Text('Drop a disc image here', style: theme.textTheme.titleMedium),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Linux installers, backups — anything saved as .iso or .img',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 18),
                                    TextButton(
                                      onPressed: busy ? null : _pick,
                                      child: const Text('Choose image…'),
                                    ),
                                  ],
                                )
                              : _ImageCard(path: path, info: info, busy: busy, onPick: _pick),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        SidePanel(
          children: [
            DiscSummary(neededBlocks: imageBlocks),
            const SizedBox(height: 20),
            const SectionLabel('Options'),
            const BurnOptionsPanel(),
            const SizedBox(height: 20),
            BurnButton(
              label: ref.watch(burnOptionsProvider).simulate ? 'Simulate burn' : 'Burn image',
              onPressed: busy || blocker != null ? null : _burn,
            ),
            BlockedReason(blocker),
          ],
        ),
      ],
    );
  }
}

class _ImageCard extends StatelessWidget {
  final String path;
  final AsyncValue<DiscImageInfo?> info;
  final bool busy;
  final VoidCallback onPick;

  const _ImageCard({required this.path, required this.info, required this.busy, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = DiscColors.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Card(
        color: scheme.surfaceContainer,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: colors.laserSoft, borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.album, color: colors.laser, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.basename(path),
                      style: theme.textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      p.dirname(path),
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 14),
                    info.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (e, _) => Text('$e', style: TextStyle(color: scheme.error)),
                      data: (i) => i == null
                          ? const SizedBox.shrink()
                          : Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _Tag(formatBytes(i.bytes)),
                                if (i.isIso) _Tag('ISO 9660'),
                                if (i.isIso && i.volumeId!.isNotEmpty) _Tag('“${i.volumeId}”'),
                                if (!i.isIso) _Tag('Raw image — copied as-is'),
                              ],
                            ),
                    ),
                    const SizedBox(height: 14),
                    TextButton.icon(
                      onPressed: busy ? null : onPick,
                      icon: const Icon(Icons.swap_horiz, size: 18),
                      label: const Text('Choose another…'),
                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;

  const _Tag(this.text);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../burn/commands.dart';
import '../burn/models.dart';
import '../burn/xorriso.dart';
import '../state/providers.dart';

/// Drive picker plus what's in it, shown above every page.
class DriveBar extends ConsumerWidget {
  const DriveBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drives = ref.watch(drivesProvider);
    final drive = ref.watch(selectedDriveProvider);
    final media = ref.watch(mediaProvider);
    final busy = ref.watch(jobProvider.select((j) => j != null && !j.finished));
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          Icon(drive?.isImageFile == true ? Icons.insert_drive_file_outlined : Icons.album,
              color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Flexible(
            child: drives.when(
              loading: () => const Text('Looking for drives…'),
              error: (e, _) => Text('Could not list drives: $e'),
              data: (list) => list.isEmpty
                  ? Text('No optical drive found', style: theme.textTheme.titleSmall)
                  : DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: drive?.address,
                        onChanged: busy
                            ? null
                            : (a) => ref.read(selectedDriveAddressProvider.notifier).state = a,
                        items: [
                          for (final d in list)
                            DropdownMenuItem(
                              value: d.address,
                              child: Text(d.label, overflow: TextOverflow.ellipsis),
                            ),
                        ],
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          if (drive != null) _MediaChip(media: media),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Re-read disc',
            onPressed: busy || drive == null ? null : () => ref.read(mediaProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Eject',
            onPressed: busy || drive == null || drive.isImageFile ? null : () => _eject(context, ref, drive),
            icon: const Icon(Icons.eject),
          ),
          PopupMenuButton<_Menu>(
            tooltip: 'More',
            enabled: !busy,
            onSelected: (m) => switch (m) {
              _Menu.rescan => ref.read(drivesProvider.notifier).rescan(),
              _Menu.imageDrive => _addImageDrive(ref),
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: _Menu.rescan, child: Text('Rescan drives')),
              PopupMenuItem(value: _Menu.imageDrive, child: Text('Use an image file as a drive…')),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _eject(BuildContext context, WidgetRef ref, Drive drive) async {
    final x = ref.read(xorrisoProvider);
    if (x == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await x.run(ejectArgs(drive));
    } on XorrisoException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Eject failed: ${e.headline}')));
    }
    await ref.read(mediaProvider.notifier).refresh();
  }

  /// A file stands in for a disc: every burn, verify and erase works on it
  /// exactly as on real media, which makes it the way to rehearse a job.
  Future<void> _addImageDrive(WidgetRef ref) async {
    final location = await getSaveLocation(
      suggestedName: 'test-disc.img',
      confirmButtonText: 'Use as drive',
    );
    if (location == null) return;
    final drive = Drive.imageFile(location.path);
    final current = ref.read(imageFileDrivesProvider);
    if (!current.contains(drive)) {
      ref.read(imageFileDrivesProvider.notifier).state = [...current, drive];
    }
    ref.read(selectedDriveAddressProvider.notifier).state = drive.address;
  }
}

enum _Menu { rescan, imageDrive }

class _MediaChip extends StatelessWidget {
  final AsyncValue<MediaInfo> media;

  const _MediaChip({required this.media});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (media.isLoading) {
      return const Chip(
        avatar: SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2)),
        label: Text('Reading disc…'),
      );
    }
    if (media.hasError) {
      final e = media.error;
      return Tooltip(
        message: e is XorrisoException ? e.headline : '$e',
        child: Chip(
          avatar: Icon(Icons.error_outline, size: 18, color: scheme.error),
          label: const Text('Drive not accessible'),
        ),
      );
    }
    final m = media.value ?? MediaInfo.none;
    return Chip(
      avatar: Icon(
        !m.present
            ? Icons.radio_button_unchecked
            : m.writable
                ? Icons.check_circle_outline
                : Icons.lock_outline,
        size: 18,
        color: m.writable ? scheme.primary : scheme.onSurfaceVariant,
      ),
      label: Text(m.summary),
    );
  }
}

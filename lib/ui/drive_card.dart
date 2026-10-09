import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../burn/commands.dart';
import '../burn/models.dart';
import '../burn/xorriso.dart';
import '../state/providers.dart';
import 'theme.dart';

/// The selected drive and what's in it, pinned to the bottom of the sidebar.
class DriveCard extends ConsumerWidget {
  const DriveCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drives = ref.watch(drivesProvider);
    final drive = ref.watch(selectedDriveProvider);
    final media = ref.watch(mediaProvider);
    final busy = ref.watch(jobProvider.select((j) => j != null && !j.finished));
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = DiscColors.of(context);
    final list = drives.valueOrNull ?? const <Drive>[];

    final (dot, status) = _status(media, drive, colors, scheme);

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('DRIVE', style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
              const Spacer(),
              _IconAction(
                tooltip: 'Re-read disc',
                icon: Icons.refresh,
                onPressed: busy || drive == null ? null : () => ref.read(mediaProvider.notifier).refresh(),
              ),
              _IconAction(
                tooltip: 'Eject',
                icon: Icons.eject,
                onPressed: busy || drive == null || drive.isImageFile
                    ? null
                    : () => _eject(context, ref, drive),
              ),
              PopupMenuButton<_Menu>(
                tooltip: 'More',
                enabled: !busy,
                iconSize: 18,
                icon: const Icon(Icons.more_vert),
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
          if (drives.isLoading && list.isEmpty)
            Text('Looking for drives…', style: theme.textTheme.bodyMedium)
          else if (list.isEmpty)
            Text(
              'No optical drive found',
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            )
          else
            PopupMenuButton<String>(
              enabled: !busy && list.length > 1,
              tooltip: list.length > 1 ? 'Switch drive' : '',
              onSelected: (a) => ref.read(selectedDriveAddressProvider.notifier).state = a,
              itemBuilder: (_) => [
                for (final d in list) PopupMenuItem(value: d.address, child: Text(d.label)),
              ],
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _driveName(drive!),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (list.length > 1) Icon(Icons.unfold_more, size: 16, color: scheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(shape: BoxShape.circle, color: dot),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  status,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _driveName(Drive d) {
    if (d.isImageFile) return d.address.substring(6).split('/').last;
    final name = [d.vendor, d.model].where((s) => s.isNotEmpty).join(' ');
    return name.isEmpty ? d.address : name;
  }

  static (Color, String) _status(
    AsyncValue<MediaInfo> media,
    Drive? drive,
    DiscColors colors,
    ColorScheme scheme,
  ) {
    if (drive == null) return (scheme.outline, 'Plug in a drive, or use an image file');
    if (media.isLoading) return (scheme.outline, 'Reading disc…');
    if (media.hasError) {
      final e = media.error;
      return (scheme.error, e is XorrisoException ? e.headline : 'Drive not accessible');
    }
    final m = media.value ?? MediaInfo.none;
    if (!m.present) return (scheme.outline, 'No disc');
    return (m.writable ? colors.verified : colors.existing, m.summary);
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
    final location = await getSaveLocation(suggestedName: 'test-disc.img', confirmButtonText: 'Use as drive');
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

class _IconAction extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  const _IconAction({required this.tooltip, required this.icon, this.onPressed});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    iconSize: 18,
    visualDensity: VisualDensity.compact,
    icon: Icon(icon),
  );
}

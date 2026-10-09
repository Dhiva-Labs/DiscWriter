import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../burn/models.dart';
import '../burn/plans.dart';
import '../burn/xorriso.dart';
import '../state/providers.dart';
import 'widgets.dart';

class DiscInfoPage extends ConsumerWidget {
  const DiscInfoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drive = ref.watch(selectedDriveProvider);
    final media = ref.watch(mediaProvider);
    final version = ref.watch(xorrisoVersionProvider).valueOrNull;
    final inaccessible = ref.watch(inaccessibleDrivesProvider);
    final x = ref.watch(xorrisoProvider);
    final theme = Theme.of(context);

    Widget row(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(
              k,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(child: SelectableText(v)),
        ],
      ),
    );

    Widget section(String title, List<Widget> children) => Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [SectionLabel(title), ...children],
        ),
      ),
    );

    final m = media.valueOrNull ?? MediaInfo.none;
    final mediaError = media.hasError
        ? (media.error is XorrisoException ? (media.error as XorrisoException).headline : '${media.error}')
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeader(
          title: 'Disc info',
          subtitle: 'What the drive reports about itself and the disc inside it.',
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (inaccessible.isNotEmpty && x != null) ...[
                      Card(
                        color: theme.colorScheme.errorContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Drive found but not accessible',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: theme.colorScheme.onErrorContainer,
                                ),
                              ),
                              const SizedBox(height: 6),
                              SelectableText(
                                '${inaccessible.map((d) => d.address).join(', ')} exists, but xorriso '
                                'cannot open it. Add yourself to the cdrom group and log in again:\n\n'
                                '    sudo usermod -aG cdrom \$USER\n\n'
                                'If Disc Writer is installed as a snap, also run:\n\n'
                                '    sudo snap connect disc-writer:optical-drive',
                                style: TextStyle(color: theme.colorScheme.onErrorContainer),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    section('Drive', [
                      if (drive == null)
                        const Text('No optical drive found. Plug in a USB drive and use "Rescan drives".')
                      else ...[
                        row('Address', drive.address),
                        // xorriso names every file-backed drive "YOYODYNE WARP DRIVE".
                        if (drive.isImageFile)
                          row('Kind', 'Image file standing in for a disc')
                        else ...[
                          if (drive.vendor.isNotEmpty || m.vendor.isNotEmpty)
                            row('Make', m.vendor.isNotEmpty ? m.vendor : drive.vendor),
                          if (drive.model.isNotEmpty || m.model.isNotEmpty)
                            row('Model', m.model.isNotEmpty ? m.model : drive.model),
                        ],
                      ],
                    ]),
                    const SizedBox(height: 12),
                    section('Disc', [
                      if (media.isLoading)
                        const LinearProgressIndicator()
                      else if (mediaError != null)
                        Text(mediaError, style: TextStyle(color: theme.colorScheme.error))
                      else if (!m.present)
                        const Text('No disc in the drive.')
                      else ...[
                        row('Type', m.displayName),
                        row('State', m.summary.split(' · ').last),
                        row('Rewritable', m.erasable ? 'Yes' : 'No'),
                        row('Sessions', '${m.sessions}'),
                        row('Used', formatBlocks(m.dataBlocks)),
                        if (m.writableBlocks != null) row('Free', formatBlocks(m.writableBlocks!)),
                        if (m.volumeId != null) row('Label', m.volumeId!),
                      ],
                    ]),
                    const SizedBox(height: 12),
                    section('Burning engine', [
                      row('xorriso', x == null ? 'Not installed' : (version ?? '…')),
                      if (x != null) row('Path', x.executable),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

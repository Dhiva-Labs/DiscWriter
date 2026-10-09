import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../burn/commands.dart';
import '../burn/models.dart';
import '../burn/plans.dart';
import '../state/providers.dart';
import 'job_dialog.dart';
import 'theme.dart';
import 'widgets.dart';

class ErasePage extends ConsumerStatefulWidget {
  const ErasePage({super.key});

  @override
  ConsumerState<ErasePage> createState() => _ErasePageState();
}

class _ErasePageState extends ConsumerState<ErasePage> {
  var _mode = BlankMode.fast;

  Future<void> _erase(MediaInfo media) async {
    final drive = ref.read(selectedDriveProvider)!;
    final simulate = ref.read(burnOptionsProvider).simulate;
    if (!simulate) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Erase this disc?'),
          content: Text(
            'Everything on the ${media.displayName}'
            '${media.volumeId == null ? '' : ' "${media.volumeId}"'} will be lost.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Erase'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    await runJobWithDialog(
      context,
      ref,
      simulate ? 'Simulating erase' : 'Erasing disc',
      blankPlan(drive, _mode, simulate: simulate),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaAsync = ref.watch(mediaProvider);
    final media = mediaAsync.valueOrNull ?? MediaInfo.none;
    final busy = ref.watch(jobProvider.select((j) => j != null && !j.finished));
    final simulate = ref.watch(burnOptionsProvider).simulate;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    String? blocker;
    if (ref.watch(xorrisoProvider) == null) {
      blocker = 'Install xorriso to erase discs';
    } else if (ref.watch(selectedDriveProvider) == null) {
      blocker = 'No drive selected';
    } else if (mediaAsync.isLoading) {
      blocker = 'Reading the disc…';
    } else if (!media.present) {
      blocker = 'Insert a rewritable disc';
    } else if (!media.erasable) {
      blocker = '${media.profile} is write-once and cannot be erased';
    } else if (media.blank) {
      blocker = 'The disc is already blank';
    }

    final colors = DiscColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeader(
          title: 'Erase',
          subtitle:
              'Wipe a CD-RW, DVD±RW, DVD-RAM or BD-RE so it can be used again. '
              'Write-once discs cannot be erased.',
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SectionLabel('Method'),
                    RadioGroup<BlankMode>(
                      groupValue: _mode,
                      onChanged: (m) => setState(() => _mode = m!),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _ModeCard(
                              mode: BlankMode.fast,
                              selected: _mode == BlankMode.fast,
                              icon: Icons.bolt,
                              title: 'Quick erase',
                              body: 'Makes the disc read as blank. Seconds to a minute.',
                              onTap: () => setState(() => _mode = BlankMode.fast),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _ModeCard(
                              mode: BlankMode.full,
                              selected: _mode == BlankMode.full,
                              icon: Icons.layers_clear_outlined,
                              title: 'Full erase',
                              body:
                                  'Overwrites every sector. As slow as a burn; for misbehaving discs or private data.',
                              onTap: () => setState(() => _mode = BlankMode.full),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Card(
                      child: SwitchListTile(
                        title: const Text('Simulate only'),
                        subtitle: const Text('Run the erase with the laser off'),
                        value: simulate,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        onChanged: busy
                            ? null
                            : (v) => ref.read(burnOptionsProvider.notifier).state = ref
                                  .read(burnOptionsProvider)
                                  .copyWith(simulate: v),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        SizedBox(
                          width: 220,
                          child: BurnButton(
                            label: simulate ? 'Simulate erase' : 'Erase disc',
                            icon: Icons.cleaning_services,
                            color: simulate ? null : scheme.error,
                            onPressed: busy || blocker != null ? null : () => _erase(media),
                          ),
                        ),
                        const SizedBox(width: 16),
                        if (media.present && media.dataBlocks > 0)
                          Row(
                            children: [
                              Icon(Icons.storage, size: 16, color: colors.existing),
                              const SizedBox(width: 6),
                              Text(
                                '${formatBlocks(media.dataBlocks)} on the disc now',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                      ],
                    ),
                    Align(alignment: Alignment.centerLeft, child: BlockedReason(blocker)),
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

class _ModeCard extends StatelessWidget {
  final BlankMode mode;
  final bool selected;
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  const _ModeCard({
    required this.mode,
    required this.selected,
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = DiscColors.of(context);
    return Material(
      color: selected ? colors.laserSoft : scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: selected ? colors.laser : scheme.outlineVariant, width: selected ? 1.5 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: selected ? colors.laser : scheme.onSurfaceVariant),
                  const Spacer(),
                  Radio<BlankMode>(value: mode),
                ],
              ),
              const SizedBox(height: 6),
              Text(title, style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(body, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

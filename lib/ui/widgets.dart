import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../burn/commands.dart';
import '../burn/models.dart';
import '../burn/plans.dart';
import '../state/providers.dart';

/// How full the disc will be. [usedBlocks] can exceed [capacityBlocks]; the
/// overflow is called out in the error colour.
class CapacityBar extends StatelessWidget {
  final int usedBlocks;
  final int capacityBlocks;
  final bool estimating;

  const CapacityBar({
    super.key,
    required this.usedBlocks,
    required this.capacityBlocks,
    this.estimating = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ratio = capacityBlocks == 0 ? 0.0 : usedBlocks / capacityBlocks;
    final over = usedBlocks > capacityBlocks;
    final color = over
        ? scheme.error
        : ratio > 0.9
            ? Colors.orange.shade700
            : scheme.primary;

    final label = over
        ? 'Too big by ${formatBlocks(usedBlocks - capacityBlocks)}'
        : '${formatBlocks(usedBlocks)} of ${formatBlocks(capacityBlocks)}'
            ' · ${(ratio * 100).toStringAsFixed(0)}%';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 14,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: scheme.surfaceContainerHighest),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: ratio.clamp(0.0, 1.0),
                  child: ColoredBox(color: color),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: over ? scheme.error : null,
                  fontWeight: over ? FontWeight.w600 : null,
                )),
            if (estimating) ...[
              const SizedBox(width: 8),
              const SizedBox.square(dimension: 10, child: CircularProgressIndicator(strokeWidth: 1.5)),
              const SizedBox(width: 6),
              Text('measuring…', style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ],
    );
  }
}

/// Speed, simulate, verify, close, erase-first and eject switches. Options
/// that make no sense for the inserted media are hidden rather than greyed.
class BurnOptionsPanel extends ConsumerWidget {
  const BurnOptionsPanel({super.key});

  static const _speeds = {
    DiscFamily.cd: [4, 8, 16, 24, 32, 48],
    DiscFamily.dvd: [2, 4, 8, 16],
    DiscFamily.bd: [2, 4, 6, 8, 12],
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final opts = ref.watch(burnOptionsProvider);
    final media = ref.watch(mediaProvider).valueOrNull ?? MediaInfo.none;
    final busy = ref.watch(jobProvider.select((j) => j != null && !j.finished));
    void set(BurnOptions o) => ref.read(burnOptionsProvider.notifier).state = o;
    final speeds = _speeds[media.family] ?? _speeds[DiscFamily.cd]!;
    final showErase = media.present && media.erasable && !media.blank;

    Widget toggle(String title, String subtitle, bool value, void Function(bool) onChanged) =>
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(title),
          subtitle: Text(subtitle),
          value: value,
          onChanged: busy ? null : onChanged,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Options', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        DropdownButtonFormField<int?>(
          initialValue: speeds.contains(opts.speed) ? opts.speed : null,
          decoration: const InputDecoration(labelText: 'Write speed'),
          onChanged: busy ? null : (s) => set(opts.copyWith(speed: () => s)),
          items: [
            const DropdownMenuItem(value: null, child: Text('Fastest the drive allows')),
            for (final s in speeds) DropdownMenuItem(value: s, child: Text('${s}x')),
          ],
        ),
        const SizedBox(height: 4),
        toggle('Verify after writing', 'Read the disc back and compare', opts.verify,
            (v) => set(opts.copyWith(verify: v))),
        toggle('Close the disc', 'Nothing can be added later; plays in more drives',
            opts.closeDisc, (v) => set(opts.copyWith(closeDisc: v))),
        if (showErase)
          toggle('Erase the disc first', 'Replace what is on it instead of adding to it',
              opts.eraseFirst, (v) => set(opts.copyWith(eraseFirst: v))),
        toggle('Simulate only', 'Laser off — test the run without writing', opts.simulate,
            (v) => set(opts.copyWith(simulate: v))),
        toggle('Eject when done', '', opts.eject, (v) => set(opts.copyWith(eject: v))),
      ],
    );
  }
}

/// A row of muted text explaining why the main action is disabled.
class BlockedReason extends StatelessWidget {
  final String? reason;

  const BlockedReason(this.reason, {super.key});

  @override
  Widget build(BuildContext context) {
    if (reason == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.info_outline, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Flexible(
          child: Text(reason!,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
      ],
    );
  }
}

/// Why a burn to the current drive can't start, or null when it can.
String? driveBlocker(WidgetRef ref) {
  if (ref.watch(xorrisoProvider) == null) return 'Install xorriso to burn discs';
  final drive = ref.watch(selectedDriveProvider);
  if (drive == null) return 'No drive selected';
  final media = ref.watch(mediaProvider);
  if (media.isLoading) return 'Reading the disc…';
  if (media.hasError) return 'The drive could not be opened — see Disc info';
  final m = media.value!;
  if (!m.present) return 'Insert a disc';
  final opts = ref.watch(burnOptionsProvider);
  if (!m.writable && !(opts.eraseFirst && m.erasable)) {
    return m.erasable
        ? 'The disc is full or closed — erase it, or turn on "Erase the disc first"'
        : 'The disc is closed and cannot take more data';
  }
  return null;
}

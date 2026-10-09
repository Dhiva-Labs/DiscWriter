import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../burn/commands.dart';
import '../burn/models.dart';
import '../burn/plans.dart';
import '../state/providers.dart';
import 'disc_gauge.dart';
import 'theme.dart';

/// Title, one-line explanation and optional actions at the top of a page.
class PageHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> actions;

  const PageHeader({super.key, required this.title, required this.subtitle, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          for (final a in actions) ...[const SizedBox(width: 10), a],
        ],
      ),
    );
  }
}

/// Small caps label above a group of controls.
class SectionLabel extends StatelessWidget {
  final String text;

  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

/// The disc gauge with the size readout under it; shared by the data and
/// image pages. [neededBlocks] is what the job will write.
class DiscSummary extends ConsumerWidget {
  final int neededBlocks;
  final bool estimating;
  final bool allowPresetChoice;

  const DiscSummary({
    super.key,
    required this.neededBlocks,
    this.estimating = false,
    this.allowPresetChoice = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final capacity = ref.watch(capacityBlocksProvider);
    final media = ref.watch(mediaProvider).valueOrNull;
    final usingPreset = media == null || !media.present || media.family == DiscFamily.file;
    final opts = ref.watch(burnOptionsProvider);
    final keepsExisting = !usingPreset && media.appendable && !media.blank && !opts.eraseFirst;
    // On an appendable disc, `capacity` is already the free space; show the
    // old sessions as a grey inner band of the same disc.
    final existingBlocks = keepsExisting ? media.dataBlocks : 0;
    final whole = capacity + existingBlocks;
    final existingFraction = whole == 0 ? 0.0 : existingBlocks / whole;
    final newFraction = whole == 0 ? 0.0 : neededBlocks / whole;
    final over = neededBlocks > capacity;
    final pct = capacity == 0 ? 0 : (neededBlocks / capacity * 100);

    return Column(
      children: [
        DiscGauge(size: 190, existingFraction: existingFraction, newFraction: newFraction),
        const SizedBox(height: 12),
        Text(
          over ? 'Too big' : '${pct.toStringAsFixed(pct < 10 && pct > 0 ? 1 : 0)}%',
          style: theme.textTheme.headlineSmall?.copyWith(
            color: over ? scheme.error : null,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              formatBlocks(neededBlocks),
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            Text(
              ' of ${formatBlocks(capacity)} free',
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (estimating) ...[
              const SizedBox(width: 8),
              const SizedBox.square(dimension: 10, child: CircularProgressIndicator(strokeWidth: 1.5)),
            ],
          ],
        ),
        if (over)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${formatBlocks(neededBlocks - capacity)} over',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.error, fontWeight: FontWeight.w600),
            ),
          ),
        const SizedBox(height: 6),
        if (usingPreset && allowPresetChoice)
          DropdownButton<CapacityPreset>(
            value: ref.watch(capacityPresetProvider),
            isDense: true,
            underline: const SizedBox.shrink(),
            borderRadius: BorderRadius.circular(10),
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            onChanged: (p) => ref.read(capacityPresetProvider.notifier).state = p!,
            items: [
              for (final p in CapacityPreset.values)
                DropdownMenuItem(value: p, child: Text('Sized for ${p.label}')),
            ],
          )
        else if (media != null && media.present)
          Text(
            keepsExisting
                ? '${media.displayName} · ${formatBlocks(existingBlocks)} already on it'
                : '${media.displayName} · ${formatBlocks(capacity)} free',
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
      ],
    );
  }
}

/// Speed and the burn switches as a compact list. Options that make no
/// sense for the inserted media are hidden rather than greyed out.
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
    final theme = Theme.of(context);
    void set(BurnOptions o) => ref.read(burnOptionsProvider.notifier).state = o;
    final speeds = _speeds[media.family] ?? _speeds[DiscFamily.cd]!;
    final showErase = media.present && media.erasable && !media.blank;

    final rows = <Widget>[
      _OptionRow(
        title: 'Write speed',
        trailing: DropdownButton<int?>(
          value: speeds.contains(opts.speed) ? opts.speed : null,
          isDense: true,
          underline: const SizedBox.shrink(),
          borderRadius: BorderRadius.circular(10),
          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          onChanged: busy ? null : (s) => set(opts.copyWith(speed: () => s)),
          items: [
            const DropdownMenuItem(value: null, child: Text('Max')),
            for (final s in speeds) DropdownMenuItem(value: s, child: Text('${s}x')),
          ],
        ),
      ),
      _SwitchRow(
        'Verify after writing',
        'Read back and compare',
        opts.verify,
        busy,
        (v) => set(opts.copyWith(verify: v)),
      ),
      _SwitchRow(
        'Close the disc',
        'No more sessions; plays in more drives',
        opts.closeDisc,
        busy,
        (v) => set(opts.copyWith(closeDisc: v)),
      ),
      if (showErase)
        _SwitchRow(
          'Erase the disc first',
          'Replace instead of adding',
          opts.eraseFirst,
          busy,
          (v) => set(opts.copyWith(eraseFirst: v)),
        ),
      _SwitchRow(
        'Simulate only',
        'Laser off — nothing is written',
        opts.simulate,
        busy,
        (v) => set(opts.copyWith(simulate: v)),
      ),
      _SwitchRow('Eject when done', null, opts.eject, busy, (v) => set(opts.copyWith(eject: v))),
    ];

    return Card(
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(indent: 14, endIndent: 14),
            rows[i],
          ],
        ],
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget trailing;

  const _OptionRow({required this.title, this.subtitle, required this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 9, 10, 9),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final bool busy;
  final ValueChanged<bool> onChanged;

  const _SwitchRow(this.title, this.subtitle, this.value, this.busy, this.onChanged);

  @override
  Widget build(BuildContext context) => _OptionRow(
    title: title,
    subtitle: subtitle,
    trailing: Transform.scale(
      scale: 0.82,
      child: Switch(value: value, onChanged: busy ? null : onChanged),
    ),
  );
}

/// The big primary action at the bottom of the side panel.
class BurnButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;

  const BurnButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.local_fire_department,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: Text(label),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        backgroundColor: color,
        foregroundColor: color == null ? null : Colors.white,
      ),
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
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.info_outline, size: 15, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              reason!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// A rounded dashed-look drop area that lights up while something hovers.
class DropSurface extends StatelessWidget {
  final bool active;
  final Widget child;

  const DropSurface({super.key, required this.active, required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = DiscColors.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      decoration: BoxDecoration(
        color: active ? colors.laserSoft : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: active ? colors.laser : scheme.outlineVariant, width: active ? 2 : 1),
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(15), child: child),
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

/// Fixed-width right-hand column holding the gauge, options and actions.
class SidePanel extends StatelessWidget {
  final List<Widget> children;

  const SidePanel({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 340,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border(left: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 28, 22, 22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      ),
    );
  }
}

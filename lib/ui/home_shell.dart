import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import 'data_disc_page.dart';
import 'disc_info_page.dart';
import 'drive_card.dart';
import 'erase_page.dart';
import 'image_page.dart';
import 'theme.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  var _index = 0;

  static const _pages = [
    (Icons.album_outlined, 'Data disc'),
    (Icons.file_copy_outlined, 'Burn image'),
    (Icons.cleaning_services_outlined, 'Erase'),
    (Icons.info_outline, 'Disc info'),
  ];

  @override
  Widget build(BuildContext context) {
    final xorriso = ref.watch(xorrisoProvider);
    final colors = DiscColors.of(context);

    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 264,
            decoration: BoxDecoration(
              color: colors.sidebar,
              border: Border(right: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Brand(),
                const SizedBox(height: 8),
                for (var i = 0; i < _pages.length; i++)
                  _NavItem(
                    icon: _pages[i].$1,
                    label: _pages[i].$2,
                    selected: i == _index,
                    onTap: () => setState(() => _index = i),
                  ),
                const Spacer(),
                const _ThemeToggle(),
                const Padding(padding: EdgeInsets.fromLTRB(12, 4, 12, 12), child: DriveCard()),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (xorriso == null) const _MissingXorrisoBanner(),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: KeyedSubtree(
                      key: ValueKey(_index),
                      child: switch (_index) {
                        0 => const DataDiscPage(),
                        1 => const ImagePage(),
                        2 => const ErasePage(),
                        _ => const DiscInfoPage(),
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    final colors = DiscColors.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: SweepGradient(
                colors: [
                  colors.laser,
                  const Color(0xFFFFB86B),
                  const Color(0xFFA0E9FF),
                  const Color(0xFFC29BFF),
                  colors.laser,
                ],
              ),
            ),
            child: Center(
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(shape: BoxShape.circle, color: colors.sidebar),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text('Disc Writer', style: theme.textTheme.titleLarge),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({required this.icon, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = DiscColors.of(context);
    final fg = selected ? scheme.onSurface : scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: selected ? scheme.surfaceContainerHigh : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(icon, size: 20, color: selected ? colors.laser : fg),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeToggle extends ConsumerWidget {
  const _ThemeToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () =>
              ref.read(themeModeProvider.notifier).state = dark ? ThemeMode.light : ThemeMode.dark,
          icon: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, size: 18),
          label: Text(dark ? 'Light theme' : 'Dark theme'),
          style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _MissingXorrisoBanner extends StatelessWidget {
  const _MissingXorrisoBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.warning_amber, color: scheme.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: SelectableText(
              'xorriso is not installed, so nothing can be burned. '
              'Install it with  sudo apt install xorriso  and restart Disc Writer.',
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

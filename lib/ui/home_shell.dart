import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import 'data_disc_page.dart';
import 'disc_info_page.dart';
import 'drive_bar.dart';
import 'erase_page.dart';
import 'image_page.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  var _index = 0;

  static const _pages = [
    (Icons.album_outlined, Icons.album, 'Data disc'),
    (Icons.file_copy_outlined, Icons.file_copy, 'Burn image'),
    (Icons.cleaning_services_outlined, Icons.cleaning_services, 'Erase'),
    (Icons.info_outline, Icons.info, 'Disc info'),
  ];

  @override
  Widget build(BuildContext context) {
    final xorriso = ref.watch(xorrisoProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 16),
              child: Icon(Icons.radio_button_checked, size: 36, color: scheme.primary),
            ),
            destinations: [
              for (final (icon, selected, label) in _pages)
                NavigationRailDestination(
                  icon: Icon(icon),
                  selectedIcon: Icon(selected),
                  label: Text(label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (xorriso == null) const _MissingXorrisoBanner(),
                const DriveBar(),
                const Divider(height: 1),
                Expanded(
                  child: switch (_index) {
                    0 => const DataDiscPage(),
                    1 => const ImagePage(),
                    2 => const ErasePage(),
                    _ => const DiscInfoPage(),
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MissingXorrisoBanner extends StatelessWidget {
  const _MissingXorrisoBanner();

  @override
  Widget build(BuildContext context) {
    return MaterialBanner(
      leading: const Icon(Icons.warning_amber),
      content: const Text(
        'xorriso is not installed, so nothing can be burned. '
        'Install it with:  sudo apt install xorriso  — then restart Disc Writer.',
      ),
      actions: const [SizedBox.shrink()],
    );
  }
}

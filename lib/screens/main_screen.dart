import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'journal_screen.dart';
import 'notes_screen.dart';
import 'settings_screen.dart';
import 'tracker_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _index = 0;

  // Last index is Settings — rendered specially on macOS (rail trailing slot)
  // and as the rightmost item on mobile NavigationBar.
  static const _destinations = <_Destination>[
    _Destination('Tasks', Icons.check_circle_outline, Icons.check_circle),
    _Destination('Notes', Icons.notes_outlined, Icons.notes),
    _Destination('Journal', Icons.book_outlined, Icons.book),
    _Destination('Tracker', Icons.show_chart_outlined, Icons.show_chart),
    _Destination('Settings', Icons.settings_outlined, Icons.settings),
  ];

  static const _settingsIndex = 4;

  Widget _screenAt(int i) => switch (i) {
        0 => const HomeScreen(),
        1 => const NotesScreen(),
        2 => const JournalScreen(),
        3 => const TrackerScreen(),
        4 => const SettingsScreen(),
        _ => const HomeScreen(),
      };

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final useRail = platform == TargetPlatform.macOS ||
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux;

    final stack = IndexedStack(
      index: _index,
      children: List.generate(_destinations.length, _screenAt),
    );

    if (useRail) {
      // Main destinations exclude Settings; Settings goes in the trailing slot.
      final mainDestinations =
          _destinations.sublist(0, _destinations.length - 1);
      final settings = _destinations[_settingsIndex];
      final railSelectedIndex =
          _index == _settingsIndex ? null : _index;

      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: railSelectedIndex,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final d in mainDestinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  ),
              ],
              trailing: Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: IconButton(
                      icon: Icon(
                        _index == _settingsIndex
                            ? settings.selectedIcon
                            : settings.icon,
                        color: _index == _settingsIndex
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      tooltip: settings.label,
                      onPressed: () =>
                          setState(() => _index = _settingsIndex),
                    ),
                  ),
                ),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: stack),
          ],
        ),
      );
    }

    return Scaffold(
      body: stack,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final d in _destinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
            ),
        ],
      ),
    );
  }
}

class _Destination {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  const _Destination(this.label, this.icon, this.selectedIcon);
}

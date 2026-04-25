import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/supabase_provider.dart';
import '../providers/theme_provider.dart';
import 'calendar_screen.dart';
import 'home_screen.dart';
import 'journal_screen.dart';
import 'notes_screen.dart';
import 'tracker_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _index = 0;

  static const _destinations = <_Destination>[
    _Destination('Tasks', Icons.check_circle_outline, Icons.check_circle),
    _Destination('Calendar', Icons.calendar_month_outlined, Icons.calendar_month),
    _Destination('Notes', Icons.notes_outlined, Icons.notes),
    _Destination('Journal', Icons.book_outlined, Icons.book),
    _Destination('Tracker', Icons.show_chart_outlined, Icons.show_chart),
  ];

  Widget _screenAt(int i) => switch (i) {
        0 => const HomeScreen(),
        1 => const _CalendarWrapper(),
        2 => const NotesScreen(),
        3 => const JournalScreen(),
        4 => const TrackerScreen(),
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
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  ),
              ],
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

// Wraps CalendarScreen in a Scaffold with its own AppBar
class _CalendarWrapper extends ConsumerWidget {
  const _CalendarWrapper();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeNotifierProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Calendar',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
        ),
        actions: [
          IconButton(
            icon: Icon(themeMode == ThemeMode.dark
                ? Icons.light_mode_outlined
                : Icons.dark_mode_outlined),
            tooltip: 'Toggle theme',
            onPressed: () =>
                ref.read(themeNotifierProvider.notifier).toggle(),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () =>
                ref.read(supabaseClientProvider).auth.signOut(),
          ),
        ],
      ),
      body: const CalendarScreen(),
    );
  }
}

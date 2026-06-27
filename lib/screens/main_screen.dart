import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_providers.dart';
import '../providers/supabase_provider.dart';
import '../sync/sync_service.dart';
import 'home_screen.dart';
import 'journal_screen.dart';
import 'notes_screen.dart';
import 'settings_screen.dart';
import 'tracker_screen.dart';

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  _SectionId _selectedSection = _SectionId.tasks;

  @override
  void initState() {
    super.initState();
    SyncService.instance.syncSoon();
  }

  static const _allMainDestinations = <_Destination>[
    _Destination(
      _SectionId.tasks,
      'Tasks',
      Icons.check_circle_outline,
      Icons.check_circle,
    ),
    _Destination(_SectionId.notes, 'Notes', Icons.notes_outlined, Icons.notes),
    _Destination(
      _SectionId.tracker,
      'Tracker',
      Icons.show_chart_outlined,
      Icons.show_chart,
    ),
    _Destination(
      _SectionId.dailyLog,
      'Daily Log',
      Icons.event_note_outlined,
      Icons.event_note,
    ),
  ];

  static const _settingsDestination = _Destination(
    _SectionId.settings,
    'Settings',
    Icons.settings_outlined,
    Icons.settings,
  );

  Widget _screenFor(_SectionId id) => switch (id) {
    _SectionId.tasks => const HomeScreen(),
    _SectionId.notes => const NotesScreen(),
    _SectionId.tracker => const TrackerScreen(),
    _SectionId.dailyLog => const JournalScreen(),
    _SectionId.settings => const SettingsScreen(),
  };

  @override
  Widget build(BuildContext context) {
    final showTracker = ref.watch(showTrackerSectionNotifierProvider);
    final showDailyLog = ref.watch(showDailyLogSectionNotifierProvider);
    final platform = Theme.of(context).platform;
    final useRail =
        platform == TargetPlatform.macOS ||
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux;

    final mainDestinations = [
      for (final destination in _allMainDestinations)
        if (destination.id != _SectionId.tracker || showTracker)
          if (destination.id != _SectionId.dailyLog || showDailyLog)
            destination,
    ];
    final destinations = [...mainDestinations, _settingsDestination];
    final visibleIds = destinations.map((d) => d.id).toSet();
    if (!visibleIds.contains(_selectedSection)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedSection = _SectionId.tasks);
      });
    }

    final selectedSection = visibleIds.contains(_selectedSection)
        ? _selectedSection
        : _SectionId.tasks;
    final selectedIndex = destinations.indexWhere(
      (d) => d.id == selectedSection,
    );
    final stack = IndexedStack(
      index: selectedIndex,
      children: [for (final d in destinations) _screenFor(d.id)],
    );

    if (useRail) {
      final railSelectedIndex = selectedSection == _SectionId.settings
          ? null
          : mainDestinations.indexWhere((d) => d.id == selectedSection);

      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: railSelectedIndex == null || railSelectedIndex < 0
                  ? null
                  : railSelectedIndex,
              onDestinationSelected: (i) =>
                  setState(() => _selectedSection = mainDestinations[i].id),
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.logout),
                        tooltip: 'Sign out',
                        onPressed: () =>
                            ref.read(supabaseClientProvider).auth.signOut(),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: IconButton(
                          icon: Icon(
                            selectedSection == _SectionId.settings
                                ? _settingsDestination.selectedIcon
                                : _settingsDestination.icon,
                            color: selectedSection == _SectionId.settings
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                          tooltip: _settingsDestination.label,
                          onPressed: () => setState(
                            () => _selectedSection = _SectionId.settings,
                          ),
                        ),
                      ),
                    ],
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
        selectedIndex: selectedIndex,
        onDestinationSelected: (i) =>
            setState(() => _selectedSection = destinations[i].id),
        destinations: [
          for (final d in destinations)
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

enum _SectionId { tasks, notes, tracker, dailyLog, settings }

class _Destination {
  final _SectionId id;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  const _Destination(this.id, this.label, this.icon, this.selectedIcon);
}

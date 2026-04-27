import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';
import '../models/calendar_entry.dart';
import '../models/recurrence.dart';
import '../providers/calendar_providers.dart';
import '../providers/settings_providers.dart';
import '../utils/date_utils.dart' as du;
import 'task_card.dart';

class CalendarView extends ConsumerStatefulWidget {
  final DateTime? initialSelectedDay;
  final ValueChanged<DateTime>? onDaySelected;

  const CalendarView({
    super.key,
    this.initialSelectedDay,
    this.onDaySelected,
  });

  @override
  ConsumerState<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends ConsumerState<CalendarView> {
  CalendarFormat _format = CalendarFormat.month;
  late DateTime _focusedDay;
  late DateTime _selectedDay;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialSelectedDay ?? DateTime.now();
    _focusedDay = initial;
    _selectedDay = initial;
  }

  List<CalendarEntry> _entriesForDay(
      Map<DateTime, List<CalendarEntry>> map, DateTime day) {
    final key = DateTime(day.year, day.month, day.day);
    return map[key] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    final occurrences = ref.watch(calendarOccurrencesProvider);
    final selectedEntries = _entriesForDay(occurrences, _selectedDay);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final dayCardColor = isDark
        ? colorScheme.surfaceContainerHigh
        : colorScheme.surfaceContainerHighest;
    final headerColor = colorScheme.onSurface.withValues(alpha: 0.6);

    return Column(
      children: [
        // Weekly / Monthly toggle + Today button
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<CalendarFormat>(
                  segments: const [
                    ButtonSegment(
                      value: CalendarFormat.week,
                      label: Text('Weekly'),
                      icon: Icon(Icons.view_week_outlined, size: 16),
                    ),
                    ButtonSegment(
                      value: CalendarFormat.month,
                      label: Text('Monthly'),
                      icon: Icon(Icons.calendar_month_outlined, size: 16),
                    ),
                  ],
                  selected: {_format},
                  onSelectionChanged: (s) =>
                      setState(() => _format = s.first),
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () {
                  final now = DateTime.now();
                  setState(() {
                    _focusedDay = now;
                    _selectedDay = now;
                  });
                  widget.onDaySelected?.call(now);
                },
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                child: const Text('Today'),
              ),
            ],
          ),
        ),

        // Calendar
        TableCalendar<CalendarEntry>(
          firstDay: DateTime.utc(2020, 1, 1),
          lastDay: DateTime.utc(2030, 12, 31),
          focusedDay: _focusedDay,
          calendarFormat: _format,
          availableCalendarFormats: const {
            CalendarFormat.month: 'Month',
            CalendarFormat.week: 'Week',
          },
          selectedDayPredicate: (day) => isSameDay(day, _selectedDay),
          eventLoader: (day) => _entriesForDay(occurrences, day),
          onDaySelected: (selected, focused) {
            setState(() {
              _selectedDay = selected;
              _focusedDay = focused;
            });
            widget.onDaySelected?.call(selected);
          },
          onFormatChanged: (format) => setState(() => _format = format),
          onPageChanged: (focused) => setState(() => _focusedDay = focused),
          calendarStyle: CalendarStyle(
            todayDecoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            todayTextStyle: TextStyle(color: colorScheme.onPrimaryContainer),
            selectedDecoration: BoxDecoration(
              color: colorScheme.primary,
              shape: BoxShape.circle,
            ),
            selectedTextStyle: TextStyle(color: colorScheme.onPrimary),
            markerDecoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.7),
              shape: BoxShape.circle,
            ),
            outsideDaysVisible: false,
          ),
          headerStyle: HeaderStyle(
            formatButtonVisible: false,
            titleCentered: true,
            titleTextStyle: theme.textTheme.titleMedium!
                .copyWith(fontWeight: FontWeight.bold),
          ),
        ),

        const Divider(height: 1),

        // Tasks for selected day — one date header, each task its own card
        Expanded(
          child: selectedEntries.isEmpty
              ? Center(
                  child: Text(
                    'No tasks',
                    style: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: 0.4)),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Single shared date label
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 4, 4, 6),
                              child: Text(
                                du.formatDateGroupHeader(_selectedDay),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: headerColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                          const Expanded(flex: 2, child: SizedBox.shrink()),
                        ],
                      ),
                      // One card per task
                      for (final entry in selectedEntries)
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(12, 3, 0, 3),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: dayCardColor,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: entry.isProjected
                                      ? _ProjectedTaskTile(entry: entry)
                                      : TaskCard(task: entry.task),
                                ),
                              ),
                            ),
                            const Expanded(flex: 2, child: SizedBox.shrink()),
                          ],
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

// Read-only tile for projected (future) occurrences of a recurring task.
// Mirrors TaskCard's row layout but uses a repeat icon instead of a checkbox
// and disables tap / swipe / context menu.
class _ProjectedTaskTile extends ConsumerStatefulWidget {
  final CalendarEntry entry;
  const _ProjectedTaskTile({required this.entry});

  @override
  ConsumerState<_ProjectedTaskTile> createState() =>
      _ProjectedTaskTileState();
}

class _ProjectedTaskTileState extends ConsumerState<_ProjectedTaskTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final task = widget.entry.task;
    final hasNotes = task.notes != null && task.notes!.isNotEmpty;
    final dim = colorScheme.onSurface.withValues(alpha: 0.5);
    final timeStyle = ref.watch(timeFormatNotifierProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Icon(Icons.repeat,
                    size: 18,
                    color: colorScheme.onSurface.withValues(alpha: 0.35)),
              ),
              const SizedBox(width: 8),
              if (task.dueTime != null) ...[
                SizedBox(
                  width: 64,
                  child: Text(
                    du.formatTimeAs(du.parseTime(task.dueTime!), timeStyle),
                    style: theme.textTheme.bodyMedium?.copyWith(color: dim),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  task.title,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: dim,
                  ),
                ),
              ),
              if (task.recurrence != RecurrenceType.none) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    task.recurrence.label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onPrimaryContainer
                          .withValues(alpha: 0.8),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              if (hasNotes)
                IconButton(
                  icon: Icon(
                    _expanded ? Icons.expand_less : Icons.notes,
                    size: 20,
                    color: _expanded
                        ? colorScheme.primary
                        : colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  iconSize: 20,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(),
                  tooltip: _expanded ? 'Hide note' : 'Show note',
                  onPressed: () => setState(() => _expanded = !_expanded),
                ),
            ],
          ),
          if (_expanded && hasNotes)
            Padding(
              padding: const EdgeInsets.fromLTRB(56, 0, 16, 8),
              child: Text(
                task.notes!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

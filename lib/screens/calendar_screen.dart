import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';
import '../models/calendar_entry.dart';
import '../models/recurrence.dart';
import '../providers/calendar_providers.dart';
import '../providers/task_providers.dart';
import '../utils/date_utils.dart' as du;
import '../widgets/add_edit_task_sheet.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  CalendarFormat _format = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  List<CalendarEntry> _entriesForDay(
      Map<DateTime, List<CalendarEntry>> map, DateTime day) {
    final key = DateTime(day.year, day.month, day.day);
    return map[key] ?? [];
  }

  void _openEdit(BuildContext context, CalendarEntry entry) {
    final isMacOS = Theme.of(context).platform == TargetPlatform.macOS;
    if (entry.isProjected) return; // projected entries are read-only

    if (isMacOS) return; // macOS uses right-click; tapping does nothing
    _showEditSheet(context, entry, editAllInSeries: false);
  }

  Future<void> _showContextMenu(
      BuildContext context, WidgetRef ref, TapUpDetails details, CalendarEntry entry) async {
    if (entry.isProjected) return;

    final task = entry.task;
    final isRecurring = task.recurrence != RecurrenceType.none;
    final hasSeries = task.seriesId != null;
    final pos = details.globalPosition;
    final rect = RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy);

    final items = <PopupMenuEntry<String>>[
      if (isRecurring) ...[
        const PopupMenuItem(value: 'edit_single', child: Text('Edit this task only')),
        if (hasSeries)
          const PopupMenuItem(value: 'edit_all', child: Text('Edit all remaining')),
      ] else
        const PopupMenuItem(value: 'edit_single', child: Text('Edit task')),
      const PopupMenuDivider(),
      if (isRecurring) ...[
        PopupMenuItem(
          value: 'delete_single',
          child: Text('Delete this task only',
              style: TextStyle(color: Colors.red.shade400)),
        ),
        if (hasSeries)
          PopupMenuItem(
            value: 'delete_all',
            child: Text('Delete all remaining',
                style: TextStyle(color: Colors.red.shade400)),
          ),
      ] else
        PopupMenuItem(
          value: 'delete_single',
          child: Text('Delete task',
              style: TextStyle(color: Colors.red.shade400)),
        ),
    ];

    final choice =
        await showMenu<String>(context: context, position: rect, items: items);
    if (!context.mounted) return;

    switch (choice) {
      case 'edit_single':
        _showEditSheet(context, entry, editAllInSeries: false);
      case 'edit_all':
        _showEditSheet(context, entry, editAllInSeries: true);
      case 'delete_single':
        await ref.read(taskListProvider.notifier).delete(task.id);
      case 'delete_all':
        await ref.read(taskListProvider.notifier).deleteSeries(task.seriesId!);
    }
  }

  void _showEditSheet(BuildContext context, CalendarEntry entry,
      {required bool editAllInSeries}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AddEditTaskSheet(
        task: entry.task,
        editAllInSeries: editAllInSeries,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final occurrences = ref.watch(calendarOccurrencesProvider);
    final selectedEntries = _entriesForDay(occurrences, _selectedDay);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isMacOS = theme.platform == TargetPlatform.macOS;

    return Column(
      children: [
        // Weekly / Monthly toggle
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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
          onDaySelected: (selected, focused) => setState(() {
            _selectedDay = selected;
            _focusedDay = focused;
          }),
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

        // Selected day header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              du.formatDate(_selectedDay),
              style: theme.textTheme.labelLarge?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.6),
                letterSpacing: 0.8,
              ),
            ),
          ),
        ),

        // Tasks for selected day
        Expanded(
          child: selectedEntries.isEmpty
              ? Center(
                  child: Text(
                    'No tasks',
                    style: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: 0.4)),
                  ),
                )
              : ListView.builder(
                  itemCount: selectedEntries.length,
                  itemBuilder: (context, index) {
                    final entry = selectedEntries[index];
                    return _CalendarTaskTile(
                      entry: entry,
                      isMacOS: isMacOS,
                      onTap: () => _openEdit(context, entry),
                      onSecondaryTapUp: (details) =>
                          _showContextMenu(context, ref, details, entry),
                      onCheckbox: entry.isProjected
                          ? null
                          : () => ref
                              .read(taskListProvider.notifier)
                              .markDone(entry.task),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _CalendarTaskTile extends StatelessWidget {
  final CalendarEntry entry;
  final bool isMacOS;
  final VoidCallback onTap;
  final void Function(TapUpDetails) onSecondaryTapUp;
  final VoidCallback? onCheckbox;

  const _CalendarTaskTile({
    required this.entry,
    required this.isMacOS,
    required this.onTap,
    required this.onSecondaryTapUp,
    this.onCheckbox,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final task = entry.task;
    final isProjected = entry.isProjected;

    return GestureDetector(
      onTap: isMacOS ? null : onTap,
      onSecondaryTapUp: isMacOS ? onSecondaryTapUp : null,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              if (!isProjected)
                Checkbox(
                  value: task.isDone,
                  shape: const CircleBorder(),
                  onChanged: onCheckbox == null ? null : (_) => onCheckbox!(),
                )
              else
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Icon(Icons.repeat,
                      size: 18,
                      color: colorScheme.onSurface.withValues(alpha: 0.35)),
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight:
                            isProjected ? FontWeight.normal : FontWeight.w600,
                        color: isProjected
                            ? colorScheme.onSurface.withValues(alpha: 0.5)
                            : null,
                      ),
                    ),
                    if (task.recurrence != RecurrenceType.none)
                      Text(
                        isProjected
                            ? '${task.recurrence.label} · projected'
                            : task.recurrence.label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withValues(alpha: 0.4),
                        ),
                      ),
                  ],
                ),
              ),
              if (!isProjected)
                Icon(Icons.chevron_right,
                    size: 18,
                    color: colorScheme.onSurface.withValues(alpha: 0.3)),
            ],
          ),
        ),
      ),
    );
  }
}

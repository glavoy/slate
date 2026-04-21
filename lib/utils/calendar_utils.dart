import '../models/calendar_entry.dart';
import '../models/recurrence.dart';
import '../models/task.dart';
import 'date_utils.dart';

Map<DateTime, List<CalendarEntry>> buildOccurrenceMap(
  List<Task> tasks,
  DateTime rangeStart,
  DateTime rangeEnd,
) {
  final map = <DateTime, List<CalendarEntry>>{};

  void add(DateTime date, CalendarEntry entry) {
    final key = DateTime(date.year, date.month, date.day);
    if (!key.isBefore(rangeStart) && !key.isAfter(rangeEnd)) {
      map.putIfAbsent(key, () => []).add(entry);
    }
  }

  for (final task in tasks) {
    final taskDate =
        DateTime(task.dueDate.year, task.dueDate.month, task.dueDate.day);

    // Always add the actual stored occurrence
    add(taskDate, CalendarEntry(task: task, date: taskDate, isProjected: false));

    // Project future occurrences within range
    if (task.recurrence != RecurrenceType.none) {
      var projected = nextOccurrence(taskDate, task.recurrence);
      while (!projected.isAfter(rangeEnd)) {
        add(projected,
            CalendarEntry(task: task, date: projected, isProjected: true));
        projected = nextOccurrence(projected, task.recurrence);
      }
    }
  }

  return map;
}

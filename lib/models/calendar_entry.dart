import 'task.dart';

class CalendarEntry {
  final Task task;
  final DateTime date;
  final bool isProjected;

  const CalendarEntry({
    required this.task,
    required this.date,
    this.isProjected = false,
  });
}

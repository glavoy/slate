import 'package:flutter/material.dart';
import '../models/recurrence.dart';

bool isOverdue(DateTime dueDate, [String? dueTime]) {
  final now = DateTime.now();
  if (dueTime != null) {
    final t = parseTime(dueTime);
    final due = DateTime(dueDate.year, dueDate.month, dueDate.day, t.hour, t.minute);
    return due.isBefore(now);
  }
  final todayMidnight = DateTime(now.year, now.month, now.day);
  final dueMidnight = DateTime(dueDate.year, dueDate.month, dueDate.day);
  return dueMidnight.isBefore(todayMidnight);
}

DateTime nextOccurrence(DateTime from, RecurrenceType recurrence) =>
    switch (recurrence) {
      RecurrenceType.daily => DateTime(from.year, from.month, from.day + 1),
      RecurrenceType.weekly => DateTime(from.year, from.month, from.day + 7),
      RecurrenceType.monthly => DateTime(from.year, from.month + 1, from.day),
      RecurrenceType.yearly => DateTime(from.year + 1, from.month, from.day),
      RecurrenceType.none => from,
    };

const _monthAbbr = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const _dayAbbr = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _dayFull = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday',
  'Friday', 'Saturday', 'Sunday',
];

String formatDate(DateTime date) {
  final dayName = _dayAbbr[date.weekday - 1];
  final month = _monthAbbr[date.month - 1];
  final yearSuffix =
      date.year == DateTime.now().year ? '' : ', ${date.year}';
  return '$dayName $month ${date.day}$yearSuffix';
}

String formatDateGroupHeader(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(date.year, date.month, date.day);
  final diff = target.difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';

  final dayName = _dayFull[date.weekday - 1];
  final month = _monthAbbr[date.month - 1];
  return '$dayName, ${date.day} $month ${date.year}';
}

// Parses "HH:MM:SS" or "HH:MM" from PostgreSQL time column
TimeOfDay parseTime(String raw) {
  final parts = raw.split(':');
  return TimeOfDay(
    hour: int.parse(parts[0]),
    minute: int.parse(parts[1]),
  );
}

// Formats TimeOfDay to "HH:MM:00" for PostgreSQL
String timeOfDayToString(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

// Formats TimeOfDay for display: "8:00 AM"
String formatTime(TimeOfDay t) {
  final hour = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
  final minute = t.minute.toString().padLeft(2, '0');
  final period = t.period == DayPeriod.am ? 'AM' : 'PM';
  return '$hour:$minute $period';
}

const defaultDueTime = TimeOfDay(hour: 8, minute: 0);

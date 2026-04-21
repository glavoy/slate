import 'package:flutter/material.dart';
import '../models/recurrence.dart';

bool isOverdue(DateTime dueDate) {
  final now = DateTime.now();
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

String formatDate(DateTime date) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final dayName = days[date.weekday - 1];
  final month = months[date.month - 1];
  return '$dayName $month ${date.day}';
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

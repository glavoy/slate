import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../models/calendar_entry.dart';
import '../utils/calendar_utils.dart';
import 'task_providers.dart';

part 'calendar_providers.g.dart';

@riverpod
// ignore: deprecated_member_use_from_same_package
Map<DateTime, List<CalendarEntry>> calendarOccurrences(CalendarOccurrencesRef ref) {
  final tasks = ref.watch(taskListProvider).valueOrNull ?? [];
  final now = DateTime.now();
  final rangeStart = DateTime(now.year, now.month - 2, 1);
  final rangeEnd = DateTime(now.year, now.month + 13, 0); // last day of month+13
  return buildOccurrenceMap(tasks, rangeStart, rangeEnd);
}

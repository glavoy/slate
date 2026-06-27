import '../models/tracker_entry.dart';

class TrackerOverviewStats {
  final DateTime? lastLoggedAt;
  final double lastSevenDaysTotal;
  final double currentMonthTotal;
  final double thirtyDayAverage;

  const TrackerOverviewStats({
    required this.lastLoggedAt,
    required this.lastSevenDaysTotal,
    required this.currentMonthTotal,
    required this.thirtyDayAverage,
  });
}

TrackerOverviewStats buildTrackerOverviewStats({
  required List<TrackerEntry> entries,
  required DateTime now,
}) {
  // Use UTC date components throughout so that "the date" of each entry
  // matches what _formatRecorded displays in the entry list.
  final today = _dateOnly(now.toUtc());
  final sevenDayStart = today.subtract(const Duration(days: 6));
  final thirtyDayStart = today.subtract(const Duration(days: 29));
  final monthStart = DateTime(today.year, today.month);

  DateTime? lastLoggedAt;
  var lastSevenDaysTotal = 0.0;
  var currentMonthTotal = 0.0;
  var thirtyDayTotal = 0.0;

  for (final entry in entries) {
    // entry.recordedAt is UTC; strip the time component to get the UTC date.
    final recordedDate = _dateOnly(entry.recordedAt);

    if (lastLoggedAt == null || entry.recordedAt.isAfter(lastLoggedAt)) {
      lastLoggedAt = entry.recordedAt;
    }

    if (!recordedDate.isBefore(sevenDayStart) && !recordedDate.isAfter(today)) {
      lastSevenDaysTotal += entry.value;
    }
    if (!recordedDate.isBefore(monthStart) && !recordedDate.isAfter(today)) {
      currentMonthTotal += entry.value;
    }
    if (!recordedDate.isBefore(thirtyDayStart) &&
        !recordedDate.isAfter(today)) {
      thirtyDayTotal += entry.value;
    }
  }

  return TrackerOverviewStats(
    lastLoggedAt: lastLoggedAt,
    lastSevenDaysTotal: lastSevenDaysTotal,
    currentMonthTotal: currentMonthTotal,
    thirtyDayAverage: thirtyDayTotal / 30,
  );
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

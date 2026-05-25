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
  final today = _dateOnly(now.toLocal());
  final sevenDayStart = today.subtract(const Duration(days: 6));
  final thirtyDayStart = today.subtract(const Duration(days: 29));
  final monthStart = DateTime(today.year, today.month);

  DateTime? lastLoggedAt;
  var lastSevenDaysTotal = 0.0;
  var currentMonthTotal = 0.0;
  var thirtyDayTotal = 0.0;

  for (final entry in entries) {
    final recordedAt = entry.recordedAt.toLocal();
    final recordedDate = _dateOnly(recordedAt);

    if (lastLoggedAt == null || recordedAt.isAfter(lastLoggedAt)) {
      lastLoggedAt = recordedAt;
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

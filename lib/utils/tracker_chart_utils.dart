import '../models/tracker_entry.dart';

enum TrackerChartPeriod { daily, weekly, monthly, yearly }

class TrackerChartPoint {
  final DateTime start;
  final DateTime end;
  final double value;

  const TrackerChartPoint({
    required this.start,
    required this.end,
    required this.value,
  });
}

List<TrackerChartPoint> buildTrackerChartPoints({
  required List<TrackerEntry> entries,
  required DateTime startDate,
  required DateTime endDate,
  required TrackerChartPeriod period,
}) {
  final normalizedStart = _dateOnly(startDate);
  final normalizedEnd = _dateOnly(endDate);
  final rangeStart = normalizedStart.isAfter(normalizedEnd)
      ? normalizedEnd
      : normalizedStart;
  final rangeEnd = normalizedStart.isAfter(normalizedEnd)
      ? normalizedStart
      : normalizedEnd;

  final bucketStarts = <DateTime>[];
  var cursor = _bucketStart(rangeStart, period);
  while (!cursor.isAfter(rangeEnd)) {
    bucketStarts.add(cursor);
    cursor = _nextBucketStart(cursor, period);
  }

  final totals = <DateTime, double>{for (final start in bucketStarts) start: 0};

  for (final entry in entries) {
    final recorded = _dateOnly(entry.recordedAt.toLocal());
    if (recorded.isBefore(rangeStart) || recorded.isAfter(rangeEnd)) {
      continue;
    }

    final bucket = _bucketStart(recorded, period);
    totals[bucket] = (totals[bucket] ?? 0) + entry.value;
  }

  return bucketStarts.map((start) {
    final naturalEnd = _nextBucketStart(
      start,
      period,
    ).subtract(const Duration(days: 1));
    return TrackerChartPoint(
      start: start.isBefore(rangeStart) ? rangeStart : start,
      end: naturalEnd.isAfter(rangeEnd) ? rangeEnd : naturalEnd,
      value: totals[start] ?? 0,
    );
  }).toList();
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

DateTime _bucketStart(DateTime date, TrackerChartPeriod period) {
  switch (period) {
    case TrackerChartPeriod.daily:
      return _dateOnly(date);
    case TrackerChartPeriod.weekly:
      return DateTime(date.year, date.month, date.day - date.weekday + 1);
    case TrackerChartPeriod.monthly:
      return DateTime(date.year, date.month);
    case TrackerChartPeriod.yearly:
      return DateTime(date.year);
  }
}

DateTime _nextBucketStart(DateTime start, TrackerChartPeriod period) {
  switch (period) {
    case TrackerChartPeriod.daily:
      return DateTime(start.year, start.month, start.day + 1);
    case TrackerChartPeriod.weekly:
      return DateTime(start.year, start.month, start.day + 7);
    case TrackerChartPeriod.monthly:
      return DateTime(start.year, start.month + 1);
    case TrackerChartPeriod.yearly:
      return DateTime(start.year + 1);
  }
}

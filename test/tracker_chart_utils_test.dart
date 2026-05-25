import 'package:flutter_test/flutter_test.dart';
import 'package:slate/models/tracker_entry.dart';
import 'package:slate/utils/tracker_chart_utils.dart';

void main() {
  TrackerEntry entry(String id, DateTime recordedAt, double value) {
    return TrackerEntry(
      id: id,
      metricId: 'metric-1',
      userId: 'user-1',
      value: value,
      recordedAt: recordedAt,
    );
  }

  test('daily points total multiple entries on the same day', () {
    final points = buildTrackerChartPoints(
      entries: [
        entry('1', DateTime(2026, 5, 1, 9), 2),
        entry('2', DateTime(2026, 5, 1, 18), 3),
        entry('3', DateTime(2026, 5, 3), 7),
      ],
      startDate: DateTime(2026, 5, 1),
      endDate: DateTime(2026, 5, 3),
      period: TrackerChartPeriod.daily,
    );

    expect(points.map((point) => point.value), [5, 0, 7]);
  });

  test('weekly points use Monday as the bucket start', () {
    final points = buildTrackerChartPoints(
      entries: [
        entry('1', DateTime(2026, 5, 4), 2),
        entry('2', DateTime(2026, 5, 10), 3),
        entry('3', DateTime(2026, 5, 11), 7),
      ],
      startDate: DateTime(2026, 5, 4),
      endDate: DateTime(2026, 5, 17),
      period: TrackerChartPeriod.weekly,
    );

    expect(points, hasLength(2));
    expect(points[0].start, DateTime(2026, 5, 4));
    expect(points[0].end, DateTime(2026, 5, 10));
    expect(points[0].value, 5);
    expect(points[1].start, DateTime(2026, 5, 11));
    expect(points[1].end, DateTime(2026, 5, 17));
    expect(points[1].value, 7);
  });

  test('monthly and yearly points total entries across boundaries', () {
    final entries = [
      entry('1', DateTime(2025, 12, 31), 1),
      entry('2', DateTime(2026, 1, 1), 2),
      entry('3', DateTime(2026, 1, 31), 3),
      entry('4', DateTime(2026, 2, 1), 4),
    ];

    final monthly = buildTrackerChartPoints(
      entries: entries,
      startDate: DateTime(2025, 12, 1),
      endDate: DateTime(2026, 2, 28),
      period: TrackerChartPeriod.monthly,
    );
    final yearly = buildTrackerChartPoints(
      entries: entries,
      startDate: DateTime(2025, 1, 1),
      endDate: DateTime(2026, 12, 31),
      period: TrackerChartPeriod.yearly,
    );

    expect(monthly.map((point) => point.value), [1, 5, 4]);
    expect(yearly.map((point) => point.value), [1, 9]);
  });

  test('filters inclusively and returns zero-value empty buckets', () {
    final points = buildTrackerChartPoints(
      entries: [
        entry('1', DateTime(2026, 4, 30, 23), 10),
        entry('2', DateTime(2026, 5, 1), 2),
        entry('3', DateTime(2026, 5, 3, 23, 59), 4),
        entry('4', DateTime(2026, 5, 4), 10),
      ],
      startDate: DateTime(2026, 5, 1),
      endDate: DateTime(2026, 5, 3),
      period: TrackerChartPeriod.daily,
    );

    expect(points, hasLength(3));
    expect(points.map((point) => point.value), [2, 0, 4]);
  });

  test(
    'uses the stored date rather than shifting UTC entries to local dates',
    () {
      final points = buildTrackerChartPoints(
        entries: [
          entry('1', DateTime.utc(2026, 5, 1, 21), 5),
          entry('2', DateTime.utc(2026, 5, 2, 21), 3),
        ],
        startDate: DateTime(2026, 5, 1),
        endDate: DateTime(2026, 5, 2),
        period: TrackerChartPeriod.daily,
      );

      expect(points.map((point) => point.value), [5, 3]);
    },
  );
}

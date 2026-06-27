import 'package:flutter_test/flutter_test.dart';
import 'package:slate/models/tracker_entry.dart';
import 'package:slate/utils/tracker_overview_stats.dart';

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

  test('last seven days includes today and previous six days only', () {
    final stats = buildTrackerOverviewStats(
      now: DateTime(2026, 5, 25, 12),
      entries: [
        entry('1', DateTime(2026, 5, 19), 2),
        entry('2', DateTime(2026, 5, 25, 23), 3),
        entry('3', DateTime(2026, 5, 18, 23, 59), 100),
        entry('4', DateTime(2026, 5, 26), 100),
      ],
    );

    expect(stats.lastSevenDaysTotal, 5);
  });

  test('current month includes entries from the first through today', () {
    final stats = buildTrackerOverviewStats(
      now: DateTime(2026, 5, 25, 12),
      entries: [
        entry('1', DateTime(2026, 5, 1), 2),
        entry('2', DateTime(2026, 5, 25), 3),
        entry('3', DateTime(2026, 4, 30), 100),
        entry('4', DateTime(2026, 5, 26), 100),
      ],
    );

    expect(stats.currentMonthTotal, 5);
  });

  test('thirty day average divides the rolling thirty day total by thirty', () {
    final stats = buildTrackerOverviewStats(
      now: DateTime(2026, 5, 25, 12),
      entries: [
        entry('1', DateTime(2026, 4, 26), 30),
        entry('2', DateTime(2026, 5, 25), 60),
        entry('3', DateTime(2026, 4, 25), 300),
      ],
    );

    expect(stats.thirtyDayAverage, 3);
  });

  test('last logged uses the most recent entry timestamp', () {
    final stats = buildTrackerOverviewStats(
      now: DateTime(2026, 5, 25, 12),
      entries: [
        entry('1', DateTime(2026, 5, 23), 1),
        entry('2', DateTime(2026, 5, 25, 8), 1),
        entry('3', DateTime(2026, 5, 25, 18), 1),
      ],
    );

    expect(stats.lastLoggedAt, DateTime(2026, 5, 25, 18));
  });

  test('empty entries return no last logged date and zero stats', () {
    final stats = buildTrackerOverviewStats(
      now: DateTime(2026, 5, 25, 12),
      entries: const [],
    );

    expect(stats.lastLoggedAt, isNull);
    expect(stats.lastSevenDaysTotal, 0);
    expect(stats.currentMonthTotal, 0);
    expect(stats.thirtyDayAverage, 0);
  });
}

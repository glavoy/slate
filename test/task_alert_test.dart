import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slate/local/local_database.dart';
import 'package:slate/repositories/task_alert_repository.dart';
import 'package:slate/services/task_alert_rules.dart';
import 'package:slate/utils/date_utils.dart';

void main() {
  final now = DateTime(2026, 9, 11, 14, 0);
  const dayStart = TimeOfDay(hour: 8, minute: 0);

  TaskAlertRow row({
    required DateTime dueAt,
    DateTime? snoozedUntil,
    DateTime? dismissedAt,
  }) => TaskAlertRow(
    taskId: 't1',
    dueAt: dueAt,
    snoozedUntil: snoozedUntil,
    dismissedAt: dismissedAt,
  );

  group('shouldAlert', () {
    test('a task due in the future does not alert', () {
      expect(
        shouldAlert(
          dueAt: now.add(const Duration(minutes: 5)),
          row: null,
          now: now,
        ),
        isFalse,
      );
    });

    test('a task due a minute ago alerts', () {
      expect(
        shouldAlert(
          dueAt: now.subtract(const Duration(minutes: 1)),
          row: null,
          now: now,
        ),
        isTrue,
      );
    });

    test('a task due exactly now alerts', () {
      expect(shouldAlert(dueAt: now, row: null, now: now), isTrue);
    });

    test('a task due 30 hours ago is outside the backfill window', () {
      expect(
        shouldAlert(
          dueAt: now.subtract(const Duration(hours: 30)),
          row: null,
          now: now,
        ),
        isFalse,
      );
    });

    test('a dismissal suppresses the alert', () {
      final dueAt = now.subtract(const Duration(minutes: 10));
      expect(
        shouldAlert(
          dueAt: dueAt,
          row: row(dueAt: dueAt, dismissedAt: now.toUtc()),
          now: now,
        ),
        isFalse,
      );
    });

    test('editing the due time past a dismissal re-arms the alert', () {
      final dismissedFor = now.subtract(const Duration(minutes: 10));
      final editedTo = now.subtract(const Duration(minutes: 2));
      expect(
        shouldAlert(
          dueAt: editedTo,
          row: row(dueAt: dismissedFor, dismissedAt: now.toUtc()),
          now: now,
        ),
        isTrue,
      );
    });

    test('a snooze suppresses until its target, then alerts again', () {
      final dueAt = now.subtract(const Duration(minutes: 10));
      final until = now.add(const Duration(minutes: 10)).toUtc();
      final alertRow = row(dueAt: dueAt, snoozedUntil: until);

      expect(shouldAlert(dueAt: dueAt, row: alertRow, now: now), isFalse);
      expect(
        shouldAlert(
          dueAt: dueAt,
          row: alertRow,
          now: now.add(const Duration(minutes: 11)),
        ),
        isTrue,
      );
    });
  });

  group('resolveDueAt', () {
    test('uses the task due time when present', () {
      expect(
        resolveDueAt(DateTime(2026, 9, 11), '14:30:00', dayStart),
        DateTime(2026, 9, 11, 14, 30),
      );
    });

    test('falls back to the day start for all-day tasks', () {
      expect(
        resolveDueAt(DateTime(2026, 9, 11), null, dayStart),
        DateTime(2026, 9, 11, 8, 0),
      );
    });
  });

  group('snoozeTargets', () {
    test('offers This evening before 6pm and drops it after', () {
      final labelsAfternoon = snoozeTargets(
        DateTime(2026, 9, 11, 14),
        dayStart,
      ).map((t) => t.label);
      expect(labelsAfternoon, contains('This evening'));

      final labelsNight = snoozeTargets(
        DateTime(2026, 9, 11, 19),
        dayStart,
      ).map((t) => t.label);
      expect(labelsNight, isNot(contains('This evening')));
    });

    test('Tomorrow morning snaps to the day start, not +24h', () {
      final tomorrow = snoozeTargets(
        DateTime(2026, 9, 11, 14, 37),
        dayStart,
      ).firstWhere((t) => t.label == 'Tomorrow morning');
      expect(tomorrow.at, DateTime(2026, 9, 12, 8, 0));
    });
  });

  group('TaskAlertRepository', () {
    late LocalDatabase local;
    late TaskAlertRepository repo;

    setUp(() {
      local = LocalDatabase.inMemory();
      repo = TaskAlertRepository(local);
    });

    test('round-trips a dismissal', () {
      final dueAt = DateTime(2026, 9, 11, 9, 0);
      repo.dismiss('t1', dueAt);

      final stored = repo.loadAll()['t1']!;
      expect(stored.dueAt, dueAt);
      expect(stored.dismissedAt, isNotNull);
      expect(stored.snoozedUntil, isNull);
    });

    test('a snooze clears a previous dismissal for the same task', () {
      final dueAt = DateTime(2026, 9, 11, 9, 0);
      repo.dismiss('t1', dueAt);
      repo.snooze('t1', dueAt, DateTime(2026, 9, 11, 10, 0));

      final stored = repo.loadAll()['t1']!;
      expect(stored.dismissedAt, isNull);
      expect(stored.snoozedUntil, isNotNull);
    });

    test('pruneStale drops rows for tasks no longer active', () {
      final dueAt = DateTime(2026, 9, 11, 9, 0);
      repo.dismiss('t1', dueAt);
      repo.dismiss('t2', dueAt);

      repo.pruneStale({'t1'});
      expect(repo.loadAll().keys, ['t1']);

      repo.pruneStale({});
      expect(repo.loadAll(), isEmpty);
    });
  });
}

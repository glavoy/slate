import 'package:flutter/material.dart';

/// Locally stored alert state for a single task occurrence.
///
/// [dueAt] is the occurrence key: a row only suppresses an alert while it still
/// refers to the task's current due instant. Editing a dismissed task's date or
/// time changes the resolved due instant, so the stored row stops matching and
/// the alert re-arms.
class TaskAlertRow {
  const TaskAlertRow({
    required this.taskId,
    required this.dueAt,
    this.snoozedUntil,
    this.dismissedAt,
  });

  /// The task this row belongs to.
  final String taskId;

  /// Local wall-clock due instant this row was recorded against.
  final DateTime dueAt;

  /// UTC instant the snooze expires, or null when not snoozed.
  final DateTime? snoozedUntil;

  /// UTC instant the alert was dismissed, or null when not dismissed.
  final DateTime? dismissedAt;
}

/// How far back an already-passed due instant still raises a banner.
///
/// Without a cap, a week away from the app would greet you with a wall of
/// alerts. Older tasks are still flagged as overdue in the Tasks list.
const alertBackfillWindow = Duration(hours: 24);

/// Hour of the "This evening" snooze target.
const _eveningHour = 18;

/// Whether a task whose due instant resolves to [dueAt] should be alerting at
/// [now], given its stored alert state [row] (null when never acted on).
bool shouldAlert({
  required DateTime dueAt,
  required TaskAlertRow? row,
  required DateTime now,
}) {
  if (dueAt.isAfter(now)) return false;
  if (now.difference(dueAt) > alertBackfillWindow) return false;

  // No stored state, or state recorded against a different occurrence.
  if (row == null || !row.dueAt.isAtSameMomentAs(dueAt)) return true;

  if (row.dismissedAt != null) return false;

  final snoozedUntil = row.snoozedUntil;
  if (snoozedUntil != null && now.toUtc().isBefore(snoozedUntil)) return false;

  return true;
}

/// A single entry in the snooze menu.
class SnoozeTarget {
  const SnoozeTarget(this.label, this.at);

  final String label;

  /// Local instant the alert should return.
  final DateTime at;
}

/// Snooze options offered for an alert raised at [now].
///
/// "Tomorrow morning" snaps to [dayStart] rather than adding a literal 24
/// hours, which would land at an arbitrary time of day. "This evening" is
/// dropped once it is already past.
List<SnoozeTarget> snoozeTargets(DateTime now, TimeOfDay dayStart) {
  final evening = DateTime(now.year, now.month, now.day, _eveningHour);
  final tomorrow = DateTime(
    now.year,
    now.month,
    now.day + 1,
    dayStart.hour,
    dayStart.minute,
  );

  return [
    SnoozeTarget('10 minutes', now.add(const Duration(minutes: 10))),
    SnoozeTarget('1 hour', now.add(const Duration(hours: 1))),
    SnoozeTarget('3 hours', now.add(const Duration(hours: 3))),
    if (evening.isAfter(now)) SnoozeTarget('This evening', evening),
    SnoozeTarget('Tomorrow morning', tomorrow),
  ];
}

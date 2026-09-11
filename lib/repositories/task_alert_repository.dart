import '../local/local_database.dart';
import '../services/task_alert_rules.dart';

/// Local-only store for in-app due alert state.
///
/// Nothing here is synced, so unlike TaskRepository these writes never set
/// sync_status or call SyncService.schedulePush().
class TaskAlertRepository {
  TaskAlertRepository([LocalDatabase? local])
    : _local = local ?? LocalDatabase.instance;

  final LocalDatabase _local;

  Map<String, TaskAlertRow> loadAll() {
    final rows = _local.select('SELECT * FROM task_alerts');
    return {
      for (final row in rows)
        row['task_id'] as String: TaskAlertRow(
          taskId: row['task_id'] as String,
          dueAt: DateTime.parse(row['due_at'] as String),
          snoozedUntil: _parseNullable(row['snoozed_until']),
          dismissedAt: _parseNullable(row['dismissed_at']),
        ),
    };
  }

  void snooze(String taskId, DateTime dueAt, DateTime until) {
    _upsert(
      taskId: taskId,
      dueAt: dueAt,
      snoozedUntil: until.toUtc().toIso8601String(),
      dismissedAt: null,
    );
  }

  void dismiss(String taskId, DateTime dueAt) {
    _upsert(
      taskId: taskId,
      dueAt: dueAt,
      snoozedUntil: null,
      dismissedAt: nowIso(),
    );
  }

  void _upsert({
    required String taskId,
    required DateTime dueAt,
    required String? snoozedUntil,
    required String? dismissedAt,
  }) {
    _local.execute(
      '''
      INSERT INTO task_alerts (task_id, due_at, snoozed_until, dismissed_at)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(task_id) DO UPDATE SET
        due_at = excluded.due_at,
        snoozed_until = excluded.snoozed_until,
        dismissed_at = excluded.dismissed_at
      ''',
      [taskId, dueAt.toIso8601String(), snoozedUntil, dismissedAt],
    );
  }

  /// Drops rows for tasks that are no longer active, keeping the table bounded
  /// as tasks are completed or deleted.
  void pruneStale(Set<String> activeTaskIds) {
    if (activeTaskIds.isEmpty) {
      _local.execute('DELETE FROM task_alerts');
      return;
    }
    final placeholders = List.filled(activeTaskIds.length, '?').join(', ');
    _local.execute(
      'DELETE FROM task_alerts WHERE task_id NOT IN ($placeholders)',
      activeTaskIds.toList(),
    );
  }

  static DateTime? _parseNullable(Object? value) =>
      value == null ? null : DateTime.parse(value as String);
}

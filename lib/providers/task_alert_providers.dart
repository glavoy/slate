import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/task.dart';
import '../repositories/task_alert_repository.dart';
import '../services/task_alert_rules.dart';
import '../utils/date_utils.dart';
import 'settings_providers.dart';
import 'task_providers.dart';

part 'task_alert_providers.g.dart';

/// Tasks that should currently be raising an in-app alert, most overdue first.
///
/// This derives from [taskListProvider], which already self-invalidates every
/// minute and on every sync change, so no timer of its own is needed. Worst
/// case latency on a due instant or an expiring snooze is about 60 seconds.
@riverpod
class DueAlerts extends _$DueAlerts {
  @override
  List<Task> build() {
    if (!ref.watch(taskAlertsEnabledNotifierProvider)) return const [];

    final tasks = ref.watch(taskListProvider).value ?? const <Task>[];
    if (tasks.isEmpty) return const [];

    final dayStart = ref.watch(taskAlertDayStartNotifierProvider);
    final repo = TaskAlertRepository();
    repo.pruneStale(tasks.map((t) => t.id).toSet());

    final rows = repo.loadAll();
    final now = DateTime.now();

    final due = <({Task task, DateTime dueAt})>[];
    for (final task in tasks) {
      final dueAt = resolveDueAt(task.dueDate, task.dueTime, dayStart);
      if (shouldAlert(dueAt: dueAt, row: rows[task.id], now: now)) {
        due.add((task: task, dueAt: dueAt));
      }
    }
    due.sort((a, b) => a.dueAt.compareTo(b.dueAt));
    return [for (final entry in due) entry.task];
  }

  void dismiss(Task task) {
    TaskAlertRepository().dismiss(task.id, _dueAtFor(task));
    ref.invalidateSelf();
  }

  void snoozeUntil(Task task, DateTime until) {
    TaskAlertRepository().snooze(task.id, _dueAtFor(task), until);
    ref.invalidateSelf();
  }

  void dismissAll() {
    final repo = TaskAlertRepository();
    for (final task in state) {
      repo.dismiss(task.id, _dueAtFor(task));
    }
    ref.invalidateSelf();
  }

  DateTime _dueAtFor(Task task) => resolveDueAt(
    task.dueDate,
    task.dueTime,
    ref.read(taskAlertDayStartNotifierProvider),
  );
}

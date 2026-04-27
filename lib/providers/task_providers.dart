import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../models/task.dart';
import '../models/recurrence.dart';
import '../repositories/task_repository.dart';
import '../sync/sync_service.dart';
import '../utils/date_utils.dart';
import 'supabase_provider.dart';

part 'task_providers.g.dart';

final showAllCompletedProvider = StateProvider<bool>((ref) => false);

@riverpod
class TaskList extends _$TaskList {
  TaskRepository _repo() => TaskRepository(ref.read(supabaseClientProvider));

  @override
  Future<List<Task>> build() async {
    final client = ref.watch(supabaseClientProvider);

    final syncSubscription = SyncService.instance.changes.listen((_) {
      ref.invalidateSelf();
      ref.invalidate(completedTaskListProvider);
    });
    ref.onDispose(syncSubscription.cancel);

    // Re-evaluate overdue status every minute while the app is running
    final timer = Timer.periodic(const Duration(minutes: 1), (_) {
      ref.invalidateSelf();
    });
    ref.onDispose(timer.cancel);

    return TaskRepository(client).fetchActiveTasks();
  }

  Future<void> markDone(Task task) async {
    await _repo().markDone(task);
    ref.invalidateSelf();
    ref.invalidate(completedTaskListProvider);
  }

  Future<void> delete(String taskId) async {
    await _repo().deleteTask(taskId);
    ref.invalidateSelf();
  }

  Future<void> deleteSeries(String seriesId) async {
    await _repo().deleteAllInSeries(seriesId);
    ref.invalidateSelf();
  }

  Future<void> add({
    required String title,
    required DateTime dueDate,
    required TimeOfDay dueTime,
    String? notes,
    RecurrenceType recurrence = RecurrenceType.none,
  }) async {
    await _repo().createTask(
      title: title,
      dueDate: dueDate,
      dueTime: dueTime,
      notes: notes,
      recurrence: recurrence,
    );
    ref.invalidateSelf();
  }

  Future<void> editTask({
    required String taskId,
    required String title,
    required DateTime dueDate,
    required TimeOfDay dueTime,
    String? notes,
    required RecurrenceType recurrence,
  }) async {
    await _repo().updateTask(
      taskId: taskId,
      title: title,
      dueDate: dueDate,
      dueTime: dueTime,
      notes: notes,
      recurrence: recurrence,
    );
    ref.invalidateSelf();
  }

  Future<void> editAllInSeries({
    required String seriesId,
    required String title,
    required TimeOfDay dueTime,
    String? notes,
    required RecurrenceType recurrence,
  }) async {
    await _repo().updateAllInSeries(
      seriesId: seriesId,
      title: title,
      dueTime: dueTime,
      notes: notes,
      recurrence: recurrence,
    );
    ref.invalidateSelf();
  }
}

@riverpod
class CompletedTaskList extends _$CompletedTaskList {
  @override
  Future<List<Task>> build() async {
    final syncSubscription = SyncService.instance.changes.listen((_) {
      ref.invalidateSelf();
    });
    ref.onDispose(syncSubscription.cancel);

    final showAll = ref.watch(showAllCompletedProvider);
    return TaskRepository(
      ref.watch(supabaseClientProvider),
    ).fetchCompleted(showAll: showAll);
  }

  Future<void> undoComplete(Task task) async {
    await TaskRepository(ref.read(supabaseClientProvider)).undoComplete(task);
    ref.invalidateSelf();
    ref.invalidate(taskListProvider);
  }

  Future<void> delete(String taskId) async {
    await TaskRepository(ref.read(supabaseClientProvider)).deleteTask(taskId);
    ref.invalidateSelf();
  }
}

@riverpod
// ignore: deprecated_member_use_from_same_package
List<Task> overdueTasks(OverdueTasksRef ref) {
  final tasks = ref.watch(taskListProvider).valueOrNull ?? [];
  return tasks.where((t) => isOverdue(t.dueDate, t.dueTime)).toList();
}

@riverpod
// ignore: deprecated_member_use_from_same_package
List<Task> upcomingTasks(UpcomingTasksRef ref) {
  final tasks = ref.watch(taskListProvider).valueOrNull ?? [];
  return tasks.where((t) => !isOverdue(t.dueDate, t.dueTime)).toList();
}

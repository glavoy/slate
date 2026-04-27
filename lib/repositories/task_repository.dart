import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../local/local_database.dart';
import '../models/recurrence.dart';
import '../models/task.dart';
import '../sync/sync_service.dart';
import '../utils/date_utils.dart';

class TaskRepository {
  TaskRepository(this._client);

  final SupabaseClient _client;
  final _local = LocalDatabase.instance;
  static const _uuid = Uuid();

  Future<List<Task>> fetchActiveTasks() async {
    final userId = _client.auth.currentUser!.id;
    final rows = _local.select(
      '''
      SELECT * FROM tasks
      WHERE user_id = ? AND is_done = 0 AND pending_delete = 0
      ORDER BY due_date ASC, due_time ASC
      ''',
      [userId],
    );
    return rows.map(_taskFromRow).toList();
  }

  Future<List<Task>> fetchCompleted({bool showAll = false}) async {
    final userId = _client.auth.currentUser!.id;
    final params = <Object?>[userId];
    var where = 'user_id = ? AND is_done = 1 AND pending_delete = 0';
    if (!showAll) {
      final weekAgo = DateTime.now()
          .subtract(const Duration(days: 7))
          .toUtc()
          .toIso8601String();
      where += ' AND completed_at >= ?';
      params.add(weekAgo);
    }
    final rows = _local.select('''
      SELECT * FROM tasks
      WHERE $where
      ORDER BY completed_at DESC
      LIMIT 100
      ''', params);
    return rows.map(_taskFromRow).toList();
  }

  Future<void> markDone(Task task) async {
    final userId = _client.auth.currentUser!.id;
    final now = nowIso();
    _local.transaction(() {
      var seriesId = task.seriesId;
      if (task.recurrence != RecurrenceType.none) {
        seriesId ??= task.id;
      }
      _local.execute(
        '''
        UPDATE tasks
        SET is_done = 1,
            completed_at = ?,
            series_id = ?,
            updated_at = ?,
            client_modified_at = ?,
            sync_status = 'pending'
        WHERE id = ?
        ''',
        [now, seriesId, now, now, task.id],
      );

      if (task.recurrence != RecurrenceType.none) {
        final nextDue = nextOccurrence(task.dueDate, task.recurrence);
        final nextId = _uuid.v4();
        _local.execute(
          '''
          INSERT INTO tasks (
            id, user_id, title, due_date, notes, is_done, recurrence,
            due_time, series_id, created_at, completed_at, updated_at,
            sync_status, client_modified_at, pending_delete
          ) VALUES (?, ?, ?, ?, ?, 0, ?, ?, ?, ?, NULL, ?, 'pending', ?, 0)
          ''',
          [
            nextId,
            userId,
            task.title,
            nextDue.toIso8601String().substring(0, 10),
            task.notes,
            task.recurrence.name,
            task.dueTime,
            seriesId,
            now,
            now,
            now,
          ],
        );
      }
    });
    SyncService.instance.syncSoon();
  }

  Future<void> undoComplete(Task task) async {
    final now = nowIso();
    _local.transaction(() {
      _local.execute(
        '''
        UPDATE tasks
        SET is_done = 0,
            completed_at = NULL,
            updated_at = ?,
            client_modified_at = ?,
            sync_status = 'pending'
        WHERE id = ?
        ''',
        [now, now, task.id],
      );

      if (task.recurrence != RecurrenceType.none && task.seriesId != null) {
        final nextDue = nextOccurrence(
          task.dueDate,
          task.recurrence,
        ).toIso8601String().substring(0, 10);
        _local.execute(
          '''
          UPDATE tasks
          SET pending_delete = 1,
              sync_status = 'pending',
              client_modified_at = ?,
              updated_at = ?
          WHERE series_id = ?
            AND due_date = ?
            AND is_done = 0
          ''',
          [now, now, task.seriesId, nextDue],
        );
      }
    });
    SyncService.instance.syncSoon();
  }

  Future<void> deleteTask(String taskId) async {
    await _markDeleted('id = ?', [taskId]);
  }

  Future<void> deleteAllInSeries(String seriesId) async {
    await _markDeleted('series_id = ? AND is_done = 0', [seriesId]);
  }

  Future<Task> createTask({
    required String title,
    required DateTime dueDate,
    required TimeOfDay dueTime,
    String? notes,
    RecurrenceType recurrence = RecurrenceType.none,
  }) async {
    final now = nowIso();
    final id = _uuid.v4();
    final seriesId = recurrence != RecurrenceType.none ? _uuid.v4() : null;
    _local.execute(
      '''
      INSERT INTO tasks (
        id, user_id, title, due_date, notes, is_done, recurrence, due_time,
        series_id, created_at, completed_at, updated_at, sync_status,
        client_modified_at, pending_delete
      ) VALUES (?, ?, ?, ?, ?, 0, ?, ?, ?, ?, NULL, ?, 'pending', ?, 0)
      ''',
      [
        id,
        _client.auth.currentUser!.id,
        title,
        dueDate.toIso8601String().substring(0, 10),
        notes,
        recurrence.name,
        timeOfDayToString(dueTime),
        seriesId,
        now,
        now,
        now,
      ],
    );
    SyncService.instance.syncSoon();
    return _taskFromRow(
      _local.selectOne('SELECT * FROM tasks WHERE id = ?', [id])!,
    );
  }

  Future<Task> updateTask({
    required String taskId,
    required String title,
    required DateTime dueDate,
    required TimeOfDay dueTime,
    String? notes,
    required RecurrenceType recurrence,
  }) async {
    final now = nowIso();
    _local.execute(
      '''
      UPDATE tasks
      SET title = ?,
          due_date = ?,
          due_time = ?,
          notes = ?,
          recurrence = ?,
          updated_at = ?,
          client_modified_at = ?,
          sync_status = 'pending'
      WHERE id = ?
      ''',
      [
        title,
        dueDate.toIso8601String().substring(0, 10),
        timeOfDayToString(dueTime),
        notes,
        recurrence.name,
        now,
        now,
        taskId,
      ],
    );
    SyncService.instance.syncSoon();
    return _taskFromRow(
      _local.selectOne('SELECT * FROM tasks WHERE id = ?', [taskId])!,
    );
  }

  Future<void> updateAllInSeries({
    required String seriesId,
    required String title,
    required TimeOfDay dueTime,
    String? notes,
    required RecurrenceType recurrence,
  }) async {
    final now = nowIso();
    _local.execute(
      '''
      UPDATE tasks
      SET title = ?,
          due_time = ?,
          notes = ?,
          recurrence = ?,
          updated_at = ?,
          client_modified_at = ?,
          sync_status = 'pending'
      WHERE series_id = ? AND is_done = 0
      ''',
      [
        title,
        timeOfDayToString(dueTime),
        notes,
        recurrence.name,
        now,
        now,
        seriesId,
      ],
    );
    SyncService.instance.syncSoon();
  }

  Future<void> _markDeleted(String where, List<Object?> params) async {
    final now = nowIso();
    _local.execute(
      '''
      UPDATE tasks
      SET pending_delete = 1,
          sync_status = 'pending',
          sync_deleted_at = ?,
          updated_at = ?,
          client_modified_at = ?
      WHERE $where
      ''',
      [now, now, now, ...params],
    );
    SyncService.instance.syncSoon();
  }

  Task _taskFromRow(Map<String, Object?> row) {
    return Task.fromJson({...row, 'is_done': sqlToBool(row['is_done'])});
  }
}

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/task.dart';
import '../models/recurrence.dart';
import '../utils/date_utils.dart';

class TaskRepository {
  final SupabaseClient _client;
  static const _uuid = Uuid();

  const TaskRepository(this._client);

  Future<List<Task>> fetchActiveTasks() async {
    final response = await _client
        .from('tasks')
        .select()
        .eq('is_done', false)
        .order('due_date', ascending: true)
        .order('due_time', ascending: true);
    return (response as List).map((e) => Task.fromJson(e)).toList();
  }

  Future<List<Task>> fetchCompleted({bool showAll = false}) async {
    var query = _client.from('tasks').select().eq('is_done', true);
    if (!showAll) {
      final weekAgo = DateTime.now()
          .subtract(const Duration(days: 7))
          .toUtc()
          .toIso8601String();
      query = query.gte('completed_at', weekAgo);
    }
    final response =
        await query.order('completed_at', ascending: false).limit(100);
    return (response as List).map((e) => Task.fromJson(e)).toList();
  }

  Future<void> markDone(Task task) async {
    final now = DateTime.now().toUtc();
    await _client.from('tasks').update({
      'is_done': true,
      'completed_at': now.toIso8601String(),
    }).eq('id', task.id);

    if (task.recurrence != RecurrenceType.none) {
      final nextDue = nextOccurrence(task.dueDate, task.recurrence);
      await _client.from('tasks').insert({
        'title': task.title,
        'due_date': nextDue.toIso8601String().substring(0, 10),
        'due_time': task.dueTime,
        'notes': task.notes,
        'recurrence': task.recurrence.name,
        if (task.seriesId != null) 'series_id': task.seriesId,
      });
    }
  }

  Future<void> undoComplete(Task task) async {
    await _client.from('tasks').update({
      'is_done': false,
      'completed_at': null,
    }).eq('id', task.id);

    if (task.recurrence != RecurrenceType.none && task.seriesId != null) {
      final nextDue = nextOccurrence(task.dueDate, task.recurrence);
      final nextDueStr = nextDue.toIso8601String().substring(0, 10);
      await _client
          .from('tasks')
          .delete()
          .eq('series_id', task.seriesId!)
          .eq('due_date', nextDueStr)
          .eq('is_done', false);
    }
  }

  Future<void> deleteTask(String taskId) async {
    await _client.from('tasks').delete().eq('id', taskId);
  }

  Future<void> deleteAllInSeries(String seriesId) async {
    await _client
        .from('tasks')
        .delete()
        .eq('series_id', seriesId)
        .eq('is_done', false);
  }

  Future<Task> createTask({
    required String title,
    required DateTime dueDate,
    required TimeOfDay dueTime,
    String? notes,
    RecurrenceType recurrence = RecurrenceType.none,
  }) async {
    final seriesId =
        recurrence != RecurrenceType.none ? _uuid.v4() : null;
    final response = await _client
        .from('tasks')
        .insert({
          'title': title,
          'due_date': dueDate.toIso8601String().substring(0, 10),
          'due_time': timeOfDayToString(dueTime),
          'notes': notes,
          'recurrence': recurrence.name,
          if (seriesId != null) 'series_id': seriesId,
        })
        .select()
        .single();
    return Task.fromJson(response);
  }

  Future<Task> updateTask({
    required String taskId,
    required String title,
    required DateTime dueDate,
    required TimeOfDay dueTime,
    String? notes,
    required RecurrenceType recurrence,
  }) async {
    final response = await _client
        .from('tasks')
        .update({
          'title': title,
          'due_date': dueDate.toIso8601String().substring(0, 10),
          'due_time': timeOfDayToString(dueTime),
          'notes': notes,
          'recurrence': recurrence.name,
        })
        .eq('id', taskId)
        .select()
        .single();
    return Task.fromJson(response);
  }

  Future<void> updateAllInSeries({
    required String seriesId,
    required String title,
    required TimeOfDay dueTime,
    String? notes,
    required RecurrenceType recurrence,
  }) async {
    await _client
        .from('tasks')
        .update({
          'title': title,
          'due_time': timeOfDayToString(dueTime),
          'notes': notes,
          'recurrence': recurrence.name,
        })
        .eq('series_id', seriesId)
        .eq('is_done', false);
  }
}

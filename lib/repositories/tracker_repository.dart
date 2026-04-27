import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../local/local_database.dart';
import '../models/tracker_entry.dart';
import '../models/tracker_metric.dart';
import '../sync/sync_service.dart';

class TrackerRepository {
  TrackerRepository(this._client);

  final SupabaseClient _client;
  final _local = LocalDatabase.instance;
  static const _uuid = Uuid();

  Future<List<TrackerMetric>> fetchMetrics() async {
    final userId = _client.auth.currentUser!.id;
    final rows = _local.select(
      '''
      SELECT * FROM tracker_metrics
      WHERE user_id = ? AND pending_delete = 0
      ORDER BY created_at ASC
      ''',
      [userId],
    );
    return rows.map((r) => TrackerMetric.fromJson(r)).toList();
  }

  Future<TrackerMetric> createMetric({
    required String name,
    String? unit,
  }) async {
    final id = _uuid.v4();
    final now = nowIso();
    _local.execute(
      '''
      INSERT INTO tracker_metrics (
        id, user_id, name, unit, created_at, updated_at, sync_status,
        client_modified_at, pending_delete
      ) VALUES (?, ?, ?, ?, ?, ?, 'pending', ?, 0)
      ''',
      [id, _client.auth.currentUser!.id, name, unit, now, now, now],
    );
    SyncService.instance.syncSoon();
    return TrackerMetric.fromJson(
      _local.selectOne('SELECT * FROM tracker_metrics WHERE id = ?', [id])!,
    );
  }

  Future<void> deleteMetric(String id) async {
    final now = nowIso();
    _local.transaction(() {
      _local.execute(
        '''
        UPDATE tracker_entries
        SET pending_delete = 1,
            sync_deleted_at = ?,
            updated_at = ?,
            client_modified_at = ?,
            sync_status = 'pending'
        WHERE metric_id = ?
        ''',
        [now, now, now, id],
      );
      _local.execute(
        '''
        UPDATE tracker_metrics
        SET pending_delete = 1,
            sync_deleted_at = ?,
            updated_at = ?,
            client_modified_at = ?,
            sync_status = 'pending'
        WHERE id = ?
        ''',
        [now, now, now, id],
      );
    });
    SyncService.instance.syncSoon();
  }

  Future<List<TrackerEntry>> fetchEntries(String metricId, {int? limit}) async {
    final userId = _client.auth.currentUser!.id;
    final rows = _local.select('''
      SELECT * FROM tracker_entries
      WHERE user_id = ? AND metric_id = ? AND pending_delete = 0
      ORDER BY recorded_at DESC
      ${limit == null ? '' : 'LIMIT ?'}
      ''', limit == null ? [userId, metricId] : [userId, metricId, limit]);
    return rows.map((r) => TrackerEntry.fromJson(r)).toList();
  }

  Future<TrackerEntry> addEntry({
    required String metricId,
    required double value,
    String? note,
    DateTime? recordedAt,
  }) async {
    final id = _uuid.v4();
    final now = nowIso();
    _local.execute(
      '''
      INSERT INTO tracker_entries (
        id, metric_id, user_id, value, recorded_at, note, updated_at,
        sync_status, client_modified_at, pending_delete
      ) VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', ?, 0)
      ''',
      [
        id,
        metricId,
        _client.auth.currentUser!.id,
        value,
        (recordedAt ?? DateTime.now()).toUtc().toIso8601String(),
        note,
        now,
        now,
      ],
    );
    SyncService.instance.syncSoon();
    return TrackerEntry.fromJson(
      _local.selectOne('SELECT * FROM tracker_entries WHERE id = ?', [id])!,
    );
  }

  Future<void> deleteEntry(String id) async {
    final now = nowIso();
    _local.execute(
      '''
      UPDATE tracker_entries
      SET pending_delete = 1,
          sync_deleted_at = ?,
          updated_at = ?,
          client_modified_at = ?,
          sync_status = 'pending'
      WHERE id = ?
      ''',
      [now, now, now, id],
    );
    SyncService.instance.syncSoon();
  }
}

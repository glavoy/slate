import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../local/local_database.dart';
import '../models/journal_entry.dart';
import '../sync/sync_service.dart';

class JournalRepository {
  JournalRepository(this._client);

  final SupabaseClient _client;
  final _local = LocalDatabase.instance;
  static const _uuid = Uuid();

  Future<List<JournalEntry>> fetchAll({int? limit}) async {
    final userId = _client.auth.currentUser!.id;
    final rows = _local.select('''
      SELECT * FROM journal_entries
      WHERE user_id = ? AND pending_delete = 0
      ORDER BY entry_date DESC
      ${limit == null ? '' : 'LIMIT ?'}
      ''', limit == null ? [userId] : [userId, limit]);
    return rows.map((r) => JournalEntry.fromJson(r)).toList();
  }

  Future<void> upsertForDate(DateTime date, String content) async {
    final userId = _client.auth.currentUser!.id;
    final dateStr = date.toIso8601String().substring(0, 10);
    final now = nowIso();
    final existing = _local.selectOne(
      '''
      SELECT id FROM journal_entries
      WHERE user_id = ? AND entry_date = ?
      ''',
      [userId, dateStr],
    );
    if (existing == null) {
      _local.execute(
        '''
        INSERT INTO journal_entries (
          id, user_id, entry_date, content, created_at, updated_at,
          sync_status, client_modified_at, pending_delete
        ) VALUES (?, ?, ?, ?, ?, ?, 'pending', ?, 0)
        ''',
        [_uuid.v4(), userId, dateStr, content, now, now, now],
      );
    } else {
      _local.execute(
        '''
        UPDATE journal_entries
        SET content = ?,
            updated_at = ?,
            client_modified_at = ?,
            sync_status = 'pending'
        WHERE id = ?
        ''',
        [content, now, now, existing['id']],
      );
    }
    SyncService.instance.syncSoon();
  }

  Future<void> delete(String id) async {
    final now = nowIso();
    _local.execute(
      '''
      UPDATE journal_entries
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

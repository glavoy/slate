import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../local/local_database.dart';
import '../models/note.dart';
import '../sync/sync_service.dart';

class NoteRepository {
  NoteRepository(this._client);

  final SupabaseClient _client;
  final _local = LocalDatabase.instance;
  static const _uuid = Uuid();

  Future<List<Note>> fetchAll() async {
    final userId = _client.auth.currentUser!.id;
    final rows = _local.select(
      '''
      SELECT * FROM notes
      WHERE user_id = ? AND deleted_at IS NULL AND pending_delete = 0
      ORDER BY pinned DESC, updated_at DESC
      ''',
      [userId],
    );
    return rows.map(_noteFromRow).toList();
  }

  Future<List<Note>> fetchDeleted() async {
    final userId = _client.auth.currentUser!.id;
    final rows = _local.select(
      '''
      SELECT * FROM notes
      WHERE user_id = ? AND deleted_at IS NOT NULL AND pending_delete = 0
      ORDER BY deleted_at DESC
      ''',
      [userId],
    );
    return rows.map(_noteFromRow).toList();
  }

  Future<Note> create({String title = '', String content = ''}) async {
    final now = nowIso();
    final id = _uuid.v4();
    _local.execute(
      '''
      INSERT INTO notes (
        id, user_id, title, content, pinned, deleted_at, created_at,
        updated_at, sync_status, client_modified_at, pending_delete
      ) VALUES (?, ?, ?, ?, 0, NULL, ?, ?, 'pending', ?, 0)
      ''',
      [id, _client.auth.currentUser!.id, title, content, now, now, now],
    );
    SyncService.instance.syncSoon();
    return _noteFromRow(
      _local.selectOne('SELECT * FROM notes WHERE id = ?', [id])!,
    );
  }

  Future<void> update(String id, {String? title, String? content}) async {
    final now = nowIso();
    final fields = <String>['updated_at = ?', 'client_modified_at = ?'];
    final values = <Object?>[now, now];
    if (title != null) {
      fields.add('title = ?');
      values.add(title);
    }
    if (content != null) {
      fields.add('content = ?');
      values.add(content);
    }
    values.add(id);
    _local.execute('''
      UPDATE notes
      SET ${fields.join(', ')}, sync_status = 'pending'
      WHERE id = ?
      ''', values);
    SyncService.instance.syncSoon();
  }

  Future<void> setPin(String id, {required bool pinned}) async {
    final now = nowIso();
    _local.execute(
      '''
      UPDATE notes
      SET pinned = ?,
          updated_at = ?,
          client_modified_at = ?,
          sync_status = 'pending'
      WHERE id = ?
      ''',
      [boolToSql(pinned), now, now, id],
    );
    SyncService.instance.syncSoon();
  }

  Future<void> softDelete(String id) async {
    final now = nowIso();
    _local.execute(
      '''
      UPDATE notes
      SET deleted_at = ?,
          updated_at = ?,
          client_modified_at = ?,
          sync_status = 'pending'
      WHERE id = ?
      ''',
      [now, now, now, id],
    );
    SyncService.instance.syncSoon();
  }

  Future<void> restore(String id) async {
    final now = nowIso();
    _local.execute(
      '''
      UPDATE notes
      SET deleted_at = NULL,
          updated_at = ?,
          client_modified_at = ?,
          sync_status = 'pending'
      WHERE id = ?
      ''',
      [now, now, id],
    );
    SyncService.instance.syncSoon();
  }

  Future<void> permanentlyDelete(String id) async {
    final now = nowIso();
    _local.execute(
      '''
      UPDATE notes
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

  Note _noteFromRow(Map<String, Object?> row) {
    return Note.fromJson({...row, 'pinned': sqlToBool(row['pinned'])});
  }
}

import 'package:supabase_flutter/supabase_flutter.dart';

import '../local/local_database.dart';
import '../models/simple_list.dart';
import '../sync/sync_service.dart';

class SimpleListRepository {
  SimpleListRepository(this._client);

  final SupabaseClient _client;
  final _local = LocalDatabase.instance;

  Future<SimpleList> fetch() async {
    final userId = _client.auth.currentUser!.id;
    final row = _local.selectOne(
      '''
      SELECT * FROM simple_list
      WHERE user_id = ? AND pending_delete = 0
      ''',
      [userId],
    );
    if (row != null) {
      return SimpleList.fromJson(row);
    }

    // Do not create a pending default row during the initial local read. On a
    // fresh device that can race the first remote pull and overwrite an
    // existing list from another device.
    return SimpleList(
      userId: userId,
      content: '• ',
      updatedAt: DateTime.now().toUtc(),
    );
  }

  Future<void> save(String content) async {
    final userId = _client.auth.currentUser!.id;
    final now = nowIso();
    _local.execute(
      '''
      INSERT INTO simple_list (
        user_id, content, updated_at, sync_status, client_modified_at,
        pending_delete
      ) VALUES (?, ?, ?, 'pending', ?, 0)
      ON CONFLICT(user_id) DO UPDATE SET
        content = excluded.content,
        updated_at = excluded.updated_at,
        client_modified_at = excluded.client_modified_at,
        sync_status = 'pending',
        pending_delete = 0
      ''',
      [userId, content, now, now],
    );
    SyncService.instance.syncSoon();
  }
}

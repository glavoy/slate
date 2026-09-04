import 'package:supabase_flutter/supabase_flutter.dart';

typedef RemoteRow = Map<String, dynamic>;

/// Position within a stable `(updated_at, key)` ordering used for paginated
/// pulls. [since] is only used for the first page; later pages advance from
/// [afterUpdatedAt] and [afterKey] without relying on a shifting offset.
class SyncPullCursor {
  const SyncPullCursor({this.since, this.afterUpdatedAt, this.afterKey});

  final String? since;
  final String? afterUpdatedAt;
  final Object? afterKey;

  bool get hasPosition => afterUpdatedAt != null && afterKey != null;

  SyncPullCursor after(RemoteRow row, String keyColumn) => SyncPullCursor(
    since: since,
    afterUpdatedAt: row['updated_at']?.toString(),
    afterKey: row[keyColumn],
  );
}

/// An insert collided with an existing row (primary key or unique constraint).
class RemoteUniqueViolation implements Exception {
  RemoteUniqueViolation(this.table);

  final String table;

  @override
  String toString() => 'RemoteUniqueViolation($table)';
}

/// The server operations the sync engine needs, kept minimal so tests can run
/// the engine against an in-memory fake server.
///
/// All mutating calls return the row as stored on the server so the caller can
/// record the server-stamped `version` and `updated_at` — those two columns are
/// server-owned and must never be sent by clients.
abstract class SyncRemote {
  /// Inserts a new row and returns it as stored. Throws
  /// [RemoteUniqueViolation] when the row already exists.
  Future<RemoteRow> insert(String table, RemoteRow payload);

  /// Compare-and-swap update: applies [payload] only if the server row still
  /// has [expectedVersion]. Returns the stored row, or null on version
  /// mismatch — including a row that no longer exists at all.
  Future<RemoteRow?> casUpdate(
    String table,
    String keyColumn,
    Object key,
    int expectedVersion,
    RemoteRow payload,
  );

  /// Marks a row deleted (tombstone). A missing row is a no-op.
  Future<void> tombstone(
    String table,
    String keyColumn,
    Object key,
    String deletedAt,
  );

  /// Fetches the single row matching all [filters], or null.
  Future<RemoteRow?> fetchWhere(String table, Map<String, Object?> filters);

  /// One keyset-paginated page for [userId], ordered by
  /// `(updated_at, keyColumn)`.
  Future<List<RemoteRow>> pullSince(
    String table, {
    required String userId,
    required String keyColumn,
    required SyncPullCursor cursor,
    required int limit,
  });
}

class SupabaseSyncRemote implements SyncRemote {
  SupabaseSyncRemote(this._client);

  final SupabaseClient _client;

  static const _uniqueViolationCode = '23505';

  @override
  Future<RemoteRow> insert(String table, RemoteRow payload) async {
    try {
      final rows = await _client.from(table).insert(payload).select();
      return rows.first;
    } on PostgrestException catch (e) {
      if (e.code == _uniqueViolationCode) throw RemoteUniqueViolation(table);
      rethrow;
    }
  }

  @override
  Future<RemoteRow?> casUpdate(
    String table,
    String keyColumn,
    Object key,
    int expectedVersion,
    RemoteRow payload,
  ) async {
    final rows = await _client
        .from(table)
        .update(payload)
        .eq(keyColumn, key)
        .eq('version', expectedVersion)
        .select();
    return rows.isEmpty ? null : rows.first;
  }

  @override
  Future<void> tombstone(
    String table,
    String keyColumn,
    Object key,
    String deletedAt,
  ) async {
    try {
      // updated_at is stamped by the server trigger; we only set the tombstone.
      await _client
          .from(table)
          .update({'sync_deleted_at': deletedAt})
          .eq(keyColumn, key);
    } catch (_) {
      await _client.from(table).delete().eq(keyColumn, key);
    }
  }

  @override
  Future<RemoteRow?> fetchWhere(
    String table,
    Map<String, Object?> filters,
  ) async {
    dynamic query = _client.from(table).select();
    for (final entry in filters.entries) {
      query = query.eq(entry.key, entry.value);
    }
    final dynamic row = await query.limit(1).maybeSingle();
    return row as RemoteRow?;
  }

  @override
  Future<List<RemoteRow>> pullSince(
    String table, {
    required String userId,
    required String keyColumn,
    required SyncPullCursor cursor,
    required int limit,
  }) async {
    dynamic query = _client.from(table).select().eq('user_id', userId);
    if (cursor.hasPosition) {
      final updatedAt = cursor.afterUpdatedAt!;
      final key = cursor.afterKey!;
      query = query.or(
        'updated_at.gt.$updatedAt,and(updated_at.eq.$updatedAt,$keyColumn.gt.$key)',
      );
    } else if (cursor.since != null) {
      query = query.gte('updated_at', cursor.since!);
    }
    query = query
        .order('updated_at', ascending: true)
        .order(keyColumn, ascending: true)
        .limit(limit);
    final dynamic response = await query;
    return (response as List).cast<RemoteRow>();
  }
}

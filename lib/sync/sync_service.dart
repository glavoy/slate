import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../local/local_database.dart';

class SyncService {
  SyncService._();

  static final instance = SyncService._();

  SupabaseClient? _client;
  LocalDatabase? _local;
  StreamSubscription<dynamic>? _connectivitySubscription;
  RealtimeChannel? _realtimeChannel;
  Timer? _periodicSyncTimer;
  final _changes = StreamController<void>.broadcast();
  bool _syncing = false;
  bool _syncRequested = false;
  DateTime? _syncStartedAt;

  static const periodicSyncInterval = Duration(seconds: 60);
  static const syncTimeout = Duration(seconds: 25);
  static const realtimeReconnectTimeout = Duration(seconds: 5);
  static const _pullPageSize = 1000;

  static const _tables = <_SyncTable>[
    _SyncTable('tasks', 'id'),
    _SyncTable('notes', 'id'),
    _SyncTable(
      'journal_entries',
      'id',
      upsertConflict: 'user_id,entry_date',
      localConflict: 'user_id, entry_date',
    ),
    _SyncTable('simple_list', 'user_id'),
    _SyncTable('tracker_metrics', 'id'),
    _SyncTable('tracker_entries', 'id'),
  ];

  void configure({
    required SupabaseClient client,
    required LocalDatabase local,
  }) {
    _client = client;
    _local = local;
    _connectivitySubscription ??= Connectivity().onConnectivityChanged.listen(
      (_) => syncSoon(),
    );
    _periodicSyncTimer ??= Timer.periodic(
      periodicSyncInterval,
      (_) => syncSoon(),
    );
    _subscribeToRealtime(client);
  }

  Stream<void> get changes => _changes.stream;

  Future<void> syncAfterResume() async {
    await _reconnectRealtime();
    await syncNow(force: true);
  }

  Future<void> forceFullPull() async {
    final local = _local;
    if (local == null) return;

    local.deleteMeta('last_sync_at');
    await syncNow(force: true);
  }

  void syncSoonAfterResume() {
    unawaited(syncAfterResume());
  }

  Future<void> syncNow({bool force = false}) async {
    final client = _client;
    final local = _local;
    final user = client?.auth.currentUser;
    if (client == null || local == null || user == null) return;
    if (_syncing) {
      if (!force || !_syncLooksStale()) {
        _syncRequested = true;
        return;
      }
      _logSyncMessage('forcing sync after stale in-flight sync');
      _syncing = false;
    }

    await _runSync(client, local, user.id).timeout(
      syncTimeout,
      onTimeout: () {
        _logSyncMessage('sync timed out');
        _syncing = false;
        _syncStartedAt = null;
        _syncRequested = true;
      },
    );
  }

  Future<void> _runSync(
    SupabaseClient client,
    LocalDatabase local,
    String userId,
  ) async {
    _syncing = true;
    _syncStartedAt = DateTime.now();
    final previousSyncAt = local.getMeta('last_sync_at');
    final syncStartedAt = nowIso();
    try {
      await _pullRemote(client, local, userId, since: previousSyncAt);
      await _pushPending(client, local, userId);
      await _pullRemote(client, local, userId, since: previousSyncAt);
      local.setMeta('last_sync_at', syncStartedAt);
      _changes.add(null);
    } catch (error, stackTrace) {
      // The app remains local-first. Failed sync attempts are retried on the
      // next app start, connectivity change, or local write.
      _logSyncError('syncNow', error, stackTrace);
    } finally {
      _syncing = false;
      _syncStartedAt = null;
      if (_syncRequested) {
        _syncRequested = false;
        unawaited(syncNow());
      }
    }
  }

  void syncSoon() {
    unawaited(syncNow());
  }

  bool _syncLooksStale() {
    final startedAt = _syncStartedAt;
    if (startedAt == null) return true;
    return DateTime.now().difference(startedAt) > syncTimeout;
  }

  void _subscribeToRealtime(SupabaseClient client) {
    if (_realtimeChannel != null) return;

    var channel = client.channel('slate-sync');
    for (final table in _tables) {
      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table.name,
        callback: (payload) => _handleRealtimePayload(table, payload),
      );
    }
    _realtimeChannel = channel.subscribe();
  }

  Future<void> _reconnectRealtime() async {
    final client = _client;
    if (client == null) return;
    final channel = _realtimeChannel;
    _realtimeChannel = null;
    if (channel != null) {
      try {
        await client.removeChannel(channel).timeout(realtimeReconnectTimeout);
      } catch (error, stackTrace) {
        _logSyncError('realtime reconnect', error, stackTrace);
      }
    }
    _subscribeToRealtime(client);
  }

  void _handleRealtimePayload(_SyncTable table, PostgresChangePayload payload) {
    final client = _client;
    final local = _local;
    final user = client?.auth.currentUser;
    if (client == null || local == null || user == null) return;

    try {
      final syncTime = nowIso();
      if (payload.eventType == PostgresChangeEvent.delete) {
        final row = payload.oldRecord;
        if (row['user_id'] == null || row['user_id'] == user.id) {
          final key = row[table.keyColumn];
          if (key != null) {
            local.execute(
              '''
              DELETE FROM ${table.name}
              WHERE ${table.keyColumn} = ? AND user_id = ?
              ''',
              [key, user.id],
            );
            _changes.add(null);
          }
        }
      } else {
        final row = payload.newRecord;
        if (row['user_id'] == null || row['user_id'] == user.id) {
          final changed = _applyRemoteRow(local, table, row, user.id, syncTime);
          if (changed) _changes.add(null);
        }
      }
    } catch (error, stackTrace) {
      // Fall through to a normal sync; realtime payload handling is an
      // acceleration path, not the authoritative merge path.
      _logSyncError('realtime ${table.name}', error, stackTrace);
    } finally {
      syncSoon();
    }
  }

  Future<void> _pushPending(
    SupabaseClient client,
    LocalDatabase local,
    String userId,
  ) async {
    final syncTime = nowIso();
    for (final table in _tables) {
      final rows = local.select(
        '''
          SELECT * FROM ${table.name}
          WHERE sync_status = ? AND user_id = ?
          ''',
        ['pending', userId],
      );
      for (final row in rows) {
        final key = row[table.keyColumn];
        if (key == null) continue;

        try {
          if (sqlToBool(row['pending_delete'])) {
            await _pushDelete(client, table, row, syncTime);
            if (pushedSnapshotStillCurrent(
              pushedClientModifiedAt: row['client_modified_at'],
              currentRow: _selectExistingLocal(local, table, row),
            )) {
              local.execute(
                '''
                DELETE FROM ${table.name}
                WHERE ${table.keyColumn} = ?
                  AND user_id = ?
                  AND sync_status = 'pending'
                  AND client_modified_at = ?
                ''',
                [key, userId, row['client_modified_at']],
              );
            }
            continue;
          }

          await _pushUpsert(client, table, row);
          if (pushedSnapshotStillCurrent(
            pushedClientModifiedAt: row['client_modified_at'],
            currentRow: _selectExistingLocal(local, table, row),
          )) {
            local.execute(
              '''
              UPDATE ${table.name}
              SET sync_status = 'synced', last_synced_at = ?
              WHERE ${table.keyColumn} = ?
                AND user_id = ?
                AND sync_status = 'pending'
                AND client_modified_at = ?
              ''',
              [syncTime, key, userId, row['client_modified_at']],
            );
          }
        } catch (error, stackTrace) {
          // Leave the row pending; a later sync attempt can retry it.
          _logSyncError('push ${table.name}', error, stackTrace);
        }
      }
    }
  }

  Future<void> _pushDelete(
    SupabaseClient client,
    _SyncTable table,
    Map<String, Object?> row,
    String syncTime,
  ) async {
    final key = row[table.keyColumn];
    final timestamp = row['client_modified_at'] ?? syncTime;
    try {
      await client
          .from(table.name)
          .update({'sync_deleted_at': timestamp, 'updated_at': timestamp})
          .eq(table.keyColumn, key!);
    } catch (_) {
      await client.from(table.name).delete().eq(table.keyColumn, key!);
    }
  }

  Future<void> _pushUpsert(
    SupabaseClient client,
    _SyncTable table,
    Map<String, Object?> row,
  ) async {
    final payload = _remotePayload(table.name, row);
    if (table.name == 'journal_entries') {
      await _pushJournalEntry(client, table, payload);
      return;
    }
    if (table.upsertConflict == null) {
      await client.from(table.name).upsert(payload);
    } else {
      await client
          .from(table.name)
          .upsert(payload, onConflict: table.upsertConflict);
    }
  }

  Future<void> _pushJournalEntry(
    SupabaseClient client,
    _SyncTable table,
    Map<String, dynamic> payload,
  ) async {
    try {
      await client
          .from(table.name)
          .upsert(payload, onConflict: table.upsertConflict);
      return;
    } catch (_) {
      final existing = await client
          .from(table.name)
          .select('id')
          .eq('entry_date', payload['entry_date'])
          .maybeSingle();
      if (existing == null) {
        await client.from(table.name).insert(payload);
      } else {
        await client.from(table.name).update(payload).eq('id', existing['id']);
      }
    }
  }

  Future<void> _pullRemote(
    SupabaseClient client,
    LocalDatabase local,
    String userId, {
    String? since,
  }) async {
    final syncTime = nowIso();
    for (final table in _tables) {
      var from = 0;

      while (true) {
        try {
          dynamic query = client
              .from(table.name)
              .select()
              .eq('user_id', userId);
          if (since != null) {
            query = query.gte('updated_at', since);
          }
          query = query
              .order(table.keyColumn)
              .range(from, from + _pullPageSize - 1);
          final dynamic response = await query;
          final rows = (response as List).cast<Map<String, dynamic>>();
          for (final row in rows) {
            _applyRemoteRow(local, table, row, userId, syncTime);
          }

          if (rows.length < _pullPageSize) break;
          from += _pullPageSize;
        } catch (error, stackTrace) {
          // Continue pulling other tables even if one table is unavailable.
          _logSyncError('pull ${table.name}', error, stackTrace);
          break;
        }
      }
    }
  }

  bool _applyRemoteRow(
    LocalDatabase local,
    _SyncTable table,
    Map<String, dynamic> row,
    String userId,
    String syncTime,
  ) {
    final key = row[table.keyColumn];
    if (key == null) return false;
    if (row['user_id'] != null && row['user_id'] != userId) return false;

    final existing = _selectExistingLocal(local, table, row);
    if (existing != null && existing['sync_status'] == 'pending') {
      if (!remoteWinsPendingLocal(
        localClientModifiedAt: existing['client_modified_at'],
        remoteRow: row,
      )) {
        return false;
      }
    }

    if (row['sync_deleted_at'] != null) {
      local.execute(
        'DELETE FROM ${table.name} WHERE ${table.keyColumn} = ? AND user_id = ?',
        [key, userId],
      );
      return true;
    }

    _upsertLocalRemoteRow(local, table.name, row, userId, syncTime);
    return true;
  }

  Map<String, Object?>? _selectExistingLocal(
    LocalDatabase local,
    _SyncTable table,
    Map<String, dynamic> row,
  ) {
    if (table.localConflict == 'user_id, entry_date') {
      final userId = row['user_id'];
      final entryDate = row['entry_date'];
      if (userId != null && entryDate != null) {
        final existing = local.selectOne(
          '''
          SELECT * FROM ${table.name}
          WHERE user_id = ? AND entry_date = ?
          ''',
          [userId, entryDate],
        );
        if (existing != null) return existing;
      }
    }
    return local.selectOne(
      'SELECT * FROM ${table.name} WHERE ${table.keyColumn} = ?',
      [row[table.keyColumn]],
    );
  }

  Map<String, dynamic> _remotePayload(String table, Map<String, Object?> row) {
    final excluded = {
      'sync_status',
      'last_synced_at',
      'client_modified_at',
      'pending_delete',
    };
    final payload = <String, dynamic>{};
    for (final entry in row.entries) {
      if (excluded.contains(entry.key)) continue;
      if (!_columnsFor(table).contains(entry.key)) continue;
      if (entry.key == 'sync_deleted_at' && entry.value == null) continue;
      final value = entry.value;
      if (value is int && _boolColumns(table).contains(entry.key)) {
        payload[entry.key] = value == 1;
      } else {
        payload[entry.key] = value;
      }
    }
    return payload;
  }

  void _upsertLocalRemoteRow(
    LocalDatabase local,
    String table,
    Map<String, dynamic> row,
    String userId,
    String syncTime,
  ) {
    final normalized = _normalizeRemoteRow(table, row, userId, syncTime);
    final columns = normalized.keys.toList();
    final placeholders = List.filled(columns.length, '?').join(', ');
    final assignments = columns.map((c) => '$c = excluded.$c').join(', ');
    local.execute('''
      INSERT INTO $table (${columns.join(', ')})
      VALUES ($placeholders)
      ON CONFLICT(${_localConflictFor(table)}) DO UPDATE SET $assignments
      ''', columns.map((c) => normalized[c]).toList());
  }

  Map<String, Object?> _normalizeRemoteRow(
    String table,
    Map<String, dynamic> row,
    String userId,
    String syncTime,
  ) {
    final updatedAt = (row['updated_at'] ?? row['created_at'] ?? syncTime)
        .toString();
    final raw = <String, Object?>{
      ...row,
      'user_id': row['user_id'] ?? userId,
      'updated_at': updatedAt,
      'sync_deleted_at': row['sync_deleted_at'],
      'sync_status': 'synced',
      'last_synced_at': syncTime,
      'client_modified_at': updatedAt,
      'pending_delete': 0,
    };
    final normalized = <String, Object?>{};
    for (final column in _columnsFor(table)) {
      if (raw.containsKey(column)) {
        normalized[column] = raw[column];
      }
    }
    for (final column in _boolColumns(table)) {
      if (normalized[column] is bool) {
        normalized[column] = (normalized[column] as bool) ? 1 : 0;
      }
    }
    return normalized;
  }

  String _localConflictFor(String table) {
    final config = _tables.firstWhere((t) => t.name == table);
    return config.localConflict ?? config.keyColumn;
  }

  Set<String> _boolColumns(String table) => switch (table) {
    'tasks' => {'is_done'},
    'notes' => {'pinned'},
    _ => const <String>{},
  };

  Set<String> _columnsFor(String table) => switch (table) {
    'tasks' => {
      'id',
      'user_id',
      'title',
      'due_date',
      'notes',
      'is_done',
      'recurrence',
      'due_time',
      'series_id',
      'created_at',
      'completed_at',
      'updated_at',
      'sync_deleted_at',
      'sync_status',
      'last_synced_at',
      'client_modified_at',
      'pending_delete',
    },
    'notes' => {
      'id',
      'user_id',
      'title',
      'content',
      'pinned',
      'deleted_at',
      'created_at',
      'updated_at',
      'sync_deleted_at',
      'sync_status',
      'last_synced_at',
      'client_modified_at',
      'pending_delete',
    },
    'journal_entries' => {
      'id',
      'user_id',
      'entry_date',
      'content',
      'created_at',
      'updated_at',
      'sync_deleted_at',
      'sync_status',
      'last_synced_at',
      'client_modified_at',
      'pending_delete',
    },
    'simple_list' => {
      'user_id',
      'content',
      'updated_at',
      'sync_deleted_at',
      'sync_status',
      'last_synced_at',
      'client_modified_at',
      'pending_delete',
    },
    'tracker_metrics' => {
      'id',
      'user_id',
      'name',
      'unit',
      'created_at',
      'updated_at',
      'sync_deleted_at',
      'sync_status',
      'last_synced_at',
      'client_modified_at',
      'pending_delete',
    },
    'tracker_entries' => {
      'id',
      'metric_id',
      'user_id',
      'value',
      'recorded_at',
      'note',
      'updated_at',
      'sync_deleted_at',
      'sync_status',
      'last_synced_at',
      'client_modified_at',
      'pending_delete',
    },
    _ => const <String>{},
  };

  @visibleForTesting
  static bool remoteWinsPendingLocal({
    required Object? localClientModifiedAt,
    required Map<String, dynamic> remoteRow,
  }) {
    final localTime = _parseTimestamp(localClientModifiedAt);
    final remoteTime = _remoteModifiedAt(remoteRow);
    if (localTime == null || remoteTime == null) return true;
    return !localTime.isAfter(remoteTime);
  }

  @visibleForTesting
  static bool pushedSnapshotStillCurrent({
    required Object? pushedClientModifiedAt,
    required Map<String, Object?>? currentRow,
  }) {
    return currentRow != null &&
        currentRow['sync_status'] == 'pending' &&
        currentRow['client_modified_at'] == pushedClientModifiedAt;
  }

  static DateTime? _parseTimestamp(Object? value) =>
      value == null ? null : DateTime.tryParse(value.toString());

  static DateTime? _remoteModifiedAt(Map<String, dynamic> row) =>
      _parseTimestamp(
        row['sync_deleted_at'] ?? row['updated_at'] ?? row['created_at'],
      );

  void _logSyncError(String operation, Object error, StackTrace stackTrace) {
    if (!kDebugMode) return;
    debugPrint('Slate sync $operation failed: $error');
    debugPrintStack(stackTrace: stackTrace);
  }

  void _logSyncMessage(String message) {
    if (!kDebugMode) return;
    debugPrint('Slate sync: $message');
  }
}

class _SyncTable {
  const _SyncTable(
    this.name,
    this.keyColumn, {
    this.upsertConflict,
    this.localConflict,
  });

  final String name;
  final String keyColumn;
  final String? upsertConflict;
  final String? localConflict;
}

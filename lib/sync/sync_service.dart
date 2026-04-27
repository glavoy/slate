import 'dart:async';
import 'dart:developer' as developer;

import 'package:connectivity_plus/connectivity_plus.dart';
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

  static const periodicSyncInterval = Duration(seconds: 60);

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
      (_) => syncNow(),
    );
    _periodicSyncTimer ??= Timer.periodic(
      periodicSyncInterval,
      (_) => syncNow(),
    );
    _subscribeToRealtime(client);
  }

  Stream<void> get changes => _changes.stream;

  Future<void> syncNow() async {
    final client = _client;
    final local = _local;
    final user = client?.auth.currentUser;
    if (client == null || local == null || user == null) return;
    if (_syncing) {
      _syncRequested = true;
      return;
    }

    _syncing = true;
    try {
      await _pushPending(client, local, user.id);
      await _pullRemote(client, local, user.id);
      local.setMeta('last_sync_at', nowIso());
      _changes.add(null);
    } catch (error, stackTrace) {
      // The app remains local-first. Failed sync attempts are retried on the
      // next app start, connectivity change, or local write.
      developer.log(
        'Sync failed',
        name: 'slate.sync',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _syncing = false;
      if (_syncRequested) {
        _syncRequested = false;
        unawaited(syncNow());
      }
    }
  }

  void syncSoon() {
    unawaited(syncNow());
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

  void _handleRealtimePayload(_SyncTable table, PostgresChangePayload payload) {
    final client = _client;
    final local = _local;
    final user = client?.auth.currentUser;
    if (client == null || local == null || user == null) return;

    try {
      final syncTime = nowIso();
      if (payload.eventType == PostgresChangeEvent.delete) {
        final key = payload.oldRecord[table.keyColumn];
        if (key != null) {
          local.execute(
            'DELETE FROM ${table.name} WHERE ${table.keyColumn} = ?',
            [key],
          );
          _changes.add(null);
        }
      } else {
        final row = payload.newRecord;
        if (row['user_id'] == null || row['user_id'] == user.id) {
          final changed = _applyRemoteRow(local, table, row, user.id, syncTime);
          if (changed) _changes.add(null);
        }
      }
    } catch (_) {
      // Fall through to a normal sync; realtime payload handling is an
      // acceleration path, not the authoritative merge path.
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

        if (sqlToBool(row['pending_delete'])) {
          await client
              .from(table.name)
              .update({
                'sync_deleted_at': row['client_modified_at'] ?? syncTime,
                'updated_at': row['client_modified_at'] ?? syncTime,
              })
              .eq(table.keyColumn, key);
          local.execute(
            'DELETE FROM ${table.name} WHERE ${table.keyColumn} = ?',
            [key],
          );
          continue;
        }

        final payload = _remotePayload(table.name, row);
        if (table.upsertConflict == null) {
          await client.from(table.name).upsert(payload);
        } else {
          await client
              .from(table.name)
              .upsert(payload, onConflict: table.upsertConflict);
        }
        local.execute(
          '''
          UPDATE ${table.name}
          SET sync_status = 'synced', last_synced_at = ?
          WHERE ${table.keyColumn} = ?
          ''',
          [syncTime, key],
        );
      }
    }
  }

  Future<void> _pullRemote(
    SupabaseClient client,
    LocalDatabase local,
    String userId,
  ) async {
    final syncTime = nowIso();
    for (final table in _tables) {
      final dynamic response = await client.from(table.name).select();
      final rows = (response as List).cast<Map<String, dynamic>>();
      for (final row in rows) {
        _applyRemoteRow(local, table, row, userId, syncTime);
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

    if (row['sync_deleted_at'] != null) {
      local.execute('DELETE FROM ${table.name} WHERE ${table.keyColumn} = ?', [
        key,
      ]);
      return true;
    }

    final existing = local.selectOne(
      'SELECT * FROM ${table.name} WHERE ${table.keyColumn} = ?',
      [key],
    );
    if (existing != null && existing['sync_status'] == 'pending') {
      final localTime = _parse(existing['client_modified_at']);
      final remoteTime = _parse(row['updated_at']);
      if (localTime != null &&
          remoteTime != null &&
          localTime.isAfter(remoteTime)) {
        return false;
      }
    }

    _upsertLocalRemoteRow(local, table.name, row, userId, syncTime);
    return true;
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

  DateTime? _parse(Object? value) =>
      value == null ? null : DateTime.tryParse(value.toString());
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

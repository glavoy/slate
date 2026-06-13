import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../local/local_database.dart';

/// Bidirectional sync between the local SQLite database and Supabase.
///
/// Design (see the sync rework plan):
///  * Writes are local-first. Repositories mark rows `pending` and call
///    [schedulePush], which coalesces a burst of edits into a single push.
///  * A full reconcile (push + one pull) runs on app launch, resume, and
///    connectivity regained — the moments a device is most likely to be a step
///    behind the other one. There is no constant short-interval polling.
///  * The pull cursor is a per-table high-water mark derived from the maximum
///    server `updated_at` actually seen, not the device's wall clock. Combined
///    with the server-side `set_updated_at` trigger this is immune to clock
///    skew between devices, which previously caused changes to never sync.
///  * Realtime is an acceleration path that only runs while the app is
///    foregrounded; [pause]/[resume] tear it down and bring it back.
class SyncService {
  SyncService._();

  static final instance = SyncService._();

  SupabaseClient? _client;
  LocalDatabase? _local;
  StreamSubscription<dynamic>? _connectivitySubscription;
  RealtimeChannel? _realtimeChannel;
  Timer? _periodicSyncTimer;
  Timer? _pushDebounce;
  final _changes = StreamController<void>.broadcast();

  bool _busy = false;
  bool _rerun = false;
  bool _rerunPull = false;
  DateTime? _syncStartedAt;

  /// Foreground-only safety net. Realtime + foreground/resync cover the common
  /// cases; this is just a backstop, so it can be infrequent.
  static const periodicSyncInterval = Duration(minutes: 5);
  static const syncTimeout = Duration(seconds: 25);
  static const realtimeReconnectTimeout = Duration(seconds: 5);
  static const pushDebounceDelay = Duration(seconds: 2);
  static const _pullPageSize = 1000;

  /// Re-pull this far behind the newest row we have seen. Cheap insurance against
  /// a row committed on another device mid-pagination; applies are idempotent so
  /// the small overlap is harmless.
  static const _hwmOverlap = Duration(seconds: 2);

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
    _SyncTable(
      'tracker_entries',
      'id',
      localConflict: 'metric_id, user_id, recorded_at',
    ),
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
    _startPeriodicTimer();
    _subscribeToRealtime(client);
    // Reconcile once on launch so the device catches up with the other one.
    unawaited(syncNow(force: true));
  }

  Stream<void> get changes => _changes.stream;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Call when the app returns to the foreground.
  Future<void> resume() async {
    final client = _client;
    if (client == null) return;
    _startPeriodicTimer();
    await _reconnectRealtime();
    await syncNow(force: true);
  }

  /// Call when the app is backgrounded. Flushes pending writes, then releases
  /// the realtime socket and the foreground timer so a backgrounded app holds no
  /// open connection.
  Future<void> pause() async {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = null;
    _pushDebounce?.cancel();
    // Best-effort flush of anything still pending before we go quiet.
    await _execute(pull: false);
    final client = _client;
    final channel = _realtimeChannel;
    _realtimeChannel = null;
    if (client != null && channel != null) {
      try {
        await client.removeChannel(channel).timeout(realtimeReconnectTimeout);
      } catch (error, stackTrace) {
        _logSyncError('realtime pause', error, stackTrace);
      }
    }
  }

  // Back-compat entry points used by the app lifecycle observer.
  Future<void> syncAfterResume() => resume();
  void syncSoonAfterResume() => unawaited(resume());

  // ── Public triggers ──────────────────────────────────────────────────────────

  /// Coalesced, push-only sync. Repositories call this after a local write so a
  /// burst of edits results in a single push pass and no read traffic.
  void schedulePush() {
    _pushDebounce?.cancel();
    _pushDebounce = Timer(pushDebounceDelay, () {
      unawaited(_execute(pull: false));
    });
  }

  /// Full reconcile: push pending local rows, then pull remote changes once.
  Future<void> syncNow({bool force = false}) async {
    if (_busy && force && _syncLooksStale()) {
      // An earlier sync is wedged past the timeout; let this one take over.
      _busy = false;
    }
    await _execute(pull: true);
  }

  /// Full reconcile, fire-and-forget.
  void syncSoon() => unawaited(syncNow());

  // ── Core runner ──────────────────────────────────────────────────────────────

  Future<void> _execute({required bool pull}) async {
    final client = _client;
    final local = _local;
    final user = client?.auth.currentUser;
    if (client == null || local == null || user == null) return;

    if (_busy) {
      _rerun = true;
      _rerunPull = _rerunPull || pull;
      return;
    }

    _busy = true;
    _syncStartedAt = DateTime.now();
    try {
      await _run(client, local, user.id, pull: pull).timeout(
        syncTimeout,
        onTimeout: () => _logSyncMessage('sync timed out'),
      );
    } catch (error, stackTrace) {
      // The app stays local-first; a failed attempt is retried on the next
      // write, resume, or connectivity change.
      _logSyncError('sync', error, stackTrace);
    } finally {
      _busy = false;
      _syncStartedAt = null;
      if (_rerun) {
        final nextPull = _rerunPull;
        _rerun = false;
        _rerunPull = false;
        unawaited(_execute(pull: nextPull));
      }
    }
  }

  Future<void> _run(
    SupabaseClient client,
    LocalDatabase local,
    String userId, {
    required bool pull,
  }) async {
    await _pushPending(client, local, userId);
    if (pull) {
      await _pullRemote(client, local, userId);
    }
    _changes.add(null);
  }

  bool _syncLooksStale() {
    final startedAt = _syncStartedAt;
    if (startedAt == null) return true;
    return DateTime.now().difference(startedAt) > syncTimeout;
  }

  void _startPeriodicTimer() {
    _periodicSyncTimer ??= Timer.periodic(
      periodicSyncInterval,
      (_) => syncSoon(),
    );
  }

  // ── Realtime ─────────────────────────────────────────────────────────────────

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
      // A realtime arrival is a good moment to flush any local pending writes.
      schedulePush();
    } catch (error, stackTrace) {
      // Realtime is only an acceleration path; fall back to a full reconcile.
      _logSyncError('realtime ${table.name}', error, stackTrace);
      syncSoon();
    }
  }

  // ── Push ─────────────────────────────────────────────────────────────────────

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
      // updated_at is stamped by the server trigger; we only set the tombstone.
      await client
          .from(table.name)
          .update({'sync_deleted_at': timestamp})
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

  // ── Pull ─────────────────────────────────────────────────────────────────────

  Future<void> _pullRemote(
    SupabaseClient client,
    LocalDatabase local,
    String userId,
  ) async {
    final syncTime = nowIso();
    for (final table in _tables) {
      final hwmKey = 'pull_hwm_${table.name}';
      final since = local.getMeta(hwmKey);
      DateTime? maxSeen;
      var from = 0;
      var completed = false;

      while (true) {
        try {
          dynamic query = client.from(table.name).select().eq(
            'user_id',
            userId,
          );
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
            final updatedAt = _parseTimestamp(row['updated_at']);
            if (updatedAt != null &&
                (maxSeen == null || updatedAt.isAfter(maxSeen))) {
              maxSeen = updatedAt;
            }
          }

          if (rows.length < _pullPageSize) {
            completed = true;
            break;
          }
          from += _pullPageSize;
        } catch (error, stackTrace) {
          // Continue pulling other tables even if one table is unavailable. Do
          // not advance the high-water mark for a table that failed to pull.
          _logSyncError('pull ${table.name}', error, stackTrace);
          break;
        }
      }

      if (completed) {
        final next = advanceHighWaterMark(since, maxSeen);
        if (next != null) local.setMeta(hwmKey, next);
      }
    }
  }

  /// New cursor = newest row seen, rewound by [_hwmOverlap], but never earlier
  /// than the previous cursor. Returns null when there is nothing to advance to.
  @visibleForTesting
  static String? advanceHighWaterMark(String? current, DateTime? maxSeen) {
    if (maxSeen == null) return null;
    final candidate = maxSeen.subtract(_hwmOverlap);
    final previous = _parseTimestamp(current);
    final next = (previous != null && previous.isAfter(candidate))
        ? previous
        : candidate;
    return next.toUtc().toIso8601String();
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
    if (existing != null && !_remoteShouldApply(existing, row)) {
      return false;
    }

    if (row['sync_deleted_at'] != null) {
      local.execute(
        'DELETE FROM ${table.name} WHERE ${table.keyColumn} = ? AND user_id = ?',
        [key, userId],
      );
      // Also remove a local row found by composite key with a different id.
      if (existing != null && existing[table.keyColumn] != key) {
        local.execute(
          'DELETE FROM ${table.name} WHERE ${table.keyColumn} = ? AND user_id = ?',
          [existing[table.keyColumn], userId],
        );
      }
      return true;
    }

    // If we found an existing row by composite key but with a different id,
    // delete it first so the upsert doesn't hit a UNIQUE constraint violation.
    if (existing != null && existing[table.keyColumn] != key) {
      local.execute(
        'DELETE FROM ${table.name} WHERE ${table.keyColumn} = ? AND user_id = ?',
        [existing[table.keyColumn], userId],
      );
    }

    _upsertLocalRemoteRow(local, table.name, row, userId, syncTime);
    return true;
  }

  /// Whether an incoming remote row should overwrite the existing local one.
  ///
  /// For a `pending` local row we compare against its `client_modified_at` (the
  /// unsynced edit time) so a fresh local edit is not lost. For a `synced` local
  /// row we compare against its stored server `updated_at`, so a stale or
  /// out-of-order remote echo can never roll the row back to older content.
  bool _remoteShouldApply(
    Map<String, Object?> existing,
    Map<String, dynamic> row,
  ) {
    final localTime = existing['sync_status'] == 'pending'
        ? existing['client_modified_at']
        : existing['updated_at'];
    return remoteWinsPendingLocal(
      localClientModifiedAt: localTime,
      remoteRow: row,
    );
  }

  Map<String, Object?>? _selectExistingLocal(
    LocalDatabase local,
    _SyncTable table,
    Map<String, dynamic> row,
  ) {
    // Always try the primary key first.
    final byKey = local.selectOne(
      'SELECT * FROM ${table.name} WHERE ${table.keyColumn} = ?',
      [row[table.keyColumn]],
    );
    if (byKey != null) return byKey;

    // For tables with a composite unique key, also look up by that key so we
    // can detect a local row with a different id but the same logical identity.
    if (table.localConflict == 'user_id, entry_date') {
      final userId = row['user_id'];
      final entryDate = row['entry_date'];
      if (userId != null && entryDate != null) {
        return local.selectOne(
          'SELECT * FROM ${table.name} WHERE user_id = ? AND entry_date = ?',
          [userId, entryDate],
        );
      }
    }
    if (table.localConflict == 'metric_id, user_id, recorded_at') {
      final metricId = row['metric_id'];
      final userId = row['user_id'];
      final recordedAt = row['recorded_at'];
      if (metricId != null && userId != null && recordedAt != null) {
        return local.selectOne(
          '''
          SELECT * FROM tracker_entries
          WHERE metric_id = ? AND user_id = ? AND recorded_at = ?
          ''',
          [metricId, userId, recordedAt],
        );
      }
    }
    return null;
  }

  Map<String, dynamic> _remotePayload(String table, Map<String, Object?> row) {
    // Local-only sync bookkeeping never leaves the device. updated_at is owned
    // by the server trigger, so we never send it either.
    final excluded = {
      'sync_status',
      'last_synced_at',
      'client_modified_at',
      'pending_delete',
      'updated_at',
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
    // INSERT OR REPLACE handles all UNIQUE/PK conflicts by deleting every
    // conflicting row before inserting the new one.  This is necessary for
    // tables like tracker_entries where a remote row can simultaneously
    // conflict on the PRIMARY KEY (same id, different recorded_at) AND on the
    // composite UNIQUE key (different id, same recorded_at).
    local.execute('''
      INSERT OR REPLACE INTO $table (${columns.join(', ')})
      VALUES ($placeholders)
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

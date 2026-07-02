import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../local/local_database.dart';
import 'sync_remote.dart';

/// Bidirectional sync between the local SQLite database and Supabase.
///
/// Design:
///  * Writes are local-first. Repositories mark rows `pending` and call
///    [schedulePush], which coalesces a burst of edits into a single push.
///  * The server is the single ordering authority. Every table carries an
///    integer `version` bumped by a server trigger on each UPDATE; clients
///    never send it. Each local row remembers the last server version it was
///    based on (`server_version`).
///  * Pushes are compare-and-swap: an UPDATE only applies if the server row
///    still has the expected version. A stale device can therefore never
///    silently overwrite a newer row — the mismatch surfaces as a conflict
///    that is resolved explicitly (see [_resolveConflict]).
///  * Conflicts pick a winner by `client_modified_at` (client clock vs client
///    clock — never client vs server). For notes the losing side is preserved
///    as a "conflicted copy" note, so a true concurrent edit never loses data.
///  * The pull cursor is a per-table high-water mark derived from the maximum
///    server `updated_at` actually seen. Only the server writes `updated_at`
///    (trigger), so the cursor is immune to device clock skew.
///  * A full reconcile (push + one pull) runs on app launch, resume, and
///    connectivity regained. Realtime is an acceleration path that only runs
///    while the app is foregrounded; [pause]/[resume] tear it down and bring
///    it back.
class SyncService {
  SyncService._();

  static final instance = SyncService._();

  /// Isolated engine instance for tests: no realtime, no connectivity
  /// listener, no timers. Drive it with [syncNow].
  @visibleForTesting
  SyncService.forTest({
    required SyncRemote remote,
    required LocalDatabase local,
    required String userId,
  }) : _remote = remote,
       _local = local,
       _testUserId = userId;

  SupabaseClient? _client;
  SyncRemote? _remote;
  LocalDatabase? _local;
  String? _testUserId;
  StreamSubscription<dynamic>? _connectivitySubscription;
  RealtimeChannel? _realtimeChannel;
  Timer? _periodicSyncTimer;
  Timer? _pushDebounce;
  final _changes = StreamController<void>.broadcast();
  static const _uuid = Uuid();

  bool _busy = false;
  bool _rerun = false;
  bool _rerunPull = false;

  /// Set when conflict resolution creates new local work (a conflicted copy or
  /// a local-wins row) so the same reconcile pass pushes it out.
  bool _followUpPush = false;
  DateTime? _syncStartedAt;

  /// Foreground-only safety net. Realtime + foreground/resync cover the common
  /// cases; this is just a backstop, so it can be infrequent.
  static const periodicSyncInterval = Duration(minutes: 5);
  static const syncTimeout = Duration(seconds: 25);
  static const realtimeReconnectTimeout = Duration(seconds: 5);
  static const pushDebounceDelay = Duration(seconds: 2);
  static const _pullPageSize = 1000;

  /// Re-pull this far behind the newest row we have seen. Cheap insurance
  /// against a row committed on another device mid-pagination; applies are
  /// idempotent so the small overlap is harmless.
  static const _hwmOverlap = Duration(seconds: 2);

  static const _tables = <_SyncTable>[
    _SyncTable('tasks', 'id'),
    _SyncTable('notes', 'id'),
    _SyncTable('journal_entries', 'id', localConflict: 'user_id, entry_date'),
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
    SyncRemote? remote,
  }) {
    _client = client;
    _remote = remote ?? SupabaseSyncRemote(client);
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

  String? get _userId => _testUserId ?? _client?.auth.currentUser?.id;

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
  /// the realtime socket and the foreground timer so a backgrounded app holds
  /// no open connection.
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
    final remote = _remote;
    final local = _local;
    final userId = _userId;
    if (remote == null || local == null || userId == null) return;

    if (_busy) {
      _rerun = true;
      _rerunPull = _rerunPull || pull;
      return;
    }

    _busy = true;
    _syncStartedAt = DateTime.now();
    try {
      await _run(remote, local, userId, pull: pull).timeout(
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
    SyncRemote remote,
    LocalDatabase local,
    String userId, {
    required bool pull,
  }) async {
    _followUpPush = false;
    await _pushPending(remote, local, userId);
    if (pull) {
      await _pullRemote(remote, local, userId);
    }
    if (_followUpPush) {
      // Conflict resolution produced new local work (conflicted copies,
      // local-wins rows). Push it in the same pass so both devices converge
      // without waiting for the next trigger. Bounded: one extra pass.
      _followUpPush = false;
      await _pushPending(remote, local, userId);
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
    final local = _local;
    final userId = _userId;
    if (local == null || userId == null) return;

    try {
      final syncTime = nowIso();
      if (payload.eventType == PostgresChangeEvent.delete) {
        // Physical deletes only happen via the legacy tombstone fallback. If a
        // pending local edit exists, leave it: the push path will discover the
        // missing server row and resolve it (edit wins for notes).
        final row = payload.oldRecord;
        if (row['user_id'] == null || row['user_id'] == userId) {
          final key = row[table.keyColumn];
          if (key != null) {
            final existing = _selectLocalByKey(local, table, key);
            if (existing != null && existing['sync_status'] != 'pending') {
              _deleteLocalRow(local, table, key, userId);
              _changes.add(null);
            }
          }
        }
      } else {
        final row = payload.newRecord;
        if (row['user_id'] == null || row['user_id'] == userId) {
          final changed = _applyRemoteRow(local, table, row, userId, syncTime);
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
    SyncRemote remote,
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
        if (row[table.keyColumn] == null) continue;
        try {
          await _pushRow(remote, local, table, row, userId, syncTime);
        } catch (error, stackTrace) {
          // Leave the row pending; a later sync attempt can retry it.
          _logSyncError('push ${table.name}', error, stackTrace);
        }
      }
    }
  }

  Future<void> _pushRow(
    SyncRemote remote,
    LocalDatabase local,
    _SyncTable table,
    Map<String, Object?> row,
    String userId,
    String syncTime, {
    bool retryOnConflict = true,
  }) async {
    final key = row[table.keyColumn]!;

    if (sqlToBool(row['pending_delete'])) {
      final timestamp = (row['client_modified_at'] ?? syncTime).toString();
      await remote.tombstone(table.name, table.keyColumn, key, timestamp);
      if (pushedSnapshotStillCurrent(
        pushedClientModifiedAt: row['client_modified_at'],
        currentRow: _selectLocalByKey(local, table, key),
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
      return;
    }

    final payload = _remotePayload(table.name, row);
    final baseVersion = (row['server_version'] as num?)?.toInt();

    RemoteRow? serverRow;
    RemoteRow? conflictingRow;
    if (baseVersion == null) {
      // Never seen on the server: plain insert. A unique violation means the
      // row already exists there (journal same-date created on two devices,
      // simple_list primary key, pre-migration rows).
      try {
        serverRow = await remote.insert(table.name, payload);
      } on RemoteUniqueViolation {
        conflictingRow = await _fetchServerCounterpart(remote, table, row);
      }
    } else {
      serverRow = await remote.casUpdate(
        table.name,
        table.keyColumn,
        key,
        baseVersion,
        payload,
      );
      if (serverRow == null) {
        conflictingRow = await remote.fetchWhere(table.name, {
          table.keyColumn: key,
        });
      }
    }

    if (serverRow != null) {
      _markPushed(local, table, row, serverRow, userId, syncTime);
      return;
    }

    final resolution = _resolveConflict(
      local,
      table,
      row,
      conflictingRow,
      userId,
      syncTime,
    );
    if (retryOnConflict && resolution == _Resolution.localWins) {
      final retryKey = conflictingRow?[table.keyColumn] ?? key;
      final fresh = _selectLocalByKey(local, table, retryKey);
      if (fresh != null &&
          fresh['sync_status'] == 'pending' &&
          !sqlToBool(fresh['pending_delete'])) {
        await _pushRow(
          remote,
          local,
          table,
          fresh,
          userId,
          syncTime,
          retryOnConflict: false,
        );
      }
    }
  }

  /// Locates the server row an insert collided with: by primary key first,
  /// then by the table's composite unique key (journal date, tracker entry).
  Future<RemoteRow?> _fetchServerCounterpart(
    SyncRemote remote,
    _SyncTable table,
    Map<String, Object?> row,
  ) async {
    final byKey = await remote.fetchWhere(table.name, {
      table.keyColumn: row[table.keyColumn],
    });
    if (byKey != null) return byKey;
    if (table.localConflict == 'user_id, entry_date') {
      return remote.fetchWhere(table.name, {
        'user_id': row['user_id'],
        'entry_date': row['entry_date'],
      });
    }
    if (table.localConflict == 'metric_id, user_id, recorded_at') {
      return remote.fetchWhere(table.name, {
        'metric_id': row['metric_id'],
        'user_id': row['user_id'],
        'recorded_at': row['recorded_at'],
      });
    }
    return null;
  }

  /// Records a successful push: the server's version/updated_at become the new
  /// baseline. Only flips the row to `synced` if it hasn't been edited again
  /// mid-push; a newer local edit stays pending but still adopts the baseline
  /// so its own push CASes against the row we just wrote.
  void _markPushed(
    LocalDatabase local,
    _SyncTable table,
    Map<String, Object?> pushedRow,
    RemoteRow serverRow,
    String userId,
    String syncTime,
  ) {
    final key = pushedRow[table.keyColumn];
    final version = (serverRow['version'] as num?)?.toInt() ?? 1;
    final updatedAt = (serverRow['updated_at'] ?? syncTime).toString();
    final current = _selectLocalByKey(local, table, key);
    if (pushedSnapshotStillCurrent(
      pushedClientModifiedAt: pushedRow['client_modified_at'],
      currentRow: current,
    )) {
      local.execute(
        '''
        UPDATE ${table.name}
        SET sync_status = 'synced',
            last_synced_at = ?,
            server_version = ?,
            updated_at = ?
        WHERE ${table.keyColumn} = ?
          AND user_id = ?
          AND sync_status = 'pending'
          AND client_modified_at = ?
        ''',
        [
          syncTime,
          version,
          updatedAt,
          key,
          userId,
          pushedRow['client_modified_at'],
        ],
      );
    } else if (current != null) {
      local.execute(
        '''
        UPDATE ${table.name}
        SET server_version = ?
        WHERE ${table.keyColumn} = ? AND user_id = ?
        ''',
        [version, key, userId],
      );
    }
  }

  // ── Conflict resolution ──────────────────────────────────────────────────────

  /// Resolves a detected conflict between a pending local row and the
  /// authoritative server row. Winner = newer `client_modified_at` (client
  /// clock vs client clock). For notes the loser is preserved as a
  /// "conflicted copy" note so no content is ever silently discarded.
  _Resolution _resolveConflict(
    LocalDatabase local,
    _SyncTable table,
    Map<String, Object?> localRow,
    RemoteRow? serverRow,
    String userId,
    String syncTime,
  ) {
    final key = localRow[table.keyColumn];
    // Bail if the local row moved on since this snapshot (e.g. the user is
    // typing); the next sync pass re-resolves against the fresh edit.
    final current = _selectLocalByKey(local, table, key);
    if (current == null ||
        current['sync_status'] != 'pending' ||
        sqlToBool(current['pending_delete']) ||
        current['client_modified_at'] != localRow['client_modified_at']) {
      return _Resolution.skipped;
    }

    final isNotes = table.name == 'notes';

    if (serverRow == null) {
      // The row vanished from the server (legacy physical delete).
      if (isNotes) {
        // Edit wins: clear the baseline so the retry re-inserts the note.
        local.execute(
          'UPDATE notes SET server_version = NULL WHERE id = ? AND user_id = ?',
          [key, userId],
        );
        _followUpPush = true;
        return _Resolution.localWins;
      }
      _deleteLocalRow(local, table, key, userId);
      return _Resolution.localDropped;
    }

    final serverVersion = (serverRow['version'] as num?)?.toInt() ?? 1;
    final serverKey = serverRow[table.keyColumn];

    if (serverRow['sync_deleted_at'] != null) {
      if (isNotes) {
        // Edit wins over a delete: adopt the tombstone's version as the
        // baseline; the retry CAS rewrites the row with sync_deleted_at = null,
        // resurrecting the note.
        local.execute(
          'UPDATE notes SET server_version = ? WHERE id = ? AND user_id = ?',
          [serverVersion, key, userId],
        );
        _followUpPush = true;
        return _Resolution.localWins;
      }
      _deleteLocalRow(local, table, key, userId);
      return _Resolution.localDropped;
    }

    final localTime = _parseTimestamp(localRow['client_modified_at']);
    final serverTime = _parseTimestamp(
      serverRow['client_modified_at'] ?? serverRow['updated_at'],
    );
    final localWins =
        localTime != null &&
        serverTime != null &&
        localTime.isAfter(serverTime);

    if (localWins) {
      if (isNotes && _noteContentDiffers(localRow, serverRow)) {
        // Our content is about to overwrite the server's; preserve theirs.
        _createConflictCopy(local, serverRow, userId);
      }
      if (serverKey != null && serverKey != key) {
        // Same logical row under a different id (composite-key collision, e.g.
        // a journal entry for the same date). Adopt the server identity so the
        // retry CAS targets the right row.
        local.execute(
          '''
          UPDATE ${table.name}
          SET ${table.keyColumn} = ?, server_version = ?
          WHERE ${table.keyColumn} = ? AND user_id = ?
          ''',
          [serverKey, serverVersion, key, userId],
        );
      } else {
        local.execute(
          '''
          UPDATE ${table.name}
          SET server_version = ?
          WHERE ${table.keyColumn} = ? AND user_id = ?
          ''',
          [serverVersion, key, userId],
        );
      }
      _followUpPush = true;
      return _Resolution.localWins;
    }

    // Server wins.
    if (isNotes && _noteContentDiffers(localRow, serverRow)) {
      // The server's content replaces ours; preserve ours.
      _createConflictCopy(local, localRow, userId);
      _followUpPush = true;
    }
    _applyServerRowLocally(local, table, serverRow, userId, syncTime);
    return _Resolution.serverApplied;
  }

  void _deleteLocalRow(
    LocalDatabase local,
    _SyncTable table,
    Object? key,
    String userId,
  ) {
    local.execute(
      'DELETE FROM ${table.name} WHERE ${table.keyColumn} = ? AND user_id = ?',
      [key, userId],
    );
  }

  bool _noteContentDiffers(Map<String, Object?> a, Map<String, Object?> b) {
    return (a['title'] ?? '').toString() != (b['title'] ?? '').toString() ||
        (a['content'] ?? '').toString() != (b['content'] ?? '').toString();
  }

  /// Preserves the losing side of a notes conflict as a new pending note. It
  /// syncs to the server like any other locally created note.
  void _createConflictCopy(
    LocalDatabase local,
    Map<String, Object?> source,
    String userId,
  ) {
    final now = nowIso();
    final stamp = _conflictStamp(DateTime.now());
    final baseTitle = (source['title'] ?? '').toString();
    final title = baseTitle.isEmpty
        ? '(conflicted copy $stamp)'
        : '$baseTitle (conflicted copy $stamp)';
    local.execute(
      '''
      INSERT INTO notes (
        id, user_id, title, content, pinned, deleted_at, created_at,
        updated_at, sync_status, client_modified_at, pending_delete,
        server_version
      ) VALUES (?, ?, ?, ?, 0, NULL, ?, ?, 'pending', ?, 0, NULL)
      ''',
      [
        _uuid.v4(),
        userId,
        title,
        (source['content'] ?? '').toString(),
        now,
        now,
        now,
      ],
    );
  }

  static String _conflictStamp(DateTime dt) {
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  // ── Pull ─────────────────────────────────────────────────────────────────────

  Future<void> _pullRemote(
    SyncRemote remote,
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
          final rows = await remote.pullSince(
            table.name,
            userId: userId,
            keyColumn: table.keyColumn,
            since: since,
            offset: from,
            limit: _pullPageSize,
          );
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

  /// Applies one remote row to the local database. Ordering decisions are made
  /// purely on server version numbers — never on clocks. Returns true when
  /// local data changed.
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
    final remoteVersion = (row['version'] as num?)?.toInt() ?? 1;

    if (existing == null) {
      if (row['sync_deleted_at'] != null) return false;
      _applyServerRowLocally(local, table, row, userId, syncTime);
      return true;
    }

    final localBaseline = (existing['server_version'] as num?)?.toInt();
    if (localBaseline != null && remoteVersion <= localBaseline) {
      // Our own echo or a stale, out-of-order arrival; nothing newer here.
      return false;
    }

    if (existing['sync_status'] != 'pending') {
      // Clean local row: the server is authoritative.
      if (row['sync_deleted_at'] != null) {
        _deleteLocalRow(local, table, key, userId);
        final existingKey = existing[table.keyColumn];
        if (existingKey != null && existingKey != key) {
          _deleteLocalRow(local, table, existingKey, userId);
        }
        return true;
      }
      _applyServerRowLocally(local, table, row, userId, syncTime);
      return true;
    }

    if (sqlToBool(existing['pending_delete'])) {
      // Local wants this row gone; the tombstone push proceeds regardless of
      // the newer remote version (delete is terminal).
      return false;
    }

    // Pending local edit vs a genuinely newer server row: a real conflict.
    final resolution = _resolveConflict(
      local,
      table,
      existing,
      row,
      userId,
      syncTime,
    );
    return resolution == _Resolution.serverApplied ||
        resolution == _Resolution.localDropped;
  }

  Map<String, Object?>? _selectLocalByKey(
    LocalDatabase local,
    _SyncTable table,
    Object? key,
  ) {
    return local.selectOne(
      'SELECT * FROM ${table.name} WHERE ${table.keyColumn} = ?',
      [key],
    );
  }

  Map<String, Object?>? _selectExistingLocal(
    LocalDatabase local,
    _SyncTable table,
    Map<String, dynamic> row,
  ) {
    // Always try the primary key first.
    final byKey = _selectLocalByKey(local, table, row[table.keyColumn]);
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
    // Local-only sync bookkeeping never leaves the device. version and
    // updated_at are owned by the server, so we never send them either.
    // sync_deleted_at IS sent even when null: an explicit null clears the
    // tombstone when an edit wins over a delete (note resurrection).
    const excluded = {
      'sync_status',
      'last_synced_at',
      'pending_delete',
      'updated_at',
      'server_version',
      'version',
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

  void _applyServerRowLocally(
    LocalDatabase local,
    _SyncTable table,
    Map<String, dynamic> row,
    String userId,
    String syncTime,
  ) {
    final normalized = _normalizeRemoteRow(table.name, row, userId, syncTime);
    final columns = normalized.keys.toList();
    final placeholders = List.filled(columns.length, '?').join(', ');
    // INSERT OR REPLACE handles all UNIQUE/PK conflicts by deleting every
    // conflicting row before inserting the new one.  This is necessary for
    // tables like tracker_entries where a remote row can simultaneously
    // conflict on the PRIMARY KEY (same id, different recorded_at) AND on the
    // composite UNIQUE key (different id, same recorded_at).
    local.execute('''
      INSERT OR REPLACE INTO ${table.name} (${columns.join(', ')})
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
      'client_modified_at': (row['client_modified_at'] ?? updatedAt).toString(),
      'pending_delete': 0,
      'server_version': (row['version'] as num?)?.toInt() ?? 1,
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
      'server_version',
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
      'server_version',
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
      'server_version',
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
      'server_version',
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
      'server_version',
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
      'server_version',
    },
    _ => const <String>{},
  };

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

enum _Resolution { localWins, serverApplied, localDropped, skipped }

class _SyncTable {
  const _SyncTable(this.name, this.keyColumn, {this.localConflict});

  final String name;
  final String keyColumn;
  final String? localConflict;
}

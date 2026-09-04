import 'package:flutter_test/flutter_test.dart';
import 'package:slate/local/local_database.dart';
import 'package:slate/sync/sync_remote.dart';
import 'package:slate/sync/sync_service.dart';

const _userId = 'user-1';

/// In-memory stand-in for the Supabase server: stamps `updated_at` with its
/// own monotonic clock, bumps `version` on every update, and enforces the
/// same unique constraints as the real schema.
class FakeSyncRemote implements SyncRemote {
  final Map<String, List<RemoteRow>> _tables = {};
  final Map<String, int> _pullCalls = {};
  int _clock = 0;

  /// Test hook invoked immediately before the second tasks pull is evaluated.
  /// It models a remote row changing between pages of one reconciliation.
  void Function()? onSecondTasksPull;

  static const _keyColumns = {
    'tasks': 'id',
    'notes': 'id',
    'simple_list': 'user_id',
    'tracker_metrics': 'id',
    'tracker_entries': 'id',
  };

  static const _compositeKeys = {
    'tracker_entries': ['metric_id', 'user_id', 'recorded_at'],
  };

  List<RemoteRow> rows(String table) => _tables.putIfAbsent(table, () => []);

  String _stamp() {
    _clock++;
    return DateTime.utc(
      2026,
      1,
      1,
    ).add(Duration(seconds: _clock)).toIso8601String();
  }

  void seedTask(String id) {
    rows('tasks').add({
      'id': id,
      'user_id': _userId,
      'title': 'Task $id',
      'due_date': '2026-06-01',
      'notes': null,
      'is_done': false,
      'recurrence': 'none',
      'due_time': null,
      'series_id': null,
      'created_at': _stamp(),
      'completed_at': null,
      'updated_at': _stamp(),
      'sync_deleted_at': null,
      'client_modified_at': _stamp(),
      'version': 1,
    });
  }

  void updateTaskRemotely(String id) {
    final row = rows('tasks').firstWhere((row) => row['id'] == id);
    row['title'] = 'Updated $id';
    row['version'] = (row['version'] as int) + 1;
    row['updated_at'] = _stamp();
  }

  @override
  Future<RemoteRow> insert(String table, RemoteRow payload) async {
    final keyColumn = _keyColumns[table]!;
    final key = payload[keyColumn];
    final existingByKey = rows(
      table,
    ).where((r) => r[keyColumn] == key).isNotEmpty;
    var existingByComposite = false;
    final composite = _compositeKeys[table];
    if (composite != null) {
      existingByComposite = rows(
        table,
      ).where((r) => composite.every((c) => r[c] == payload[c])).isNotEmpty;
    }
    if (existingByKey || existingByComposite) {
      throw RemoteUniqueViolation(table);
    }
    final stored = <String, dynamic>{
      ...payload,
      'version': 1,
      'updated_at': _stamp(),
    };
    rows(table).add(stored);
    return Map.of(stored);
  }

  @override
  Future<RemoteRow?> casUpdate(
    String table,
    String keyColumn,
    Object key,
    int expectedVersion,
    RemoteRow payload,
  ) async {
    for (final row in rows(table)) {
      if (row[keyColumn] == key) {
        if (row['version'] != expectedVersion) return null;
        row.addAll(payload);
        row['version'] = (row['version'] as int) + 1;
        row['updated_at'] = _stamp();
        return Map.of(row);
      }
    }
    return null;
  }

  @override
  Future<void> tombstone(
    String table,
    String keyColumn,
    Object key,
    String deletedAt,
  ) async {
    for (final row in rows(table)) {
      if (row[keyColumn] == key) {
        row['sync_deleted_at'] = deletedAt;
        row['version'] = (row['version'] as int) + 1;
        row['updated_at'] = _stamp();
        return;
      }
    }
  }

  @override
  Future<RemoteRow?> fetchWhere(
    String table,
    Map<String, Object?> filters,
  ) async {
    for (final row in rows(table)) {
      if (filters.entries.every((e) => row[e.key] == e.value)) {
        return Map.of(row);
      }
    }
    return null;
  }

  @override
  Future<List<RemoteRow>> pullSince(
    String table, {
    required String userId,
    required String keyColumn,
    required SyncPullCursor cursor,
    required int limit,
  }) async {
    final pullCall = (_pullCalls[table] ?? 0) + 1;
    _pullCalls[table] = pullCall;
    if (table == 'tasks' && pullCall == 2) {
      onSecondTasksPull?.call();
    }
    final matched =
        rows(table)
            .where((r) => r['user_id'] == userId)
            .where(
              (r) =>
                  cursor.since == null ||
                  (r['updated_at'] as String).compareTo(cursor.since!) >= 0,
            )
            .map(Map<String, dynamic>.of)
            .toList()
          ..sort((a, b) {
            final byTime = (a['updated_at'] as String).compareTo(
              b['updated_at'] as String,
            );
            if (byTime != 0) return byTime;
            return a[keyColumn].toString().compareTo(b[keyColumn].toString());
          });
    final page = cursor.hasPosition
        ? matched.where((row) {
            final time = row['updated_at'] as String;
            final key = row[keyColumn].toString();
            return time.compareTo(cursor.afterUpdatedAt!) > 0 ||
                (time == cursor.afterUpdatedAt &&
                    key.compareTo(cursor.afterKey.toString()) > 0);
          }).toList()
        : matched;
    return page.take(limit).toList();
  }
}

/// One simulated device: its own local SQLite database and sync engine,
/// sharing the fake server with the other device.
class TestDevice {
  TestDevice(FakeSyncRemote remote)
    : local = LocalDatabase.inMemory(),
      _remote = remote {
    service = SyncService.forTest(
      remote: remote,
      local: local,
      userId: _userId,
    );
  }

  final LocalDatabase local;
  final FakeSyncRemote _remote;
  late final SyncService service;

  Future<void> sync() => service.syncNow();

  // Mirrors NoteRepository.create / update / permanentlyDelete SQL.
  void createNote({
    required String id,
    required String title,
    required String content,
    required String clientTime,
  }) {
    local.execute(
      '''
      INSERT INTO notes (
        id, user_id, title, content, pinned, deleted_at, created_at,
        updated_at, sync_status, client_modified_at, pending_delete
      ) VALUES (?, ?, ?, ?, 0, NULL, ?, ?, 'pending', ?, 0)
      ''',
      [id, _userId, title, content, clientTime, clientTime, clientTime],
    );
  }

  void editNote(
    String id, {
    String? title,
    String? content,
    required String clientTime,
  }) {
    final fields = <String>[
      'updated_at = ?',
      'client_modified_at = ?',
      "sync_status = 'pending'",
    ];
    final values = <Object?>[clientTime, clientTime];
    if (title != null) {
      fields.add('title = ?');
      values.add(title);
    }
    if (content != null) {
      fields.add('content = ?');
      values.add(content);
    }
    values.add(id);
    local.execute('UPDATE notes SET ${fields.join(', ')} WHERE id = ?', values);
  }

  void deleteNote(String id, {required String clientTime}) {
    local.execute(
      '''
      UPDATE notes
      SET pending_delete = 1,
          sync_deleted_at = ?,
          updated_at = ?,
          client_modified_at = ?,
          sync_status = 'pending'
      WHERE id = ?
      ''',
      [clientTime, clientTime, clientTime, id],
    );
  }

  Map<String, Object?>? note(String id) =>
      local.selectOne('SELECT * FROM notes WHERE id = ?', [id]);

  List<Map<String, Object?>> allNotes() =>
      local.select('SELECT * FROM notes ORDER BY created_at, id');

  List<RemoteRow> serverNotes() => _remote.rows('notes');
}

String t(int seconds) =>
    DateTime.utc(2026, 6, 1).add(Duration(seconds: seconds)).toIso8601String();

void main() {
  late FakeSyncRemote remote;
  late TestDevice phone;
  late TestDevice laptop;

  setUp(() {
    remote = FakeSyncRemote();
    phone = TestDevice(remote);
    laptop = TestDevice(remote);
  });

  test('the reported bug: a stale pending edit cannot destroy a newer remote '
      'edit — it becomes a conflicted copy instead', () async {
    phone.createNote(
      id: 'n1',
      title: 'Groceries',
      content: 'v1',
      clientTime: t(0),
    );
    await phone.sync();
    await laptop.sync();
    expect(laptop.note('n1')!['content'], 'v1');

    // Laptop makes an edit but doesn't sync (e.g. backgrounded)…
    laptop.editNote('n1', content: 'laptop edit', clientTime: t(10));
    // …then the phone makes a NEWER edit and syncs it.
    phone.editNote('n1', content: 'phone edit', clientTime: t(20));
    await phone.sync();

    // Laptop resumes. Old engine: blind upsert wipes out the phone edit.
    await laptop.sync();

    // The phone's newer edit survives everywhere.
    expect(laptop.note('n1')!['content'], 'phone edit');
    expect(laptop.note('n1')!['sync_status'], 'synced');
    final serverN1 = remote.rows('notes').firstWhere((r) => r['id'] == 'n1');
    expect(serverN1['content'], 'phone edit');

    // The laptop's edit is preserved as a conflicted copy and synced out.
    final copies = laptop
        .allNotes()
        .where((n) => (n['title'] as String).contains('conflicted copy'))
        .toList();
    expect(copies, hasLength(1));
    expect(copies.first['content'], 'laptop edit');
    expect(remote.rows('notes'), hasLength(2));

    // The phone converges to the same two notes.
    await phone.sync();
    expect(phone.allNotes(), hasLength(2));
  });

  test('clock skew does not decide ordering: a later edit from a device with '
      'a slow clock still applies', () async {
    phone.createNote(id: 'n1', title: 'Note', content: 'v1', clientTime: t(0));
    await phone.sync();
    await laptop.sync();

    // Laptop's clock is 10 minutes fast; it edits and syncs first.
    laptop.editNote('n1', content: 'laptop (fast clock)', clientTime: t(600));
    await laptop.sync();
    await phone.sync();
    expect(phone.note('n1')!['content'], 'laptop (fast clock)');

    // The phone now edits sequentially — its wall clock reads EARLIER than the
    // laptop's previous edit. Versions, not clocks, order the writes.
    phone.editNote(
      'n1',
      content: 'phone (later, slow clock)',
      clientTime: t(60),
    );
    await phone.sync();
    await laptop.sync();

    expect(laptop.note('n1')!['content'], 'phone (later, slow clock)');
    // Sequential edits are not conflicts: no copies appear.
    expect(remote.rows('notes'), hasLength(1));
  });

  test('push echo: a synced row adopts the server version and timestamp, and '
      're-pulling is a no-op', () async {
    phone.createNote(id: 'n1', title: 'Note', content: 'v1', clientTime: t(0));
    await phone.sync();

    var row = phone.note('n1')!;
    expect(row['sync_status'], 'synced');
    expect(row['server_version'], 1);
    final serverRow = remote.rows('notes').single;
    expect(row['updated_at'], serverRow['updated_at']);

    await phone.sync();
    expect(phone.allNotes(), hasLength(1));

    phone.editNote('n1', content: 'v2', clientTime: t(5));
    await phone.sync();
    row = phone.note('n1')!;
    expect(row['server_version'], 2);
    expect(row['content'], 'v2');
    expect(remote.rows('notes'), hasLength(1));
  });

  test('a pending note edit wins over a remote permanent delete and '
      'resurrects the note', () async {
    phone.createNote(id: 'n1', title: 'Note', content: 'v1', clientTime: t(0));
    await phone.sync();
    await laptop.sync();

    laptop.editNote('n1', content: 'laptop edit', clientTime: t(10));
    phone.deleteNote('n1', clientTime: t(5));
    await phone.sync();
    expect(phone.note('n1'), isNull);
    expect(remote.rows('notes').single['sync_deleted_at'], isNotNull);

    await laptop.sync();
    final serverRow = remote.rows('notes').single;
    expect(serverRow['sync_deleted_at'], isNull);
    expect(serverRow['content'], 'laptop edit');
    expect(laptop.note('n1')!['sync_status'], 'synced');

    await phone.sync();
    expect(phone.note('n1')!['content'], 'laptop edit');
  });

  test(
    'identical concurrent content produces no conflicted-copy noise',
    () async {
      phone.createNote(
        id: 'n1',
        title: 'Note',
        content: 'v1',
        clientTime: t(0),
      );
      await phone.sync();
      await laptop.sync();

      laptop.editNote('n1', content: 'same words', clientTime: t(10));
      phone.editNote('n1', content: 'same words', clientTime: t(20));
      await phone.sync();
      await laptop.sync();
      await phone.sync();

      expect(remote.rows('notes'), hasLength(1));
      expect(phone.allNotes(), hasLength(1));
      expect(laptop.allNotes(), hasLength(1));
      expect(laptop.note('n1')!['content'], 'same words');
    },
  );

  test('keyset pagination does not skip a row when an earlier page row '
      'reorders during a multi-page pull', () async {
    // SyncService pulls 1,000 rows per page. Moving one of the first-page
    // rows to the end used to make an offset-based second page skip task 1000.
    for (var index = 0; index <= 1000; index++) {
      remote.seedTask('task-${index.toString().padLeft(4, '0')}');
    }
    remote.onSecondTasksPull = () => remote.updateTaskRemotely('task-0000');

    await phone.sync();

    final localTasks = phone.local.select('SELECT id FROM tasks');
    expect(localTasks, hasLength(1001));
    expect(
      localTasks.map((row) => row['id']),
      contains('task-1000'),
      reason: 'The row immediately after the old offset boundary is retained.',
    );
    expect(
      phone.local.selectOne('SELECT title FROM tasks WHERE id = ?', [
        'task-0000',
      ])!['title'],
      'Updated task-0000',
    );
  });
}

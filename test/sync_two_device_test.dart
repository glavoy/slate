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
  int _clock = 0;

  static const _keyColumns = {
    'tasks': 'id',
    'notes': 'id',
    'journal_entries': 'id',
    'simple_list': 'user_id',
    'tracker_metrics': 'id',
    'tracker_entries': 'id',
  };

  static const _compositeKeys = {
    'journal_entries': ['user_id', 'entry_date'],
    'tracker_entries': ['metric_id', 'user_id', 'recorded_at'],
  };

  List<RemoteRow> rows(String table) => _tables.putIfAbsent(table, () => []);

  String _stamp() {
    _clock++;
    return DateTime.utc(2026, 1, 1)
        .add(Duration(seconds: _clock))
        .toIso8601String();
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
    String? since,
    required int offset,
    required int limit,
  }) async {
    final matched =
        rows(table)
            .where((r) => r['user_id'] == userId)
            .where(
              (r) =>
                  since == null ||
                  (r['updated_at'] as String).compareTo(since) >= 0,
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
    if (offset >= matched.length) return [];
    return matched.sublist(
      offset,
      offset + limit > matched.length ? matched.length : offset + limit,
    );
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

  void createJournalEntry({
    required String id,
    required String entryDate,
    required String content,
    required String clientTime,
  }) {
    local.execute(
      '''
      INSERT INTO journal_entries (
        id, user_id, entry_date, content, created_at, updated_at,
        sync_status, client_modified_at, pending_delete
      ) VALUES (?, ?, ?, ?, ?, ?, 'pending', ?, 0)
      ''',
      [id, _userId, entryDate, content, clientTime, clientTime, clientTime],
    );
  }

  Map<String, Object?>? note(String id) =>
      local.selectOne('SELECT * FROM notes WHERE id = ?', [id]);

  List<Map<String, Object?>> allNotes() =>
      local.select('SELECT * FROM notes ORDER BY created_at, id');

  List<Map<String, Object?>> journalEntries() =>
      local.select('SELECT * FROM journal_entries');

  List<RemoteRow> serverNotes() => _remote.rows('notes');
}

String t(int seconds) => DateTime.utc(
  2026,
  6,
  1,
).add(Duration(seconds: seconds)).toIso8601String();

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
    final serverN1 = remote
        .rows('notes')
        .firstWhere((r) => r['id'] == 'n1');
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
    phone.editNote('n1', content: 'phone (later, slow clock)', clientTime: t(60));
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

  test('journal entries created for the same day on both devices merge into '
      'one row by last-writer-wins', () async {
    phone.createJournalEntry(
      id: 'j-phone',
      entryDate: '2026-06-01',
      content: 'phone words',
      clientTime: t(0),
    );
    laptop.createJournalEntry(
      id: 'j-laptop',
      entryDate: '2026-06-01',
      content: 'laptop words',
      clientTime: t(10),
    );
    await phone.sync();
    await laptop.sync();
    await phone.sync();

    // One logical entry everywhere, under the first-created id, holding the
    // newer content.
    expect(remote.rows('journal_entries'), hasLength(1));
    final serverRow = remote.rows('journal_entries').single;
    expect(serverRow['id'], 'j-phone');
    expect(serverRow['content'], 'laptop words');
    expect(laptop.journalEntries().single['id'], 'j-phone');
    expect(phone.journalEntries().single['content'], 'laptop words');
  });

  test('identical concurrent content produces no conflicted-copy noise', () async {
    phone.createNote(id: 'n1', title: 'Note', content: 'v1', clientTime: t(0));
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
  });
}

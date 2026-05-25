import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

class LocalDatabase {
  LocalDatabase._();

  static final instance = LocalDatabase._();

  Database? _db;

  Database get db {
    final database = _db;
    if (database == null) {
      throw StateError('LocalDatabase.open() must be called before use.');
    }
    return database;
  }

  Future<void> open() async {
    if (_db != null) return;
    final dir = await getApplicationSupportDirectory();
    await Directory(dir.path).create(recursive: true);
    _db = sqlite3.open(p.join(dir.path, 'slate.sqlite'));
    db.execute('PRAGMA foreign_keys = ON;');
    db.execute('PRAGMA journal_mode = WAL;');
    _createSchema();
  }

  void _createSchema() {
    db.execute('''
      CREATE TABLE IF NOT EXISTS sync_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS tasks (
        id TEXT PRIMARY KEY,
        user_id TEXT,
        title TEXT NOT NULL,
        due_date TEXT NOT NULL,
        notes TEXT,
        is_done INTEGER NOT NULL DEFAULT 0,
        recurrence TEXT NOT NULL DEFAULT 'none',
        due_time TEXT,
        series_id TEXT,
        created_at TEXT NOT NULL,
        completed_at TEXT,
        updated_at TEXT NOT NULL,
        sync_deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'synced',
        last_synced_at TEXT,
        client_modified_at TEXT NOT NULL,
        pending_delete INTEGER NOT NULL DEFAULT 0
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS notes (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        title TEXT NOT NULL DEFAULT '',
        content TEXT NOT NULL DEFAULT '',
        pinned INTEGER NOT NULL DEFAULT 0,
        deleted_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'synced',
        last_synced_at TEXT,
        client_modified_at TEXT NOT NULL,
        pending_delete INTEGER NOT NULL DEFAULT 0
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS journal_entries (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        entry_date TEXT NOT NULL,
        content TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'synced',
        last_synced_at TEXT,
        client_modified_at TEXT NOT NULL,
        pending_delete INTEGER NOT NULL DEFAULT 0,
        UNIQUE(user_id, entry_date)
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS simple_list (
        user_id TEXT PRIMARY KEY,
        content TEXT NOT NULL DEFAULT '',
        updated_at TEXT NOT NULL,
        sync_deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'synced',
        last_synced_at TEXT,
        client_modified_at TEXT NOT NULL,
        pending_delete INTEGER NOT NULL DEFAULT 0
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS tracker_metrics (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        name TEXT NOT NULL,
        unit TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'synced',
        last_synced_at TEXT,
        client_modified_at TEXT NOT NULL,
        pending_delete INTEGER NOT NULL DEFAULT 0
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS tracker_entries (
        id TEXT PRIMARY KEY,
        metric_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        value REAL NOT NULL,
        recorded_at TEXT NOT NULL,
        note TEXT,
        updated_at TEXT NOT NULL,
        sync_deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'synced',
        last_synced_at TEXT,
        client_modified_at TEXT NOT NULL,
        pending_delete INTEGER NOT NULL DEFAULT 0,
        UNIQUE(metric_id, user_id, recorded_at)
      );
    ''');

    _migrateSchema();
  }

  void _migrateSchema() {
    final version =
        db.select('PRAGMA user_version').first['user_version'] as int;
    if (version < 1) _migrateToV1();
    if (version < 2) _migrateToV2();
  }

  void _migrateToV2() {
    // Fix tracker_entries that were stored as "local-midnight UTC" rather than
    // true UTC midnight.  This happens when the device is in a UTC+ timezone:
    // DateTime(year, month, day).toUtc() produces the previous UTC day.
    //
    // Strategy: for every entry whose time component is already midnight in
    // the device's current timezone (i.e. it was a date-only entry), advance
    // or rewind it to the UTC midnight of that local date.  Entries with an
    // explicit time and UTC-midnight Supabase entries are left untouched.
    final offsetSeconds = DateTime.now().timeZoneOffset.inSeconds;
    if (offsetSeconds == 0) {
      db.execute('PRAGMA user_version = 2;');
      return;
    }
    final sign = offsetSeconds >= 0 ? '+' : '';
    final now = nowIso();
    db.execute('BEGIN IMMEDIATE;');
    try {
      // Migrate local-midnight entries to true UTC midnight.
      // OR IGNORE skips rows where a UTC midnight entry already exists.
      db.execute('''
        UPDATE OR IGNORE tracker_entries
        SET recorded_at     = strftime('%Y-%m-%dT00:00:00.000Z',
                                datetime(recorded_at,
                                         '$sign$offsetSeconds seconds')),
            sync_status     = 'pending',
            updated_at      = ?,
            client_modified_at = ?
        WHERE time(recorded_at) != '00:00:00'
          AND time(datetime(recorded_at,
                            '$sign$offsetSeconds seconds')) = '00:00:00'
      ''', [now, now]);
      // Delete any remaining local-midnight entries that couldn't be migrated
      // because a UTC midnight entry already existed for that (metric_id, user_id, date).
      db.execute('''
        DELETE FROM tracker_entries
        WHERE time(recorded_at) != '00:00:00'
          AND time(datetime(recorded_at,
                            '$sign$offsetSeconds seconds')) = '00:00:00'
      ''');
      db.execute('PRAGMA user_version = 2;');
      db.execute('COMMIT;');
    } catch (_) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }

  void _migrateToV1() {
    // Add UNIQUE(metric_id, user_id, recorded_at) to tracker_entries.
    // SQLite can't ADD CONSTRAINT, so recreate the table.
    db.execute('BEGIN IMMEDIATE;');
    try {
      db.execute('''
        CREATE TABLE tracker_entries_new (
          id TEXT PRIMARY KEY,
          metric_id TEXT NOT NULL,
          user_id TEXT NOT NULL,
          value REAL NOT NULL,
          recorded_at TEXT NOT NULL,
          note TEXT,
          updated_at TEXT NOT NULL,
          sync_deleted_at TEXT,
          sync_status TEXT NOT NULL DEFAULT 'synced',
          last_synced_at TEXT,
          client_modified_at TEXT NOT NULL,
          pending_delete INTEGER NOT NULL DEFAULT 0,
          UNIQUE(metric_id, user_id, recorded_at)
        );
      ''');
      // For each (metric_id, user_id, recorded_at) group keep one row:
      // pending beats synced; within the same status, latest updated_at wins.
      db.execute('''
        INSERT OR IGNORE INTO tracker_entries_new
        SELECT * FROM tracker_entries t1
        WHERE t1.rowid = (
          SELECT t2.rowid
          FROM tracker_entries t2
          WHERE t2.metric_id  = t1.metric_id
            AND t2.user_id    = t1.user_id
            AND t2.recorded_at = t1.recorded_at
          ORDER BY
            CASE WHEN t2.sync_status = 'pending' THEN 0 ELSE 1 END ASC,
            t2.updated_at DESC
          LIMIT 1
        );
      ''');
      db.execute('DROP TABLE tracker_entries;');
      db.execute('ALTER TABLE tracker_entries_new RENAME TO tracker_entries;');
      db.execute('PRAGMA user_version = 1;');
      db.execute('COMMIT;');
    } catch (_) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }

  List<Map<String, Object?>> select(
    String sql, [
    List<Object?> parameters = const [],
  ]) {
    final result = db.select(sql, parameters);
    return result.map((row) => Map<String, Object?>.from(row)).toList();
  }

  Map<String, Object?>? selectOne(
    String sql, [
    List<Object?> parameters = const [],
  ]) {
    final rows = select(sql, parameters);
    return rows.isEmpty ? null : rows.first;
  }

  void execute(String sql, [List<Object?> parameters = const []]) {
    db.execute(sql, parameters);
  }

  T transaction<T>(T Function() action) {
    db.execute('BEGIN IMMEDIATE;');
    try {
      final result = action();
      db.execute('COMMIT;');
      return result;
    } catch (_) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }

  String? getMeta(String key) {
    final row = selectOne('SELECT value FROM sync_meta WHERE key = ?', [key]);
    return row?['value'] as String?;
  }

  void setMeta(String key, String value) {
    execute(
      '''
      INSERT INTO sync_meta (key, value)
      VALUES (?, ?)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value
      ''',
      [key, value],
    );
  }

  void deleteMeta(String key) {
    execute('DELETE FROM sync_meta WHERE key = ?', [key]);
  }
}

String nowIso() => DateTime.now().toUtc().toIso8601String();

int boolToSql(bool value) => value ? 1 : 0;

bool sqlToBool(Object? value) => value == 1 || value == true;

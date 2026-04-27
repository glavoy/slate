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
        pending_delete INTEGER NOT NULL DEFAULT 0
      );
    ''');
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
}

String nowIso() => DateTime.now().toUtc().toIso8601String();

int boolToSql(bool value) => value ? 1 : 0;

bool sqlToBool(Object? value) => value == 1 || value == true;

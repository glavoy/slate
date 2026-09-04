import 'package:flutter_test/flutter_test.dart';
import 'package:slate/local/local_database.dart';

void main() {
  test('clearCachedData removes every local row and sync cursor', () {
    final local = LocalDatabase.inMemory();
    addTearDown(local.db.dispose);
    const timestamp = '2026-09-04T00:00:00.000Z';

    local.execute(
      '''
      INSERT INTO tasks (
        id, user_id, title, due_date, created_at, updated_at,
        client_modified_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        'task-1',
        'user-1',
        'Private task',
        '2026-09-04',
        timestamp,
        timestamp,
        timestamp,
      ],
    );
    local.execute(
      '''
      INSERT INTO notes (
        id, user_id, title, content, created_at, updated_at,
        client_modified_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        'note-1',
        'user-1',
        'Private note',
        'content',
        timestamp,
        timestamp,
        timestamp,
      ],
    );
    local.execute(
      '''
      INSERT INTO simple_list (user_id, content, updated_at, client_modified_at)
      VALUES (?, ?, ?, ?)
      ''',
      ['user-1', 'Private list', timestamp, timestamp],
    );
    local.execute(
      '''
      INSERT INTO tracker_metrics (
        id, user_id, name, created_at, updated_at, client_modified_at
      ) VALUES (?, ?, ?, ?, ?, ?)
      ''',
      ['metric-1', 'user-1', 'Private metric', timestamp, timestamp, timestamp],
    );
    local.execute(
      '''
      INSERT INTO tracker_entries (
        id, metric_id, user_id, value, recorded_at, updated_at,
        client_modified_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
      ''',
      ['entry-1', 'metric-1', 'user-1', 1.0, timestamp, timestamp, timestamp],
    );
    local.setMeta('pull_hwm_tasks', timestamp);

    local.clearCachedData();

    for (final table in const [
      'tasks',
      'notes',
      'simple_list',
      'tracker_metrics',
      'tracker_entries',
    ]) {
      expect(local.select('SELECT * FROM $table'), isEmpty);
    }
    expect(local.select('SELECT * FROM sync_meta'), isEmpty);
  });
}

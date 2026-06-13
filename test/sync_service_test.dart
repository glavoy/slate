import 'package:flutter_test/flutter_test.dart';
import 'package:slate/sync/sync_service.dart';

void main() {
  group('SyncService remoteWinsPendingLocal', () {
    test('keeps a newer pending local edit over an older remote row', () {
      final wins = SyncService.remoteWinsPendingLocal(
        localClientModifiedAt: '2026-05-10T12:00:00.000Z',
        remoteRow: {'updated_at': '2026-05-10T11:59:00.000Z'},
      );

      expect(wins, isFalse);
    });

    test('applies a newer remote row over an older pending local edit', () {
      final wins = SyncService.remoteWinsPendingLocal(
        localClientModifiedAt: '2026-05-10T12:00:00.000Z',
        remoteRow: {'updated_at': '2026-05-10T12:01:00.000Z'},
      );

      expect(wins, isTrue);
    });

    test('uses remote tombstone time when comparing deletes', () {
      final wins = SyncService.remoteWinsPendingLocal(
        localClientModifiedAt: '2026-05-10T12:00:00.000Z',
        remoteRow: {
          'updated_at': '2026-05-10T11:00:00.000Z',
          'sync_deleted_at': '2026-05-10T12:02:00.000Z',
        },
      );

      expect(wins, isTrue);
    });
  });

  group('SyncService remoteWinsPendingLocal (synced rows)', () {
    // A synced local row compares against its stored server updated_at. A stale
    // or out-of-order remote echo must not roll the row back to older content.
    test('rejects a stale remote echo older than the local synced row', () {
      final wins = SyncService.remoteWinsPendingLocal(
        localClientModifiedAt: '2026-05-10T12:00:05.000Z',
        remoteRow: {'updated_at': '2026-05-10T12:00:00.000Z'},
      );

      expect(wins, isFalse);
    });

    test('applies a genuinely newer remote row to a synced local row', () {
      final wins = SyncService.remoteWinsPendingLocal(
        localClientModifiedAt: '2026-05-10T12:00:00.000Z',
        remoteRow: {'updated_at': '2026-05-10T12:00:05.000Z'},
      );

      expect(wins, isTrue);
    });
  });

  group('SyncService advanceHighWaterMark', () {
    DateTime parse(String s) => DateTime.parse(s);

    test('returns null when nothing was seen', () {
      expect(
        SyncService.advanceHighWaterMark('2026-05-10T12:00:00.000Z', null),
        isNull,
      );
    });

    test('advances to newest-seen rewound by the overlap window', () {
      final next = SyncService.advanceHighWaterMark(
        null,
        parse('2026-05-10T12:00:10.000Z'),
      );

      // 10s seen minus the 2s overlap.
      expect(parse(next!), parse('2026-05-10T12:00:08.000Z'));
    });

    test('never moves the cursor backwards', () {
      // Newest seen is only 1s past the previous cursor, so candidate (−2s)
      // would regress; the previous cursor must be retained.
      final next = SyncService.advanceHighWaterMark(
        '2026-05-10T12:00:00.000Z',
        parse('2026-05-10T12:00:01.000Z'),
      );

      expect(parse(next!), parse('2026-05-10T12:00:00.000Z'));
    });
  });

  group('SyncService pushedSnapshotStillCurrent', () {
    test('keeps a newer local edit pending after an older snapshot pushed', () {
      final current = {
        'sync_status': 'pending',
        'client_modified_at': '2026-05-10T12:00:02.000Z',
      };

      final stillCurrent = SyncService.pushedSnapshotStillCurrent(
        pushedClientModifiedAt: '2026-05-10T12:00:00.000Z',
        currentRow: current,
      );

      expect(stillCurrent, isFalse);
    });

    test('allows sync completion when the pushed snapshot is unchanged', () {
      final current = {
        'sync_status': 'pending',
        'client_modified_at': '2026-05-10T12:00:00.000Z',
      };

      final stillCurrent = SyncService.pushedSnapshotStillCurrent(
        pushedClientModifiedAt: '2026-05-10T12:00:00.000Z',
        currentRow: current,
      );

      expect(stillCurrent, isTrue);
    });
  });
}

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

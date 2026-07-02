import 'package:flutter_test/flutter_test.dart';
import 'package:slate/sync/sync_service.dart';

void main() {
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

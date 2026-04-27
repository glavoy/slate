import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/tracker_metric.dart';
import '../models/tracker_entry.dart';
import '../repositories/tracker_repository.dart';
import '../sync/sync_service.dart';
import 'supabase_provider.dart';

part 'tracker_providers.g.dart';

@riverpod
class TrackerMetrics extends _$TrackerMetrics {
  TrackerRepository _repo() =>
      TrackerRepository(ref.read(supabaseClientProvider));

  @override
  Future<List<TrackerMetric>> build() async {
    ref.watch(supabaseClientProvider);
    final syncSubscription = SyncService.instance.changes.listen(
      (_) => ref.invalidateSelf(),
    );
    ref.onDispose(syncSubscription.cancel);

    return _repo().fetchMetrics();
  }

  Future<TrackerMetric> create({required String name, String? unit}) async {
    final m = await _repo().createMetric(name: name, unit: unit);
    ref.invalidateSelf();
    return m;
  }

  Future<void> delete(String id) async {
    await _repo().deleteMetric(id);
    ref.invalidateSelf();
  }
}

@riverpod
class TrackerEntries extends _$TrackerEntries {
  TrackerRepository _repo() =>
      TrackerRepository(ref.read(supabaseClientProvider));

  @override
  Future<List<TrackerEntry>> build(String metricId) async {
    ref.watch(supabaseClientProvider);
    final syncSubscription = SyncService.instance.changes.listen(
      (_) => ref.invalidateSelf(),
    );
    ref.onDispose(syncSubscription.cancel);

    return _repo().fetchEntries(metricId);
  }

  Future<void> add({
    required double value,
    String? note,
    DateTime? recordedAt,
  }) async {
    await _repo().addEntry(
      metricId: metricId,
      value: value,
      note: note,
      recordedAt: recordedAt,
    );
    ref.invalidateSelf();
  }

  Future<void> delete(String id) async {
    await _repo().deleteEntry(id);
    ref.invalidateSelf();
  }
}

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/journal_entry.dart';
import '../repositories/journal_repository.dart';
import '../sync/sync_service.dart';
import 'supabase_provider.dart';

part 'journal_providers.g.dart';

@riverpod
class JournalEntries extends _$JournalEntries {
  JournalRepository _repo() =>
      JournalRepository(ref.read(supabaseClientProvider));

  @override
  Future<List<JournalEntry>> build() async {
    ref.watch(supabaseClientProvider);
    final syncSubscription = SyncService.instance.changes.listen(
      (_) => ref.invalidateSelf(),
    );
    ref.onDispose(syncSubscription.cancel);

    return _repo().fetchAll();
  }

  Future<void> save(DateTime date, String content) async {
    await _repo().upsertForDate(date, content);
    ref.invalidateSelf();
  }

  Future<void> delete(String id) async {
    await _repo().delete(id);
    ref.invalidateSelf();
  }
}

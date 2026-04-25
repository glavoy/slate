import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/journal_entry.dart';
import '../repositories/journal_repository.dart';
import 'supabase_provider.dart';

part 'journal_providers.g.dart';

@riverpod
class JournalEntries extends _$JournalEntries {
  JournalRepository _repo() =>
      JournalRepository(ref.read(supabaseClientProvider));

  @override
  Future<List<JournalEntry>> build() async {
    final client = ref.watch(supabaseClientProvider);

    final channel = client
        .channel('public:journal_entries')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'journal_entries',
          callback: (_) {
            ref.invalidateSelf();
          },
        )
        .subscribe();

    ref.onDispose(channel.unsubscribe);

    return _repo().fetchAll();
  }

  Future<void> save(DateTime date, String content) async {
    await _repo().upsertForDate(date, content);
  }

  Future<void> delete(String id) async {
    await _repo().delete(id);
    ref.invalidateSelf();
  }
}

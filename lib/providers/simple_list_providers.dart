import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/simple_list.dart';
import '../repositories/simple_list_repository.dart';
import 'supabase_provider.dart';

part 'simple_list_providers.g.dart';

@riverpod
class SimpleListNotifier extends _$SimpleListNotifier {
  SimpleListRepository _repo() =>
      SimpleListRepository(ref.read(supabaseClientProvider));

  @override
  Future<SimpleList> build() async {
    final client = ref.watch(supabaseClientProvider);

    final channel = client
        .channel('public:simple_list')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'simple_list',
          callback: (payload) {
            if (payload.eventType == PostgresChangeEvent.delete) return;
            final row = payload.newRecord;
            if (row.isEmpty) return;
            try {
              state = AsyncValue.data(SimpleList.fromJson(row));
            } catch (_) {
              // ignore malformed payloads
            }
          },
        )
        .subscribe();

    ref.onDispose(channel.unsubscribe);

    return _repo().fetch();
  }

  Future<void> save(String content) async {
    await _repo().save(content);
  }
}

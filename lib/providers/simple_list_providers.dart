import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/simple_list.dart';
import '../repositories/simple_list_repository.dart';
import '../sync/sync_service.dart';
import 'supabase_provider.dart';

part 'simple_list_providers.g.dart';

@riverpod
class SimpleListNotifier extends _$SimpleListNotifier {
  SimpleListRepository _repo() =>
      SimpleListRepository(ref.read(supabaseClientProvider));

  @override
  Future<SimpleList> build() async {
    ref.watch(supabaseClientProvider);
    final syncSubscription = SyncService.instance.changes.listen(
      (_) => ref.invalidateSelf(),
    );
    ref.onDispose(syncSubscription.cancel);

    return _repo().fetch();
  }

  Future<void> save(String content) async {
    await _repo().save(content);
  }
}

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/note.dart';
import '../repositories/note_repository.dart';
import '../sync/sync_service.dart';
import 'supabase_provider.dart';

part 'note_providers.g.dart';

@riverpod
class NoteList extends _$NoteList {
  NoteRepository _repo() => NoteRepository(ref.read(supabaseClientProvider));

  @override
  Future<List<Note>> build() async {
    ref.watch(supabaseClientProvider);
    final syncSubscription = SyncService.instance.changes.listen(
      (_) => ref.invalidateSelf(),
    );
    ref.onDispose(syncSubscription.cancel);
    return _repo().fetchAll();
  }

  Future<Note> create() async {
    final note = await _repo().create();
    ref.invalidateSelf();
    return note;
  }

  Future<void> edit(String id, {String? title, String? content}) async {
    await _repo().update(id, title: title, content: content);
    ref.invalidateSelf();
  }

  Future<void> pin(String id, {required bool value}) async {
    await _repo().setPin(id, pinned: value);
    ref.invalidateSelf();
  }

  // Soft-delete: sets deleted_at rather than removing the row.
  Future<void> delete(String id) async {
    await _repo().softDelete(id);
    ref.invalidateSelf();
    ref.invalidate(deletedNoteListProvider);
  }
}

@riverpod
class DeletedNoteList extends _$DeletedNoteList {
  NoteRepository _repo() => NoteRepository(ref.read(supabaseClientProvider));

  @override
  Future<List<Note>> build() async {
    ref.watch(supabaseClientProvider);
    final syncSubscription = SyncService.instance.changes.listen(
      (_) => ref.invalidateSelf(),
    );
    ref.onDispose(syncSubscription.cancel);
    return _repo().fetchDeleted();
  }

  Future<void> restore(String id) async {
    await _repo().restore(id);
    ref.invalidateSelf();
    ref.invalidate(noteListProvider);
  }

  Future<void> permanentlyDelete(String id) async {
    await _repo().permanentlyDelete(id);
    ref.invalidateSelf();
  }
}

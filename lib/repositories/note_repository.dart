import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/note.dart';

class NoteRepository {
  NoteRepository(this._client);
  final SupabaseClient _client;

  Future<List<Note>> fetchAll() async {
    final rows = await _client
        .from('notes')
        .select()
        .filter('deleted_at', 'is', null)
        .order('pinned', ascending: false)
        .order('updated_at', ascending: false);
    return rows.map<Note>((r) => Note.fromJson(r)).toList();
  }

  Future<List<Note>> fetchDeleted() async {
    final rows = await _client
        .from('notes')
        .select()
        .not('deleted_at', 'is', null)
        .order('deleted_at', ascending: false);
    return rows.map<Note>((r) => Note.fromJson(r)).toList();
  }

  Future<Note> create({String title = '', String content = ''}) async {
    final inserted = await _client
        .from('notes')
        .insert({'title': title, 'content': content})
        .select()
        .single();
    return Note.fromJson(inserted);
  }

  Future<void> update(String id, {String? title, String? content}) async {
    final patch = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (title != null) patch['title'] = title;
    if (content != null) patch['content'] = content;
    await _client.from('notes').update(patch).eq('id', id);
  }

  Future<void> setPin(String id, {required bool pinned}) async {
    await _client.from('notes').update({'pinned': pinned}).eq('id', id);
  }

  Future<void> softDelete(String id) async {
    await _client.from('notes').update({
      'deleted_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
  }

  Future<void> restore(String id) async {
    await _client.from('notes').update({'deleted_at': null}).eq('id', id);
  }

  Future<void> permanentlyDelete(String id) async {
    await _client.from('notes').delete().eq('id', id);
  }
}

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/journal_entry.dart';

class JournalRepository {
  JournalRepository(this._client);
  final SupabaseClient _client;

  Future<List<JournalEntry>> fetchAll({int? limit}) async {
    var query =
        _client.from('journal_entries').select().order('entry_date', ascending: false);
    final rows = limit != null ? await query.limit(limit) : await query;
    return rows.map<JournalEntry>((r) => JournalEntry.fromJson(r)).toList();
  }

  Future<void> upsertForDate(DateTime date, String content) async {
    final userId = _client.auth.currentUser!.id;
    final dateStr = date.toIso8601String().substring(0, 10);
    await _client.from('journal_entries').upsert({
      'user_id': userId,
      'entry_date': dateStr,
      'content': content,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'user_id,entry_date');
  }

  Future<void> delete(String id) async {
    await _client.from('journal_entries').delete().eq('id', id);
  }
}

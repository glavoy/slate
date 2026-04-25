import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/simple_list.dart';

class SimpleListRepository {
  SimpleListRepository(this._client);
  final SupabaseClient _client;

  Future<SimpleList> fetch() async {
    final userId = _client.auth.currentUser!.id;
    final row = await _client
        .from('simple_list')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    if (row != null) {
      return SimpleList.fromJson(row);
    }
    final inserted = await _client
        .from('simple_list')
        .insert({'content': '• '})
        .select()
        .single();
    return SimpleList.fromJson(inserted);
  }

  Future<void> save(String content) async {
    final userId = _client.auth.currentUser!.id;
    await _client.from('simple_list').upsert({
      'user_id': userId,
      'content': content,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }
}

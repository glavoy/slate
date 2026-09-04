import 'package:supabase_flutter/supabase_flutter.dart';

import '../local/local_database.dart';
import '../sync/sync_service.dart';

/// Owns the local-session boundary so every sign-out control has identical
/// privacy behavior.
abstract final class SessionService {
  static Future<void> signOut(SupabaseClient client) async {
    await client.auth.signOut();
    await clearSignedOutData();
  }

  /// Used after an externally initiated Supabase sign-out as a safety net.
  static Future<void> clearSignedOutData() async {
    await SyncService.instance.pause(flushPending: false);
    LocalDatabase.instance.clearCachedData();
  }
}

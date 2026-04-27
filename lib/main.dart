import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'env/env.dart';
import 'local/local_database.dart';
import 'providers/settings_providers.dart';
import 'providers/theme_provider.dart';
import 'sync/sync_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(url: Env.supabaseUrl, anonKey: Env.supabaseAnonKey);
  await LocalDatabase.instance.open();
  SyncService.instance.configure(
    client: Supabase.instance.client,
    local: LocalDatabase.instance,
  );

  final container = ProviderContainer();
  await Future.wait([
    container.read(themeNotifierProvider.notifier).init(),
    container.read(dateFormatNotifierProvider.notifier).init(),
    container.read(timeFormatNotifierProvider.notifier).init(),
  ]);

  runApp(
    UncontrolledProviderScope(container: container, child: const SlateApp()),
  );
}

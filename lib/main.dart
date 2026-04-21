import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'env/env.dart';
import 'providers/theme_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey,
  );

  final container = ProviderContainer();
  await container.read(themeNotifierProvider.notifier).init();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const SlateApp(),
    ),
  );
}

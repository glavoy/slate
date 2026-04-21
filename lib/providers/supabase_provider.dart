import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'supabase_provider.g.dart';

@riverpod
// ignore: deprecated_member_use_from_same_package
SupabaseClient supabaseClient(SupabaseClientRef ref) =>
    Supabase.instance.client;

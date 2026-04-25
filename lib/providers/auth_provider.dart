import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_provider.dart';

part 'auth_provider.g.dart';

@riverpod
// ignore: deprecated_member_use_from_same_package
Stream<AuthState> authState(AuthStateRef ref) {
  final client = ref.watch(supabaseClientProvider);
  return client.auth.onAuthStateChange;
}

@riverpod
// ignore: deprecated_member_use_from_same_package
User? currentUser(CurrentUserRef ref) {
  ref.watch(authStateProvider);
  return ref.watch(supabaseClientProvider).auth.currentUser;
}

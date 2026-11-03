import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/env.dart';

/// Initialises the Supabase client once, before `runApp`. A build without a
/// project (`Env.hasSupabase == false`) skips this and every provider below
/// reports "no cloud", which the social screens render as an explanation.
Future<void> initSupabase() async {
  if (!Env.hasSupabase) return;
  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabasePublishableKey,
  );
}

/// The client, or null when the build has no Supabase project. Overridable in
/// tests with a mock client.
final supabaseProvider = Provider<SupabaseClient?>(
  (ref) => Env.hasSupabase ? Supabase.instance.client : null,
);

/// Auth events; completes with a single null when there is no client.
final authStateProvider = StreamProvider<AuthState?>((ref) {
  final client = ref.watch(supabaseProvider);
  if (client == null) return Stream<AuthState?>.value(null);
  return client.auth.onAuthStateChange;
});

/// The current session, re-read on every auth event.
final sessionProvider = Provider<Session?>((ref) {
  final client = ref.watch(supabaseProvider);
  ref.watch(authStateProvider);
  return client?.auth.currentSession;
});

/// The signed-in user's id, or null when signed out or offline-only.
final currentUserIdProvider = Provider<String?>(
  (ref) => ref.watch(sessionProvider)?.user.id,
);

/// True when the build has a project and someone is signed in.
final isSignedInProvider = Provider<bool>(
  (ref) => ref.watch(currentUserIdProvider) != null,
);

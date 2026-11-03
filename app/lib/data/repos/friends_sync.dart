import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database.dart';
import '../supabase/supabase_providers.dart';
import '../sync/outbox.dart';
import 'feed_repo.dart';
import 'friends_repo.dart';

final friendsRepoProvider = Provider<FriendsRepo>(
  (ref) => FriendsRepo(
    clientOf: () => ref.read(supabaseProvider),
    db: ref.watch(databaseProvider),
    outbox: ref.watch(outboxWorkerProvider),
    me: () => ref.read(currentUserIdProvider),
  ),
);

final feedRepoProvider = Provider<FeedRepo>(
  (ref) => FeedRepo(
    clientOf: () => ref.read(supabaseProvider),
    db: ref.watch(databaseProvider),
    outbox: ref.watch(outboxWorkerProvider),
    me: () => ref.read(currentUserIdProvider),
  ),
);

/// Registers the friends and feed outbox handlers. Watched once from the
/// Friends and Drive screens (and by the sync bootstrap when present).
final friendsSyncProvider = Provider<void>((ref) {
  final worker = ref.watch(outboxWorkerProvider);
  ref.watch(friendsRepoProvider).registerHandlers(worker);
  ref.watch(feedRepoProvider).registerHandlers(worker);
  // A sign-in may unblock rows that were waiting on `OutboxRetryLater`.
  ref.listen(currentUserIdProvider, (_, next) {
    if (next != null) worker.scheduleDrain();
  });
});

/// Friends and pending requests: the cache first, then the network.
class FriendsSnapshotNotifier extends AsyncNotifier<FriendsSnapshot> {
  @override
  Future<FriendsSnapshot> build() async {
    final me = ref.watch(currentUserIdProvider);
    final repo = ref.watch(friendsRepoProvider);
    // Keep the state in step with optimistic cache writes.
    final sub = repo.watchCached().listen((s) {
      if (s != null) state = AsyncData(s);
    });
    ref.onDispose(sub.cancel);
    if (me == null) return const FriendsSnapshot();
    final cached = await repo.cached();
    unawaited(_refresh(repo));
    return cached ?? const FriendsSnapshot();
  }

  Future<void> _refresh(FriendsRepo repo) async {
    try {
      final fresh = await repo.fetch();
      state = AsyncData(fresh);
    } catch (e) {
      debugPrint('friends refresh failed: $e');
    }
  }

  Future<void> refresh() => _refresh(ref.read(friendsRepoProvider));
}

final friendsSnapshotProvider =
    AsyncNotifierProvider<FriendsSnapshotNotifier, FriendsSnapshot>(
      FriendsSnapshotNotifier.new,
    );

/// Incoming friend requests waiting for an answer (badge on the Drive tab).
final pendingRequestCountProvider = Provider<int>(
  (ref) => ref.watch(friendsSnapshotProvider).value?.incoming.length ?? 0,
);

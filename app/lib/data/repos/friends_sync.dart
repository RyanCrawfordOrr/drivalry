import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database.dart';
import '../supabase/supabase_providers.dart';
import '../sync/outbox.dart';
import 'feed_repo.dart';
import 'friends_repo.dart';
import 'moderation_repo.dart';

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
  ref.watch(moderationRepoProvider).registerHandlers(worker);
  // A sign-in may unblock rows that were waiting on `OutboxRetryLater`.
  ref.listen(currentUserIdProvider, (_, next) {
    if (next != null) worker.scheduleDrain();
  });
});

/// Friends and pending requests: the cache first, then the network.
///
/// The other side's answer to a request lands while this app is not looking
/// (a push at best, nothing at all with notifications off), so besides the
/// fetch at start-up the snapshot is pulled again when the app returns to the
/// foreground and when the Friends tab opens, unless it is younger than
/// [staleAfter]. Pushes about friends trigger an unconditional [refresh]
/// (see PushService).
class FriendsSnapshotNotifier extends AsyncNotifier<FriendsSnapshot> {
  /// How old a snapshot may be before a resume or tab open refetches it.
  /// Short enough that an acceptance shows on the next look, long enough
  /// that hopping between tabs does not hit the network every time.
  static const staleAfter = Duration(seconds: 30);

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
    final lifecycle = AppLifecycleListener(
      onResume: () => unawaited(refreshIfStale()),
    );
    ref.onDispose(lifecycle.dispose);
    final cached = await repo.cached();
    unawaited(_refresh(repo));
    return cached ?? const FriendsSnapshot();
  }

  /// Fetches unless the current snapshot was fetched within [staleAfter].
  /// Nothing to fetch while signed out.
  Future<void> refreshIfStale({DateTime? now}) async {
    if (ref.read(currentUserIdProvider) == null) return;
    final s = state.value;
    if (s != null && !s.isStale(now ?? DateTime.now(), staleAfter)) return;
    await _refresh(ref.read(friendsRepoProvider));
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

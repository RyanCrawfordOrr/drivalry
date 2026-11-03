import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database.dart';
import '../supabase/supabase_providers.dart';
import '../sync/outbox.dart';
import 'circles_repo.dart';

final circlesRepoProvider = Provider<CirclesRepo>((ref) {
  return CirclesRepo(
    apiOf: () {
      final client = ref.read(supabaseProvider);
      if (client == null || client.auth.currentSession == null) return null;
      return SupabaseCirclesApi(client);
    },
    db: ref.watch(databaseProvider),
    outbox: ref.watch(outboxWorkerProvider),
    me: () => ref.read(currentUserIdProvider),
  );
});

/// Registers the circle outbox handlers. Watched from the sync bootstrap and
/// the Friends screen.
final circlesSyncProvider = Provider<void>((ref) {
  final worker = ref.watch(outboxWorkerProvider);
  ref.watch(circlesRepoProvider).registerHandlers(worker);
  ref.listen(currentUserIdProvider, (_, next) {
    if (next != null) worker.scheduleDrain();
  });
});

/// My circles: the cache first, then the network.
class MyCirclesNotifier extends AsyncNotifier<List<Circle>> {
  @override
  Future<List<Circle>> build() async {
    final me = ref.watch(currentUserIdProvider);
    final repo = ref.watch(circlesRepoProvider);
    final sub = repo.watchCached().listen((c) {
      if (c != null) state = AsyncData(c);
    });
    ref.onDispose(sub.cancel);
    if (me == null) return const [];
    final cached = await repo.cached();
    unawaited(_refresh(repo));
    return cached ?? const [];
  }

  Future<void> _refresh(CirclesRepo repo) async {
    try {
      state = AsyncData(await repo.fetch());
    } catch (e) {
      debugPrint('circles refresh failed: $e');
    }
  }

  Future<void> refresh() => _refresh(ref.read(circlesRepoProvider));
}

final myCirclesProvider =
    AsyncNotifierProvider<MyCirclesNotifier, List<Circle>>(
      MyCirclesNotifier.new,
    );

/// One circle from the list, live.
final circleProvider = Provider.family<Circle?, String>((ref, id) {
  final circles = ref.watch(myCirclesProvider).value ?? const [];
  for (final c in circles) {
    if (c.id == id) return c;
  }
  return null;
});

/// Members of a circle: cache first; `ref.invalidate` to refetch.
final circleMembersProvider = FutureProvider.family<List<CircleMember>, String>(
  (ref, circleId) async {
    final repo = ref.watch(circlesRepoProvider);
    final cached = await repo.cachedMembers(circleId);
    if (cached != null) {
      unawaited(
        repo.fetchMembers(circleId).catchError((Object e) {
          debugPrint('members refresh failed: $e');
          return cached;
        }),
      );
      return cached;
    }
    return repo.fetchMembers(circleId);
  },
);

/// Live member lists keyed by circle id, for the map's circle filter.
final circleMembershipProvider = Provider<Map<String, Set<String>>>((ref) {
  final circles = ref.watch(myCirclesProvider).value ?? const [];
  return {
    for (final c in circles)
      c.id: {
        for (final m
            in ref.watch(circleMembersProvider(c.id)).value ??
                const <CircleMember>[])
          m.userId,
      },
  };
});

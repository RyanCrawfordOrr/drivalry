import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/convoy/live/convoy_live.dart';
import '../db/database.dart';
import '../supabase/supabase_providers.dart';
import '../sync/outbox.dart';
import 'convoy_repo.dart';

final convoyRepoProvider = Provider<ConvoyRepo>((ref) {
  return ConvoyRepo(
    apiOf: () {
      final client = ref.read(supabaseProvider);
      if (client == null || client.auth.currentSession == null) return null;
      return SupabaseConvoysApi(client);
    },
    db: ref.watch(databaseProvider),
    outbox: ref.watch(outboxWorkerProvider),
    me: () => ref.read(currentUserIdProvider),
  );
});

/// Registers the convoy outbox handlers and purges 30-day-old tracks once.
/// Watched from the sync bootstrap and the Convoy tab.
final convoySyncProvider = Provider<void>((ref) {
  final worker = ref.watch(outboxWorkerProvider);
  ref.watch(convoyRepoProvider).registerHandlers(worker);
  ref.listen(currentUserIdProvider, (_, next) {
    if (next != null) worker.scheduleDrain();
  });
  // Positions, ETAs and lost-sheep checks run while a convoy is active even
  // with no convoy screen open.
  ref.watch(activeConvoyLiveProvider);
  unawaited(
    ref
        .read(databaseProvider)
        .purgeOldConvoyTracks(
          DateTime.now()
              .subtract(const Duration(days: 30))
              .millisecondsSinceEpoch,
        )
        .catchError((Object e) {
          debugPrint('convoy track purge failed: $e');
          return 0;
        }),
  );
});

/// My convoys: cache first, then the network.
class MyConvoysNotifier extends AsyncNotifier<List<Convoy>> {
  @override
  Future<List<Convoy>> build() async {
    final me = ref.watch(currentUserIdProvider);
    final repo = ref.watch(convoyRepoProvider);
    final sub = repo.watchCached().listen((c) {
      if (c != null) state = AsyncData(c);
    });
    ref.onDispose(sub.cancel);
    if (me == null) return const [];
    final cached = await repo.cached();
    unawaited(_refresh(repo));
    return cached ?? const [];
  }

  Future<void> _refresh(ConvoyRepo repo) async {
    try {
      state = AsyncData(await repo.fetch());
    } catch (e) {
      debugPrint('convoys refresh failed: $e');
    }
  }

  Future<void> refresh() => _refresh(ref.read(convoyRepoProvider));
}

final myConvoysProvider =
    AsyncNotifierProvider<MyConvoysNotifier, List<Convoy>>(
      MyConvoysNotifier.new,
    );

/// One convoy from my list, live.
final convoyProvider = Provider.family<Convoy?, String>((ref, id) {
  final list = ref.watch(myConvoysProvider).value ?? const [];
  for (final c in list) {
    if (c.id == id) return c;
  }
  return null;
});

/// The convoy I am currently driving in (active), or the one being planned
/// when none is active. Null when I am in none.
final activeConvoyProvider = Provider<Convoy?>((ref) {
  final list = ref.watch(myConvoysProvider).value ?? const [];
  for (final c in list) {
    if (c.isActive) return c;
  }
  for (final c in list) {
    if (c.status == ConvoyStatus.planning) return c;
  }
  return null;
});

/// Who leads a convoy (its creator).
final convoyLeaderProvider = Provider.family<String?, String>(
  (ref, id) => ref.watch(convoyProvider(id))?.createdBy,
);

final amConvoyLeaderProvider = Provider.family<bool, String>((ref, id) {
  final me = ref.watch(currentUserIdProvider);
  return me != null && ref.watch(convoyLeaderProvider(id)) == me;
});

/// Generic "cache first, network when empty, live on cache writes" list.
Stream<List<T>> _cacheThenFetch<T>({
  required Stream<List<T>?> watch,
  required Future<List<T>?> Function() cached,
  required Future<List<T>> Function() fetch,
}) {
  late StreamController<List<T>> out;
  StreamSubscription<List<T>?>? sub;
  out = StreamController<List<T>>(
    onListen: () async {
      sub = watch.listen((v) {
        if (v != null && !out.isClosed) out.add(v);
      });
      final c = await cached();
      if (c != null && !out.isClosed) out.add(c);
      try {
        final f = await fetch();
        if (!out.isClosed) out.add(f);
      } catch (e) {
        debugPrint('convoy fetch failed: $e');
        if (c == null && !out.isClosed) out.add(const []);
      }
    },
    onCancel: () => sub?.cancel(),
  );
  return out.stream;
}

final convoyMembersProvider = StreamProvider.autoDispose
    .family<List<ConvoyMember>, String>((ref, id) {
      final repo = ref.watch(convoyRepoProvider);
      ref.watch(convoyRealtimeProvider(id));
      return _cacheThenFetch(
        watch: repo.watchMembers(id),
        cached: () => repo.cachedMembers(id),
        fetch: () => repo.fetchMembers(id),
      );
    });

final convoyStopsProvider = StreamProvider.autoDispose
    .family<List<ConvoyStop>, String>((ref, id) {
      final repo = ref.watch(convoyRepoProvider);
      ref.watch(convoyRealtimeProvider(id));
      return _cacheThenFetch(
        watch: repo.watchStops(id),
        cached: () => repo.cachedStops(id),
        fetch: () => repo.fetchStops(id),
      );
    });

final convoyExpensesProvider = StreamProvider.autoDispose
    .family<List<ConvoyExpense>, String>((ref, id) {
      final repo = ref.watch(convoyRepoProvider);
      return _cacheThenFetch(
        watch: repo.watchExpenses(id),
        cached: () => repo.cachedExpenses(id),
        fetch: () => repo.fetchExpenses(id),
      );
    });

final convoyPhotosProvider = StreamProvider.autoDispose
    .family<List<ConvoyPhoto>, String>((ref, id) {
      final repo = ref.watch(convoyRepoProvider);
      return _cacheThenFetch(
        watch: repo.watchPhotos(id),
        cached: () => repo.cachedPhotos(id),
        fetch: () => repo.fetchPhotos(id),
      );
    });

/// Whether a `convoy_stop_votes` change is about a stop of ours. The table
/// has no `convoy_id`, so Postgres Changes cannot filter it server-side.
bool voteEventIsOurs(
  Map<String, dynamic> newRecord,
  Map<String, dynamic> oldRecord,
  Set<String> knownStopIds,
) {
  final stopId = newRecord['stop_id'] ?? oldRecord['stop_id'];
  return stopId is String && knownStopIds.contains(stopId);
}

/// Display names of a convoy's members by user id, "You" for me. Backed by
/// the member stream so it follows joins and renames.
final convoyMemberNamesProvider = Provider.autoDispose
    .family<Map<String, String>, String>((ref, id) {
      final me = ref.watch(currentUserIdProvider);
      final members = ref.watch(convoyMembersProvider(id)).value ?? const [];
      return {
        for (final m in members) m.userId: m.userId == me ? 'You' : m.name,
      };
    });

/// Present (not left) members of a convoy, by id.
final convoyMemberIdsProvider = Provider.autoDispose
    .family<Set<String>, String>((ref, id) {
      final members = ref.watch(convoyMembersProvider(id)).value ?? const [];
      return {
        for (final m in members)
          if (m.isPresent) m.userId,
      };
    });

/// Postgres Changes on the convoy's durable tables while a convoy screen is
/// open: any change refetches members and stops (docs/03 §7). Nothing is
/// subscribed when the provider is not watched.
final convoyRealtimeProvider = Provider.autoDispose.family<void, String>((
  ref,
  id,
) {
  final client = ref.watch(supabaseProvider);
  final repo = ref.watch(convoyRepoProvider);
  if (client == null || ref.watch(currentUserIdProvider) == null) return;

  Timer? debounce;
  void refetch() {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(
        repo.fetchMembers(id).catchError((Object e) => <ConvoyMember>[]),
      );
      unawaited(repo.fetchStops(id).catchError((Object e) => <ConvoyStop>[]));
      unawaited(
        repo.fetch().then((_) {}).catchError((Object e) {
          debugPrint('convoy refetch failed: $e');
        }),
      );
    });
  }

  final channel = client.channel('convoy-db:$id');
  channel
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'convoy_members',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'convoy_id',
          value: id,
        ),
        callback: (_) => refetch(),
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'convoy_stops',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'convoy_id',
          value: id,
        ),
        callback: (_) => refetch(),
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'convoy_stop_votes',
        callback: (payload) {
          // No convoy_id column on votes, so every convoy's votes arrive
          // here; only a vote on one of our cached stops is worth a refetch.
          unawaited(
            repo
                .cachedStops(id)
                .then((stops) {
                  final known = {
                    for (final s in stops ?? const <ConvoyStop>[]) s.id,
                  };
                  if (voteEventIsOurs(
                    payload.newRecord,
                    payload.oldRecord,
                    known,
                  )) {
                    refetch();
                  }
                })
                .catchError((Object e) {
                  debugPrint('vote event check failed: $e');
                }),
          );
        },
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'convoys',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: id,
        ),
        callback: (_) => refetch(),
      )
      .subscribe();
  ref.onDispose(() {
    debounce?.cancel();
    unawaited(client.removeChannel(channel));
  });
});

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../supabase/supabase_providers.dart';
import '../sync/outbox.dart';
import 'badge_defs.dart';
import 'badge_engine.dart';
import 'badges_providers.dart';

/// Runs the [BadgeEngine] whenever a trip is scored and pushes awards to the
/// cloud through the outbox (`user_badges` row plus a `badge` feed post).
class BadgesSync {
  BadgesSync({
    required this.db,
    required this.outbox,
    required this.client,
    required this.userId,
    required this.defs,
    int Function()? now,
  }) : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch) {
    engine = BadgeEngine(
      db,
      onAwarded: (id, at) => _enqueue(id, awardedAt: at),
      now: _now,
    );
    _registerHandler();
  }

  final AppDatabase db;
  final OutboxWorker outbox;
  final SupabaseClient? client;
  final String? Function() userId;
  final Future<List<BadgeDef>> Function() defs;
  final int Function() _now;
  late final BadgeEngine engine;

  static const kind = 'user_badge';
  static const _uuid = Uuid();
  StreamSubscription<List<TripWithScore>>? _sub;
  Future<void> _chain = Future.value();

  /// Badge definitions, fetched once per sync pass rather than per award.
  Future<List<BadgeDef>>? _defs;
  Future<List<BadgeDef>> _definitions() => _defs ??= defs();

  /// Starts watching scored trips. Safe to call once; the subscription is
  /// cancelled by [dispose].
  void start() {
    _sub ??= db.watchScoredTripsWithScores(limit: 300).listen((rows) {
      _chain = _chain.then((_) => engine.evaluate(rows)).catchError((Object e) {
        debugPrint('badge evaluation failed: $e');
        return <String>[];
      });
    });
    unawaited(syncPending());
  }

  /// Waits for the evaluation queue to empty (tests).
  Future<void> flush() => _chain;

  /// Re-queues awards made while signed out or before a previous sync could
  /// finish. Call when a user signs in.
  Future<void> syncPending() async {
    final uid = userId();
    if (uid == null) return;
    _defs = null; // definitions may have changed since the last pass
    for (final a in await db.allBadgeAwards()) {
      if (!a.synced) await _enqueue(a.badgeId, awardedAt: a.awardedAt);
    }
  }

  Future<void> _enqueue(String badgeId, {int? awardedAt}) async {
    final uid = userId();
    if (uid == null) return; // syncPending() catches up after sign-in
    final name = badgeDefById(await _definitions(), badgeId)?.name ?? badgeId;
    awardedAt ??= (await db.badgeAward(badgeId))?.awardedAt ?? _now();
    await outbox.enqueue(kind, {
      'user_id': uid,
      'badge_id': badgeId,
      'name': name,
      'awarded_at': awardedAt,
      'post_id': _uuid.v5(Namespace.url.value, 'drivalry:badge:$uid:$badgeId'),
    }, id: 'user_badge:$uid:$badgeId');
  }

  void _registerHandler() {
    if (outbox.handles(kind)) return;
    outbox.register(kind, (p) async {
      final c = client;
      final uid = userId();
      if (c == null || uid == null) throw const OutboxRetryLater('signed out');
      // Another account's award: leave it queued for them.
      if (p['user_id'] != uid) throw const OutboxSkip('another account');
      final badgeId = p['badge_id'] as String;
      final awardedAt = DateTime.fromMillisecondsSinceEpoch(
        (p['awarded_at'] as num).toInt(),
      ).toUtc().toIso8601String();
      await c
          .from('user_badges')
          .upsert(
            {'user_id': uid, 'badge_id': badgeId, 'awarded_at': awardedAt},
            onConflict: 'user_id,badge_id',
            ignoreDuplicates: true,
          );
      await c
          .from('feed_posts')
          .upsert(
            {
              'id': p['post_id'],
              'author_id': uid,
              'kind': 'badge',
              'body': {'badge_id': badgeId, 'name': p['name']},
              'created_at': awardedAt,
            },
            onConflict: 'id',
            ignoreDuplicates: true,
          );
      await db.markBadgeSynced(badgeId);
    });
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }
}

/// Keeps badge evaluation and upload alive for the life of the app. Watch it
/// from the bootstrap provider.
final badgesSyncProvider = Provider<BadgesSync>((ref) {
  final sync = BadgesSync(
    db: ref.watch(databaseProvider),
    outbox: ref.watch(outboxWorkerProvider),
    client: ref.watch(supabaseProvider),
    userId: () => ref.read(currentUserIdProvider),
    defs: () => ref.read(badgeDefsProvider.future),
  );
  sync.start();
  // A sign-in after start-up uploads awards earned while signed out.
  ref.listen<String?>(currentUserIdProvider, (prev, next) {
    if (next != null && next != prev) sync.syncPending();
  });
  ref.onDispose(sync.dispose);
  return sync;
});

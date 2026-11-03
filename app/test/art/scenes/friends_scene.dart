import 'dart:convert';

import 'package:drivalry/app/deep_links.dart';
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/repos/feed_repo.dart';
import 'package:drivalry/data/repos/friends_sync.dart';
import 'package:drivalry/data/supabase/supabase_providers.dart';
import 'package:drivalry/data/sync/outbox.dart';
import 'package:drivalry/features/friends/friends_screen.dart';
import 'package:drivalry/tracking/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../support/fake_tracking_port.dart';
import '../../support/sqlite_support.dart';
import '../art_harness.dart';
import 'scene.dart';

/// `04-friends`: the real [FriendsScreen] on its Feed tab with a populated,
/// friends-only feed.
///
/// The feed repo caches each page of `feed_posts` (author profile, body,
/// reactions, comment count) as JSON in the drift `remote_cache` table, so the
/// page is seeded there under the repo's own key. The controller then asks
/// "the network" for a fresh page; [_CachedFeedRepo] answers from that same
/// cache, which is what keeps the seeded posts on screen.
class FriendsScene extends ArtScene {
  static const _me = 'kai';

  AppDatabase? _db;
  FakeTrackingPort? _port;

  @override
  String get id => '04-friends';

  @override
  String get headline => 'Good drives get reactions. Bad ones get roasted.';

  @override
  String get subline => 'A feed only your friends can see.';

  @override
  Duration get settle => const Duration(seconds: 3);

  @override
  Future<Widget> build() async {
    final db = _db = memoryDatabase();
    final port = _port = FakeTrackingPort();
    await db.cachePut(
      FeedRepo.cacheKey(FeedFilter.all, 0),
      jsonEncode([for (final p in _posts()) p.toJson()]),
      DateTime.now().millisecondsSinceEpoch,
    );
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        trackingPortProvider.overrideWithValue(port),
        deepLinkSourceProvider.overrideWithValue(const NoDeepLinks()),
        currentUserIdProvider.overrideWithValue(_me),
        cloudConfiguredProvider.overrideWithValue(true),
        feedRepoProvider.overrideWith(
          (ref) => _CachedFeedRepo(
            db: ref.watch(databaseProvider),
            outbox: ref.watch(outboxWorkerProvider),
            me: () => _me,
          ),
        ),
      ],
      child: MaterialApp(
        theme: artTheme(Brightness.light),
        darkTheme: artTheme(),
        themeMode: ThemeMode.dark,
        debugShowCheckedModeBanner: false,
        home: const FriendsScreen(),
      ),
    );
  }

  @override
  Future<void> dispose() async {
    await _port?.dispose();
    await _db?.close();
    _port = null;
    _db = null;
  }

  /// Five posts from four friends, newest first, each the shape
  /// `TripUploader` and `BadgesSync` publish. Roasts target the drive, never
  /// the driver, and a speeding roast is a roast, not a brag.
  static List<FeedPost> _posts() {
    final now = DateTime.now().toUtc();
    return [
      FeedPost(
        id: 'post-priya-94',
        author: _author('priya', 'Priya'),
        kind: 'trip',
        tripId: 'trip-priya-94',
        createdAt: now.subtract(const Duration(hours: 2, minutes: 14)),
        body: {
          'score': 94,
          'xp': 96,
          'reckless': false,
          'roast':
              'Butter smooth. 14 miles, zero events, and the phone '
              'stayed face down the whole way.',
          'tone': 'praise',
          'speeding': false,
        },
        reactions: const {'fire': 6, 'clap': 3},
        myReactions: const {'fire'},
        commentCount: 2,
      ),
      FeedPost(
        id: 'post-jordan-shame',
        author: _author('jordan', 'Jordan'),
        kind: 'shame',
        tripId: 'trip-jordan-38',
        createdAt: now.subtract(const Duration(hours: 3, minutes: 40)),
        body: {
          'score': 38,
          'xp': 0,
          'reckless': true,
          'roast':
              '41 in a 25 on Elm Street, for 90 seconds, to save 40 '
              'seconds. Everyone here can see this.',
          'tone': 'roast',
          'components': {'speed': 46, 'smoothness': 12, 'attention': 4},
          'speeding': true,
        },
        reactions: const {'skull': 7, 'clown': 4, 'snitch': 3, 'laugh': 2},
        myReactions: const {'snitch'},
        commentCount: 5,
      ),
      FeedPost(
        id: 'post-sam-71',
        author: _author('sam', 'Sam'),
        kind: 'trip',
        tripId: 'trip-sam-71',
        createdAt: now.subtract(const Duration(hours: 5, minutes: 5)),
        body: {
          'score': 71,
          'xp': 52,
          'reckless': false,
          'roast':
              'Two hard brakes and a yellow light you argued with. '
              'Decent, not clean.',
          'tone': 'roast',
          'components': {'smoothness': 18, 'speed': 11},
          'speeding': true,
        },
        reactions: const {'laugh': 3, 'clap': 1},
        commentCount: 1,
      ),
      FeedPost(
        id: 'post-alex-badge',
        author: _author('alex', 'Alex'),
        kind: 'badge',
        createdAt: now.subtract(const Duration(hours: 8, minutes: 30)),
        body: const {
          'badge_id': 'hands_off',
          'badge_name': 'Hands Off',
          'name': 'Hands Off',
        },
        reactions: const {'clap': 4, 'fire': 2},
        commentCount: 0,
      ),
      FeedPost(
        id: 'post-maya-88',
        author: _author('maya', 'Maya'),
        kind: 'trip',
        tripId: 'trip-maya-88',
        createdAt: now.subtract(const Duration(hours: 26)),
        body: {
          'score': 88,
          'xp': 70,
          'reckless': false,
          'roast':
              'Clean run. One late lane change on the parkway, '
              'otherwise nothing to see.',
          'tone': 'praise',
          'speeding': false,
        },
        reactions: const {'fire': 2},
        commentCount: 0,
      ),
    ];
  }

  static FeedAuthor _author(String id, String name) =>
      FeedAuthor(id: id, handle: id, displayName: name);
}

/// A [FeedRepo] whose network is the cache: `fetchPage` returns the page the
/// scene seeded, so the controller's refresh keeps the posts instead of
/// replacing them with an empty page from a missing client.
class _CachedFeedRepo extends FeedRepo {
  _CachedFeedRepo({required super.db, required super.outbox, required super.me})
    : super(clientOf: () => null);

  @override
  Future<List<FeedPost>> fetchPage(FeedFilter filter, int page) async =>
      await cachedPage(filter, page) ?? const [];
}

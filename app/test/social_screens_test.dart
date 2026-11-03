import 'dart:convert';

import 'package:drivalry/app/deep_links.dart';
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/repos/feed_repo.dart';
import 'package:drivalry/data/repos/friends_repo.dart';
import 'package:drivalry/data/repos/friends_sync.dart';
import 'package:drivalry/data/supabase/supabase_providers.dart';
import 'package:drivalry/data/sync/outbox.dart';
import 'package:drivalry/features/circles/circles_view.dart';
import 'package:drivalry/features/friends/friends_list_view.dart';
import 'package:drivalry/features/friends/friends_screen.dart';
import 'package:drivalry/features/profile/profile_screen.dart';
import 'package:drivalry/tracking/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_tracking_port.dart';
import 'support/sqlite_support.dart';
import 'support/widget_support.dart';

const _me = 'me-0000';

/// A feed whose network is the cache, so seeded pages stay on screen.
class _CachedFeedRepo extends FeedRepo {
  _CachedFeedRepo({required super.db, required super.outbox, required super.me})
    : super(clientOf: () => null);

  @override
  Future<List<FeedPost>> fetchPage(FeedFilter filter, int page) async =>
      await cachedPage(filter, page) ?? const [];
}

/// Friends whose refresh returns the cache instead of an empty snapshot.
class _CachedFriendsRepo extends FriendsRepo {
  _CachedFriendsRepo({
    required super.db,
    required super.outbox,
    required super.me,
  }) : super(clientOf: () => null);

  @override
  Future<FriendsSnapshot> fetch() async =>
      await cached() ?? const FriendsSnapshot();
}

/// The social screens signed in as [user] (null: signed out) against an
/// in-memory database, with cache-backed repos.
Widget _scope(
  AppDatabase db,
  FakeTrackingPort port,
  Widget home, {
  String? user = _me,
}) => ProviderScope(
  overrides: [
    databaseProvider.overrideWithValue(db),
    trackingPortProvider.overrideWithValue(port),
    deepLinkSourceProvider.overrideWithValue(const NoDeepLinks()),
    currentUserIdProvider.overrideWithValue(user),
    cloudConfiguredProvider.overrideWithValue(true),
    feedRepoProvider.overrideWith(
      (ref) => _CachedFeedRepo(
        db: ref.watch(databaseProvider),
        outbox: ref.watch(outboxWorkerProvider),
        me: () => user,
      ),
    ),
    friendsRepoProvider.overrideWith(
      (ref) => _CachedFriendsRepo(
        db: ref.watch(databaseProvider),
        outbox: ref.watch(outboxWorkerProvider),
        me: () => user,
      ),
    ),
  ],
  child: MaterialApp(home: home),
);

FeedPost _post({
  required String id,
  required String author,
  required String kind,
  required Map<String, dynamic> body,
  Map<String, int> reactions = const {},
  int comments = 0,
}) => FeedPost(
  id: id,
  author: FeedAuthor(id: author, handle: author, displayName: author),
  kind: kind,
  body: body,
  createdAt: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
  reactions: reactions,
  commentCount: comments,
);

FriendRequest _incoming(String id, String name) => FriendRequest(
  requesterId: id,
  addresseeId: _me,
  other: FriendProfile(id: id, handle: id, displayName: name),
  direction: FriendRequestDirection.incoming,
  createdAt: DateTime.utc(2026, 11, 2),
);

void main() {
  final skip = skipWithoutSqlite() != null;
  late AppDatabase db;
  late FakeTrackingPort port;
  setUp(() {
    db = memoryDatabase();
    port = FakeTrackingPort();
  });
  tearDown(() async {
    await port.dispose();
    await db.close();
  });

  Widget app(Widget home, {String? user = _me}) =>
      _scope(db, port, home, user: user);

  testWidgets('an empty feed shows one Add friend button and no FAB', (
    tester,
  ) async {
    await tester.pumpWidget(app(const FriendsScreen()));
    await pumpFor(tester, const Duration(seconds: 2));
    expect(find.text('Nothing yet.'), findsOneWidget);
    expect(find.text('Add a friend and the roasts start.'), findsOneWidget);
    expect(find.text('Add friend'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets('posts carry the wall kicker and long-press opens actions', (
    tester,
  ) async {
    await db.cachePut(
      FeedRepo.cacheKey(FeedFilter.all, 0),
      jsonEncode([
        _post(
          id: 'p1',
          author: 'jordan',
          kind: 'shame',
          body: const {
            'score': 38,
            'reckless': true,
            'roast': 'Forty-one in a twenty-five on Elm Street.',
            'speeding': true,
            'components': {'speed': 46},
          },
          reactions: const {'skull': 7},
          comments: 5,
        ).toJson(),
        _post(
          id: 'p2',
          author: 'priya',
          kind: 'trip',
          body: const {'score': 94, 'roast': 'Butter smooth.'},
        ).toJson(),
      ]),
      DateTime.now().millisecondsSinceEpoch,
    );
    await tester.pumpWidget(app(const FriendsScreen()));
    await pumpFor(tester, const Duration(seconds: 2));
    expect(find.text('WALL OF SHAME'), findsOneWidget);
    expect(find.text('WALL OF FAME'), findsOneWidget);
    expect(
      find.text('Forty-one in a twenty-five on Elm Street.'),
      findsOneWidget,
    );
    expect(find.text('5 comments'), findsOneWidget);
    // With posts on screen, Add friend is an app-bar icon: nothing floats
    // over the posts.
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byTooltip('Add friend'), findsOneWidget);

    await tester.longPress(
      find.text('Forty-one in a twenty-five on Elm Street.'),
    );
    await pumpFor(tester, const Duration(seconds: 1));
    for (final label in ['REACT', 'Comment', 'Share', 'Report']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    await tester.tapAt(const Offset(5, 5));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('Report'), findsNothing);
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets('the friends tab with nobody added shows the empty state', (
    tester,
  ) async {
    await tester.pumpWidget(app(const FriendsScreen()));
    await pumpFor(tester, const Duration(seconds: 1));
    await tester.tap(find.widgetWithText(Tab, 'Friends'));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('No friends yet.'), findsOneWidget);
    expect(find.text('Add friend'), findsOneWidget);
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets('swiping a request away declines it, with Undo', (tester) async {
    final snapshot = FriendsSnapshot(incoming: [_incoming('jordan', 'Jordan')]);
    await db.cachePut(
      FriendsRepo.cacheKey,
      jsonEncode(snapshot.toJson()),
      DateTime.now().millisecondsSinceEpoch,
    );
    await tester.pumpWidget(app(const Scaffold(body: FriendsListView())));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('Jordan'), findsOneWidget);

    // Swipe left: the row goes at once and the snackbar offers Undo.
    await tester.drag(find.text('Jordan'), const Offset(-500, 0));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('Jordan'), findsNothing);
    expect(find.text('Declined Jordan.'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('Jordan'), findsOneWidget);
    final repo = FriendsRepo(
      clientOf: () => null,
      db: db,
      outbox: OutboxWorker(db),
      me: () => _me,
    );
    expect((await repo.cached())!.incoming, hasLength(1));

    // Swipe again and let the snackbar time out: now it is really declined.
    await tester.drag(find.text('Jordan'), const Offset(-500, 0));
    await pumpFor(tester, const Duration(seconds: 7));
    expect(find.text('Jordan'), findsNothing);
    expect((await repo.cached())!.incoming, isEmpty);
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets('no circles: one New circle button plus Join with code', (
    tester,
  ) async {
    await tester.pumpWidget(app(const Scaffold(body: CirclesView())));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('No circles yet.'), findsOneWidget);
    expect(find.text('New circle'), findsOneWidget);
    expect(find.text('Join with code'), findsOneWidget);
    expect(find.text('I got home'), findsNothing);
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets('a signed-out profile asks you to sign in', (tester) async {
    await tester.pumpWidget(app(const ProfileScreen(), user: null));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.text('Sign in to get a profile.'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    await unmountAndSettle(tester);
  }, skip: skip);
}

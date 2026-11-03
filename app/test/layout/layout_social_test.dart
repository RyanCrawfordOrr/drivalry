// Layout audit for the social area: the Friends root on each tab, requests,
// post detail, add friend, circles, places, profile and sign-in, each in its
// empty and populated states, with the sheets they open.
//
//   DRIVALRY_LAYOUT=1 flutter test test/layout/layout_social_test.dart
//
// Opt-in like `layout_scenes_test.dart`: fonts come from the Flutter cache,
// which CI does not populate.
//
// The audit has no z-order. Three states would read as overlap or clipping
// although nothing is wrong, and each is handled here: a sheet opens over a
// blank page so only the sheet is measured; a scrolled page ignores overlap
// and checks the collapsed title's geometry itself; a swiped row ignores the
// clipping of its own content sliding off-screen.
import 'dart:async';
import 'dart:convert';

import 'package:drivalry/app/deep_links.dart';
import 'package:drivalry/app/ui/ui.dart';
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/repos/circles_repo.dart';
import 'package:drivalry/data/repos/circles_sync.dart';
import 'package:drivalry/data/repos/feed_repo.dart';
import 'package:drivalry/data/repos/friends_repo.dart';
import 'package:drivalry/data/repos/friends_sync.dart';
import 'package:drivalry/data/repos/places_repo.dart';
import 'package:drivalry/data/repos/presence_repo.dart';
import 'package:drivalry/data/supabase/supabase_providers.dart';
import 'package:drivalry/data/sync/outbox.dart';
import 'package:drivalry/features/circles/checkin_sheet.dart';
import 'package:drivalry/features/circles/circle_invite_sheet.dart';
import 'package:drivalry/features/circles/circle_screen.dart';
import 'package:drivalry/features/circles/circles_list_screen.dart';
import 'package:drivalry/features/circles/circles_view.dart';
import 'package:drivalry/features/friends/add_friend_screen.dart';
import 'package:drivalry/features/friends/feed_view.dart';
import 'package:drivalry/features/friends/friend_requests_screen.dart';
import 'package:drivalry/features/friends/friends_screen.dart';
import 'package:drivalry/features/friends/post_actions_sheet.dart';
import 'package:drivalry/features/friends/post_detail_screen.dart';
import 'package:drivalry/features/places/place_screen.dart';
import 'package:drivalry/features/places/places_screen.dart';
import 'package:drivalry/features/places/save_place_sheet.dart';
import 'package:drivalry/features/profile/profile_model.dart';
import 'package:drivalry/features/profile/profile_repo.dart';
import 'package:drivalry/features/profile/profile_screen.dart';
import 'package:drivalry/features/profile/sign_in_screen.dart';
import 'package:drivalry/tracking/providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../art/art_harness.dart';
import '../support/fake_tracking_port.dart';
import '../support/sqlite_support.dart';
import '../support/widget_support.dart';
import 'layout_audit.dart';

const _me = 'kai';
final int _nowMs = DateTime.now().millisecondsSinceEpoch;
final DateTime _now = DateTime.now().toUtc();

// ------------------------------------------------------------------ seeds --

FeedAuthor _author(String id, String name) =>
    FeedAuthor(id: id, handle: id, displayName: name);

const _roast =
    '41 in a 25 on Elm Street, for 90 seconds, to save 40 seconds. '
    'Everyone here can see this.';

/// Posts of both walls, a roast with components, a badge and a check-in.
List<FeedPost> _posts() => [
  FeedPost(
    id: 'post-priya-94',
    author: _author('priya', 'Priya Raman'),
    kind: 'trip',
    tripId: 'trip-priya-94',
    createdAt: _now.subtract(const Duration(hours: 2, minutes: 14)),
    body: const {
      'score': 94,
      'xp': 96,
      'reckless': false,
      'roast':
          'Butter smooth. 14 miles, zero events, and the phone stayed face '
          'down the whole way.',
      'tone': 'praise',
      'speeding': false,
    },
    reactions: const {'fire': 6, 'clap': 3},
    myReactions: const {'fire'},
    commentCount: 2,
  ),
  FeedPost(
    id: 'post-jordan-shame',
    author: _author('jordan', 'Jordan Lee'),
    kind: 'shame',
    tripId: 'trip-jordan-38',
    createdAt: _now.subtract(const Duration(hours: 3, minutes: 40)),
    body: const {
      'score': 38,
      'xp': 0,
      'reckless': true,
      'roast': _roast,
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
    author: _author('sam', 'Sam Okafor'),
    kind: 'trip',
    tripId: 'trip-sam-71',
    createdAt: _now.subtract(const Duration(hours: 5, minutes: 5)),
    body: const {
      'score': 71,
      'xp': 52,
      'reckless': false,
      'roast':
          'Two hard brakes and a yellow light you argued with. Decent, not '
          'clean.',
      'tone': 'roast',
      'components': {'smoothness': 18, 'speed': 11},
      'speeding': true,
    },
    reactions: const {'laugh': 3, 'clap': 1},
    commentCount: 1,
  ),
  FeedPost(
    id: 'post-alex-badge',
    author: _author('alex', 'Alex Nguyen'),
    kind: 'badge',
    createdAt: _now.subtract(const Duration(hours: 8, minutes: 30)),
    body: const {'badge_id': 'phone_free_10', 'badge_name': 'Hands Off'},
    reactions: const {'clap': 4, 'fire': 2},
  ),
  FeedPost(
    id: 'post-maya-home',
    author: _author('maya', 'Maya Chen'),
    kind: 'checkin',
    createdAt: _now.subtract(const Duration(hours: 26)),
    body: const {'label': 'Home'},
    reactions: const {'fire': 2},
  ),
];

List<FeedComment> _comments(String postId) => [
  FeedComment(
    id: 'c1',
    postId: postId,
    author: _author('sam', 'Sam Okafor'),
    body: 'Elm Street again. The speed bump is a hint, not a ramp.',
    createdAt: _now.subtract(const Duration(hours: 3)),
  ),
  FeedComment(
    id: 'c2',
    postId: postId,
    author: _author('priya', 'Priya Raman'),
    body: 'Forty seconds. Worth it?',
    createdAt: _now.subtract(const Duration(hours: 2, minutes: 50)),
  ),
  FeedComment(
    id: 'c3',
    postId: postId,
    author: _author('jordan', 'Jordan Lee'),
    body: 'I was late for a thing. The thing was a nap.',
    createdAt: _now.subtract(const Duration(hours: 1)),
  ),
];

Future<void> _seedFeed(AppDatabase db) => db.cachePut(
  FeedRepo.cacheKey(FeedFilter.all, 0),
  jsonEncode([for (final p in _posts()) p.toJson()]),
  _nowMs,
);

FriendProfile _friend(String id, String name, {double? rating}) =>
    FriendProfile(id: id, handle: id, displayName: name, driverRating: rating);

FriendRequest _request(FriendProfile other, FriendRequestDirection dir) {
  final incoming = dir == FriendRequestDirection.incoming;
  return FriendRequest(
    requesterId: incoming ? other.id : _me,
    addresseeId: incoming ? _me : other.id,
    other: other,
    direction: dir,
    createdAt: _now.subtract(const Duration(days: 1)),
  );
}

final _friends = FriendsSnapshot(
  friends: [
    _friend('priya', 'Priya Raman', rating: 94),
    _friend('jordan', 'Jordan Lee', rating: 38),
    _friend('sam', 'Sam Okafor'),
    _friend('maya', 'Maya Chen', rating: 88),
  ],
  incoming: [
    _request(_friend('alex', 'Alex Nguyen'), FriendRequestDirection.incoming),
    _request(
      _friend('taylor', 'Taylor Brooks-Whitfield'),
      FriendRequestDirection.incoming,
    ),
  ],
  outgoing: [
    _request(_friend('chris', 'Chris Park'), FriendRequestDirection.outgoing),
  ],
);

Future<void> _seedFriends(AppDatabase db) =>
    db.cachePut(FriendsRepo.cacheKey, jsonEncode(_friends.toJson()), _nowMs);

PresenceRow _presenceRow(String id, String name, {required bool driving}) =>
    PresenceRow(
      userId: id,
      handle: id,
      displayName: name,
      lat: 38.9,
      lon: -77.03,
      driving: driving,
      updatedAt: _now.subtract(Duration(minutes: driving ? 1 : 190)),
    );

final _presence = [
  _presenceRow('priya', 'Priya Raman', driving: true),
  _presenceRow('sam', 'Sam Okafor', driving: false),
];

Circle _circle(
  String id,
  String name, {
  required int members,
  required String code,
  bool hiding = false,
}) => Circle(
  id: id,
  name: name,
  createdBy: _me,
  inviteCode: code,
  createdAt: DateTime.utc(2026, 10, 1),
  memberCount: members,
  myHiding: hiding,
);

final _family = _circle('c-family', 'Family', members: 3, code: 'fam8k2qz');

CircleMember _member(String id, String name, {bool hiding = false}) =>
    CircleMember(
      userId: id,
      handle: id,
      displayName: name,
      hiding: hiding,
      joinedAt: DateTime.utc(2026, 10, 2),
    );

Future<void> _seedCircles(AppDatabase db) async {
  final family = [
    _member(_me, 'Kai Tanaka'),
    _member('priya', 'Priya Raman'),
    _member('jordan', 'Jordan Lee', hiding: true),
  ];
  final crew = [
    _member(_me, 'Kai Tanaka'),
    _member('sam', 'Sam Okafor'),
    _member('maya', 'Maya Chen'),
    _member('alex', 'Alex Nguyen'),
    _member('taylor', 'Taylor Brooks-Whitfield'),
  ];
  await db.cachePut(
    CirclesRepo.cacheKey,
    jsonEncode([
      _family.toJson(),
      _circle(
        'c-crew',
        'The Crew',
        members: 5,
        code: 'crew77ab',
        hiding: true,
      ).toJson(),
    ]),
    _nowMs,
  );
  await db.cachePut(
    CirclesRepo.membersKey('c-family'),
    jsonEncode([for (final m in family) m.toJson()]),
    _nowMs,
  );
  await db.cachePut(
    CirclesRepo.membersKey('c-crew'),
    jsonEncode([for (final m in crew) m.toJson()]),
    _nowMs,
  );
}

/// Home and Work; returns Home's id.
Future<String> _seedPlaces(AppDatabase db) async {
  final repo = PlacesRepo(db, now: () => _nowMs);
  final home = await repo.addPlace(
    label: 'Home',
    kind: PlaceKind.home,
    lat: 38.9,
    lon: -77.03,
    radiusM: 150,
  );
  await repo.addPlace(
    label: 'Work',
    kind: PlaceKind.work,
    lat: 38.95,
    lon: -77.1,
    radiusM: 200,
  );
  await repo.setAlert(home, 'priya', onArrive: true, onLeave: false);
  return home;
}

const _kai = Profile(
  id: _me,
  handle: 'kai',
  displayName: 'Kai Tanaka',
  driverRating: 86,
  passengerMarkedCount: 3,
);

const _priya = Profile(
  id: 'priya',
  handle: 'priya',
  displayName: 'Priya Raman',
  driverRating: 94,
  passengerMarkedCount: 1,
);

Future<void> _seedProfile(AppDatabase db, Profile p) =>
    db.cachePut(ProfileRepo.cacheKey(p.id), jsonEncode(p.toJson()), _nowMs);

Future<void> _seedBadges(AppDatabase db) async {
  await db.awardBadge('phone_free_10', _nowMs);
  await db.awardBadge('first_trip', _nowMs - 86400000 * 12);
  await db.awardBadge('night_owl', _nowMs - 86400000 * 30);
}

// ------------------------------------------------------------------ repos --

/// A feed whose network is the cache, so seeded pages stay on screen.
class _CachedFeedRepo extends FeedRepo {
  _CachedFeedRepo({
    required super.db,
    required super.outbox,
    required super.me,
    this.comments = const [],
  }) : super(clientOf: () => null);

  final List<FeedComment> comments;

  @override
  Future<List<FeedPost>> fetchPage(FeedFilter filter, int page) async =>
      await cachedPage(filter, page) ?? const [];

  @override
  Future<FeedPost?> fetchPost(String id) async {
    for (final p in await cachedPage(FeedFilter.all, 0) ?? const <FeedPost>[]) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Future<List<FeedComment>> fetchComments(String postId) async => [
    for (final c in comments)
      if (c.postId == postId) c,
  ];
}

/// Friends whose refresh returns the cache; `profile` answers from a map.
class _CachedFriendsRepo extends FriendsRepo {
  _CachedFriendsRepo({
    required super.db,
    required super.outbox,
    required super.me,
    this.profiles = const {},
  }) : super(clientOf: () => null);

  final Map<String, FriendProfile> profiles;

  @override
  Future<FriendsSnapshot> fetch() async =>
      await cached() ?? const FriendsSnapshot();

  @override
  Future<FriendProfile?> profile(String userId) async => profiles[userId];
}

/// Circles whose refresh returns the cache instead of an empty list.
class _CachedCirclesRepo extends CirclesRepo {
  _CachedCirclesRepo({
    required super.db,
    required super.outbox,
    required super.me,
  }) : super(apiOf: () => null);

  @override
  Future<List<Circle>> fetch() async => await cached() ?? const [];
}

// ----------------------------------------------------------------- scenes --

/// Per-test state: the database, the fake port, a navigator to push over
/// and a touch the scene may hold mid-gesture while the frame is captured.
class _Ctx {
  _Ctx(this.db, this.port);
  final AppDatabase db;
  final FakeTrackingPort port;
  final navigator = GlobalKey<NavigatorState>();
  TestGesture? held;
  String placeId = '';
}

Widget _app(
  _Ctx c,
  Widget home, {
  String? user = _me,
  ThemeMode mode = ThemeMode.dark,
  List<FeedComment> comments = const [],
  Map<String, FriendProfile> profiles = const {},
  List<PresenceRow> presence = const [],
}) => ProviderScope(
  overrides: [
    databaseProvider.overrideWithValue(c.db),
    trackingPortProvider.overrideWithValue(c.port),
    deepLinkSourceProvider.overrideWithValue(const NoDeepLinks()),
    currentUserIdProvider.overrideWithValue(user),
    cloudConfiguredProvider.overrideWithValue(true),
    feedRepoProvider.overrideWith(
      (ref) => _CachedFeedRepo(
        db: ref.watch(databaseProvider),
        outbox: ref.watch(outboxWorkerProvider),
        me: () => user,
        comments: comments,
      ),
    ),
    friendsRepoProvider.overrideWith(
      (ref) => _CachedFriendsRepo(
        db: ref.watch(databaseProvider),
        outbox: ref.watch(outboxWorkerProvider),
        me: () => user,
        profiles: profiles,
      ),
    ),
    circlesRepoProvider.overrideWith(
      (ref) => _CachedCirclesRepo(
        db: ref.watch(databaseProvider),
        outbox: ref.watch(outboxWorkerProvider),
        me: () => user,
      ),
    ),
    visiblePresenceProvider.overrideWith((ref) => Stream.value(presence)),
  ],
  child: MaterialApp(
    navigatorKey: c.navigator,
    theme: artTheme(Brightness.light),
    darkTheme: artTheme(),
    themeMode: mode,
    debugShowCheckedModeBanner: false,
    home: home,
  ),
);

class _Scene {
  const _Scene(
    this.name,
    this.build, {
    this.prepare,
    this.check,
    this.settle = const Duration(seconds: 2),
    this.platform,
    this.ignore = const {},
  });

  final String name;
  final Future<Widget> Function(_Ctx c) build;

  /// Runs after the first frames: switch tab, scroll, open a sheet.
  final Future<void> Function(WidgetTester t, _Ctx c)? prepare;

  /// Geometry the scene asserts itself, on top of the audit.
  final void Function(WidgetTester t, PhoneSize size)? check;
  final Duration settle;

  /// Set as `debugDefaultTargetPlatformOverride` for the scene.
  final TargetPlatform? platform;

  /// Issue kinds the audit cannot judge for this scene (see the file note).
  final Set<String> ignore;
}

Future<void> _tab(WidgetTester t, String label) async {
  await t.tap(find.widgetWithText(Tab, label));
  await pumpFor(t, const Duration(seconds: 1));
}

Future<void> _scroll(WidgetTester t, Finder list, double by) async {
  await t.drag(list, Offset(0, -by));
  await pumpFor(t, const Duration(milliseconds: 600));
}

/// Pushes a profile so the bar gets a back button. The push future completes
/// when the route pops, so it is not awaited.
Future<void> _pushProfile(WidgetTester t, _Ctx c, {String? userId}) async {
  unawaited(
    c.navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => ProfileScreen(userId: userId)),
    ),
  );
  await pumpFor(t, const Duration(seconds: 2));
}

/// A sheet over a blank page, opened through its public entry point.
_Scene _sheet(
  String name,
  void Function(BuildContext ctx, _Ctx c) open, {
  Future<void> Function(_Ctx c)? seed,
}) => _Scene(
  name,
  (c) async {
    await seed?.call(c);
    return _app(c, const Scaffold());
  },
  prepare: (t, c) async {
    open(t.element(find.byType(Scaffold)), c);
    await pumpFor(t, const Duration(seconds: 1));
  },
);

Rect _largeTitle(WidgetTester t) => t.getRect(
  find.descendant(of: find.byType(LargeTitle), matching: find.byType(Text)),
);

/// Expanded, the title must sit clear above the tab bar.
void _expectTitleClearsTabs(WidgetTester t, PhoneSize size) {
  final title = _largeTitle(t);
  final tabs = t.getRect(find.byType(TabBar));
  expect(
    tabs.top - title.bottom,
    greaterThanOrEqualTo(Space.sm),
    reason: 'title $title touches the tabs $tabs',
  );
}

/// Scrolled, the title must have shrunk into the toolbar row and, with a
/// back button in the bar, start clear of it.
void Function(WidgetTester, PhoneSize) _expectCollapsedTitle({
  bool leading = false,
}) => (t, size) {
  final title = _largeTitle(t);
  final toolbar = Rect.fromLTWH(0, size.top, size.width, kToolbarHeight);
  expect(
    title.top >= toolbar.top - 1 && title.bottom <= toolbar.bottom + 1,
    isTrue,
    reason: 'title $title is not inside the toolbar row $toolbar',
  );
  final clear = (leading ? kToolbarHeight : 0) + Space.gutter;
  expect(
    title.left,
    greaterThanOrEqualTo(clear - 1),
    reason: 'title $title does not clear the leading button ($clear)',
  );
};

/// The comment composer sits inside the screen, above the bottom inset.
void _expectComposerAtBottom(WidgetTester t, PhoneSize size) {
  final field = t.getRect(find.byType(TextField));
  final floor = size.height - size.bottom;
  expect(
    field.bottom,
    lessThanOrEqualTo(floor - Space.sm + 1),
    reason: '$field',
  );
  expect(field.bottom, greaterThan(floor - 80), reason: '$field');
}

/// Mid-swipe, the decline label must be revealed inside the gutter.
void _expectDeclineRevealed(WidgetTester t, PhoneSize size) {
  final label = t.getRect(find.text('Decline'));
  expect(label.left, greaterThan(size.width / 2), reason: '$label');
  expect(label.right, lessThanOrEqualTo(size.width - Space.gutter + 1));
}

final _scenes = <_Scene>[
  // Friends root: feed.
  _Scene('social-feed-empty', (c) async => _app(c, const FriendsScreen())),
  _Scene(
    'social-feed-posts',
    (c) async {
      await _seedFeed(c.db);
      return _app(c, const FriendsScreen());
    },
    settle: const Duration(seconds: 3),
    check: _expectTitleClearsTabs,
  ),
  _Scene(
    'social-feed-posts-scrolled',
    (c) async {
      await _seedFeed(c.db);
      return _app(c, const FriendsScreen());
    },
    settle: const Duration(seconds: 3),
    prepare: (t, c) => _scroll(t, find.byType(NestedScrollView), 200),
    check: _expectCollapsedTitle(),
    ignore: const {'overlap'},
  ),
  _Scene('social-feed-posts-light', (c) async {
    await _seedFeed(c.db);
    return _app(c, const FriendsScreen(), mode: ThemeMode.light);
  }, settle: const Duration(seconds: 3)),
  // Friends root: friends.
  _Scene(
    'social-friends-empty',
    (c) async => _app(c, const FriendsScreen()),
    prepare: (t, c) => _tab(t, 'Friends'),
  ),
  _Scene('social-friends-list', (c) async {
    await _seedFriends(c.db);
    return _app(c, const FriendsScreen(), presence: _presence);
  }, prepare: (t, c) => _tab(t, 'Friends')),
  // Friends root: circles.
  _Scene(
    'social-circles-empty',
    (c) async => _app(c, const FriendsScreen()),
    prepare: (t, c) => _tab(t, 'Circles'),
  ),
  _Scene('social-circles-list', (c) async {
    await _seedCircles(c.db);
    await _seedFriends(c.db);
    await _seedPlaces(c.db);
    return _app(c, const FriendsScreen(), presence: _presence);
  }, prepare: (t, c) => _tab(t, 'Circles')),
  // Requests.
  _Scene(
    'social-requests-empty',
    (c) async => _app(c, const FriendRequestsScreen()),
  ),
  _Scene('social-requests', (c) async {
    await _seedFriends(c.db);
    return _app(c, const FriendRequestsScreen());
  }),
  _Scene(
    'social-requests-swipe',
    (c) async {
      await _seedFriends(c.db);
      return _app(c, const FriendRequestsScreen());
    },
    prepare: (t, c) async {
      final g = c.held = await t.startGesture(
        t.getCenter(find.text('Alex Nguyen')),
      );
      await g.moveBy(const Offset(-30, 0));
      await t.pump();
      await g.moveBy(const Offset(-90, 0));
      await t.pump(const Duration(milliseconds: 100));
    },
    check: _expectDeclineRevealed,
    ignore: const {'clipped'},
  ),
  // Post detail, add friend.
  // Comments scroll out under the composer, which the audit reads as
  // overlap; the composer's own place is checked instead.
  _Scene(
    'social-post-detail',
    (c) async {
      await _seedFeed(c.db);
      return _app(
        c,
        const PostDetailScreen(postId: 'post-jordan-shame'),
        comments: _comments('post-jordan-shame'),
      );
    },
    check: _expectComposerAtBottom,
    ignore: const {'overlap'},
  ),
  _Scene('social-add-friend', (c) async {
    await _seedFriends(c.db);
    return _app(
      c,
      const AddFriendScreen(initialUserId: 'taylor'),
      profiles: {'taylor': _friend('taylor', 'Taylor Brooks-Whitfield')},
    );
  }),
  // Circles.
  _Scene(
    'social-circles-screen-empty',
    (c) async => _app(c, const CirclesListScreen()),
  ),
  _Scene('social-circles-screen', (c) async {
    await _seedCircles(c.db);
    await _seedPlaces(c.db);
    return _app(c, const CirclesListScreen(), presence: _presence);
  }),
  _Scene('social-circle', (c) async {
    await _seedCircles(c.db);
    return _app(
      c,
      const CircleScreen(circleId: 'c-family'),
      presence: _presence,
    );
  }),
  // Places.
  _Scene('social-places-empty', (c) async => _app(c, const PlacesScreen())),
  _Scene('social-places', (c) async {
    await _seedPlaces(c.db);
    return _app(c, const PlacesScreen());
  }),
  _Scene('social-place', (c) async {
    c.placeId = await _seedPlaces(c.db);
    await _seedFriends(c.db);
    return _app(c, PlaceScreen(placeId: c.placeId));
  }),
  // Profile.
  _Scene('social-profile-own', (c) async {
    await _seedProfile(c.db, _kai);
    await _seedBadges(c.db);
    return _app(c, const ProfileScreen());
  }),
  _Scene('social-profile-own-light', (c) async {
    await _seedProfile(c.db, _kai);
    await _seedBadges(c.db);
    return _app(c, const ProfileScreen(), mode: ThemeMode.light);
  }),
  _Scene('social-profile-other', (c) async {
    await _seedProfile(c.db, _priya);
    return _app(c, const Scaffold());
  }, prepare: (t, c) => _pushProfile(t, c, userId: 'priya')),
  // Another driver's page is too short to scroll, so the collapsed title
  // over a back button is checked on the own profile pushed the same way.
  _Scene(
    'social-profile-pushed-scrolled',
    (c) async {
      await _seedProfile(c.db, _kai);
      await _seedBadges(c.db);
      return _app(c, const Scaffold());
    },
    prepare: (t, c) async {
      await _pushProfile(t, c);
      await _scroll(t, find.byType(CustomScrollView), 200);
    },
    check: _expectCollapsedTitle(leading: true),
    ignore: const {'overlap'},
  ),
  // Sign-in.
  _Scene(
    'social-sign-in-android',
    (c) async => _app(
      c,
      const SignInScreen(cloudConfigured: true, googleConfigured: true),
      user: null,
    ),
    platform: TargetPlatform.android,
  ),
  _Scene(
    'social-sign-in-ios',
    (c) async => _app(
      c,
      const SignInScreen(cloudConfigured: true, googleConfigured: true),
      user: null,
    ),
    platform: TargetPlatform.iOS,
  ),
  // Sheets, each over a blank page.
  _sheet(
    'social-sheet-post-actions',
    (ctx, c) => showPostActions(ctx, post: _posts()[1], onReact: (_) {}),
  ),
  _sheet(
    'social-sheet-friend-picker',
    (ctx, c) => showFriendPickerSheet(ctx, _friends.friends),
  ),
  _sheet(
    'social-sheet-join-code',
    (ctx, c) => joinCircleByCode(ctx),
    seed: (c) => _seedCircles(c.db),
  ),
  _sheet(
    'social-sheet-invite',
    (ctx, c) => showCircleInviteSheet(ctx, _family),
    seed: (c) => _seedCircles(c.db),
  ),
  _sheet(
    'social-sheet-checkin',
    (ctx, c) => showCheckinSheet(ctx),
    seed: (c) async {
      await _seedCircles(c.db);
      await _seedPlaces(c.db);
    },
  ),
  _sheet(
    'social-sheet-save-place',
    (ctx, c) => showSavePlaceSheet(ctx, lat: 38.9, lon: -77.03),
  ),
  _sheet(
    'social-sheet-handle',
    (ctx, c) => showEditFieldSheet(
      ctx,
      title: 'Handle',
      initial: 'kai',
      hint: 'Lowercase letters, digits, underscores',
      validator: Profile.validateHandle,
    ),
  ),
  _sheet(
    'social-sheet-name',
    (ctx, c) => showEditFieldSheet(
      ctx,
      title: 'Name',
      initial: 'Kai Tanaka',
      hint: 'What friends see',
      validator: Profile.validateDisplayName,
    ),
  ),
];

void main() {
  setUpAll(() async {
    if (layoutShots) await loadArtFonts();
  });
  final sqliteSkip = skipWithoutSqlite();
  for (final scene in _scenes) {
    for (final size in phoneSizes) {
      testWidgets(
        '${scene.name} lays out on $size',
        (tester) async {
          final c = _Ctx(memoryDatabase(), FakeTrackingPort());
          debugDefaultTargetPlatformOverride = scene.platform;
          try {
            final app = await scene.build(c);
            final report = await auditLayout(
              tester,
              name: scene.name,
              app: app,
              size: size,
              settle: scene.settle,
              prepare: scene.prepare == null
                  ? null
                  : (t) => scene.prepare!(t, c),
            );
            scene.check?.call(tester, size);
            await c.held?.up();
            await pumpFor(tester, const Duration(milliseconds: 600));
            await unmountAndSettle(tester);
            final blocking = [
              for (final i in report.blocking)
                if (!scene.ignore.contains(i.kind)) i,
            ];
            expect(blocking, isEmpty, reason: report.summary());
          } finally {
            debugDefaultTargetPlatformOverride = null;
            await c.port.dispose();
            await c.db.close();
          }
        },
        skip: sqliteSkip != null || !layoutShots,
        timeout: const Timeout(Duration(minutes: 3)),
      );
    }
  }
}

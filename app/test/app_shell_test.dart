import 'dart:convert';

import 'package:drivalry/app/app.dart';
import 'package:drivalry/app/deep_links.dart';
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/repos/friends_repo.dart';
import 'package:drivalry/data/repos/friends_sync.dart';
import 'package:drivalry/data/supabase/supabase_providers.dart';
import 'package:drivalry/data/sync/outbox.dart';
import 'package:drivalry/features/drive/drive_screen.dart';
import 'package:drivalry/tracking/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_tracking_port.dart';
import 'support/sqlite_support.dart';
import 'support/widget_support.dart';

const _me = 'me-0000';

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

void main() {
  // testWidgets takes a bool; the reason is printed by the unit tests.
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

  testWidgets('shell shows five tabs and switches between them', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          trackingPortProvider.overrideWithValue(port),
          // Tests never talk to the app_links plugin.
          deepLinkSourceProvider.overrideWithValue(const NoDeepLinks()),
        ],
        child: const DrivalryApp(),
      ),
    );
    await pumpFor(tester, const Duration(seconds: 1));

    for (final label in ['Drive', 'Leagues', 'Friends', 'Convoy', 'Garage']) {
      expect(find.widgetWithText(NavigationDestination, label), findsOneWidget);
    }

    // Drive is the initial tab (map-first, no app bar of its own).
    expect(find.byType(DriveScreen), findsOneWidget);
    // Boot read the plugin state and drained the spool. Tests build without a
    // Maps key, so the key is never sent (see maps_ready_test.dart).
    expect(port.calls, containsAll(['getState', 'drainSpool']));
    expect(port.calls, isNot(contains('setMapsApiKey')));

    await tester.tap(find.widgetWithText(NavigationDestination, 'Convoy'));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.widgetWithText(AppBar, 'Convoy'), findsOneWidget);

    await tester.tap(find.widgetWithText(NavigationDestination, 'Garage'));
    await pumpFor(tester, const Duration(seconds: 1));
    // Garage uses a large collapsing title, which carries the text twice
    // (expanded and collapsed), so look for the sliver app bar instead.
    expect(
      find.descendant(
        of: find.byType(SliverAppBar),
        matching: find.text('Garage'),
      ),
      findsWidgets,
    );
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets('the Friends tab carries a dot while a request waits', (
    tester,
  ) async {
    final snapshot = FriendsSnapshot(
      incoming: [
        FriendRequest(
          requesterId: 'jordan',
          addresseeId: _me,
          other: const FriendProfile(
            id: 'jordan',
            handle: 'jordan',
            displayName: 'Jordan',
          ),
          direction: FriendRequestDirection.incoming,
          createdAt: DateTime.utc(2026, 11, 2),
        ),
      ],
    );
    await db.cachePut(
      FriendsRepo.cacheKey,
      jsonEncode(snapshot.toJson()),
      DateTime.now().millisecondsSinceEpoch,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          trackingPortProvider.overrideWithValue(port),
          deepLinkSourceProvider.overrideWithValue(const NoDeepLinks()),
          currentUserIdProvider.overrideWithValue(_me),
          friendsRepoProvider.overrideWith(
            (ref) => _CachedFriendsRepo(
              db: ref.watch(databaseProvider),
              outbox: ref.watch(outboxWorkerProvider),
              me: () => _me,
            ),
          ),
        ],
        child: const DrivalryApp(),
      ),
    );
    await pumpFor(tester, const Duration(seconds: 1));

    // Only one of icon/selectedIcon is in the tree, so one Badge per tab.
    Badge friendsDot() => tester.widget<Badge>(
      find.descendant(
        of: find.widgetWithText(NavigationDestination, 'Friends'),
        matching: find.byType(Badge),
      ),
    );
    expect(friendsDot().isLabelVisible, isTrue);
    // The other tabs never carry one.
    expect(
      find.descendant(
        of: find.widgetWithText(NavigationDestination, 'Drive'),
        matching: find.byType(Badge),
      ),
      findsNothing,
    );

    // Declining drops the request from the cache: the dot goes with it.
    await FriendsRepo(
      clientOf: () => null,
      db: db,
      outbox: OutboxWorker(db),
      me: () => _me,
    ).remove('jordan');
    await pumpFor(tester, const Duration(seconds: 1));
    expect(friendsDot().isLabelVisible, isFalse);
    await unmountAndSettle(tester);
  }, skip: skip);
}

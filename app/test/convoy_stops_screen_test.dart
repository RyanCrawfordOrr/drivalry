import 'package:drivalry/app/theme.dart';
import 'package:drivalry/app/ui/ui.dart';
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/google/places_client.dart' show StopCategory;
import 'package:drivalry/data/repos/convoy_repo.dart';
import 'package:drivalry/data/repos/convoy_sync.dart';
import 'package:drivalry/data/supabase/supabase_providers.dart';
import 'package:drivalry/data/sync/outbox.dart';
import 'package:drivalry/features/convoy/stops/convoy_stops_screen.dart';
import 'package:drivalry/tracking/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_tracking_port.dart';
import 'support/sqlite_support.dart';
import 'support/widget_support.dart';

/// The stops screen as a driving screen: 64-tall category tiles, 56 vote
/// buttons, the leader's Accept inline, and swipe-to-withdraw with Undo.
void main() {
  final skip = skipWithoutSqlite() != null;
  late AppDatabase db;
  late FakeTrackingPort port;
  late ConvoyRepo seed;

  setUp(() {
    Haptics.enabled = false;
    db = memoryDatabase();
    port = FakeTrackingPort();
    seed = ConvoyRepo(
      apiOf: () => null,
      db: db,
      outbox: OutboxWorker(db, now: () => 1),
      me: () => 'u1',
      now: () => 1_000_000,
    );
  });
  tearDown(() async {
    await port.dispose();
    await db.close();
  });

  Widget app({required bool leader}) => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      trackingPortProvider.overrideWithValue(port),
      currentUserIdProvider.overrideWithValue('u1'),
      amConvoyLeaderProvider.overrideWith((ref, id) => leader),
    ],
    child: MaterialApp(
      theme: DrivalryTheme.dark(),
      home: const ConvoyStopsScreen(convoyId: 'c1'),
    ),
  );

  testWidgets('category tiles and vote buttons are driving-sized', (
    tester,
  ) async {
    final id = await seed.proposeStop(
      'c1',
      category: StopCategory.gas,
      name: 'Summit Fuel',
      lat: 40,
      lon: -100,
    );
    await tester.pumpWidget(app(leader: false));
    await pumpFor(tester, const Duration(seconds: 1));
    final gas = find.byKey(const Key('stop-category-gas'));
    expect(tester.getSize(gas).height, Sizes.drivingTouch);
    expect(find.text('No stops yet.'), findsNothing);
    final up = find.byKey(Key('vote-up-$id'));
    expect(tester.getSize(up).height, Sizes.button);
    // My own proposal already carries my yes vote.
    expect(find.byIcon(Icons.thumb_up), findsOneWidget);
    expect(find.text('Gas · by you'), findsOneWidget);
    // Members never see the leader's actions.
    expect(find.byKey(Key('accept-$id')), findsNothing);
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets('the leader accepts a proposed stop inline', (tester) async {
    final id = await seed.proposeStop(
      'c1',
      category: StopCategory.food,
      name: 'Tacos',
      lat: 40,
      lon: -100,
    );
    await tester.pumpWidget(app(leader: true));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('PROPOSED'), findsOneWidget);
    final accept = find.byKey(Key('accept-$id'));
    expect(accept, findsOneWidget);
    expect(find.byKey(Key('reject-$id')), findsOneWidget);
    expect(tester.getSize(accept).height, Sizes.touch);
    expect(find.byType(PopupMenuButton<StopStatus>), findsNothing);

    await tester.tap(accept);
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('NEXT UP'), findsOneWidget);
    expect(find.text('PROPOSED'), findsNothing);
    expect(find.text('Food · by you · Accepted'), findsOneWidget);
    // The accepted stop offers Done and a way back.
    expect(find.byKey(Key('done-$id')), findsOneWidget);
    expect(find.byKey(Key('reopen-$id')), findsOneWidget);
    final stored = (await seed.cachedStops('c1'))!.single;
    expect(stored.status, StopStatus.accepted);
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets('without stops the screen says so', (tester) async {
    await tester.pumpWidget(app(leader: false));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('No stops yet.'), findsOneWidget);
    expect(
      find.text('Propose gas, food or a photo stop and the convoy votes.'),
      findsOneWidget,
    );
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets('swiping my proposal withdraws it and Undo brings it back', (
    tester,
  ) async {
    final id = await seed.proposeStop(
      'c1',
      category: StopCategory.photo,
      name: 'Eagle Point',
      lat: 40,
      lon: -100,
    );
    await tester.pumpWidget(app(leader: false));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('Eagle Point'), findsOneWidget);

    await tester.drag(find.byKey(Key('stop-$id')), const Offset(-600, 0));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.byKey(Key('stop-$id')), findsNothing);
    expect(find.text('Eagle Point withdrawn.'), findsOneWidget);
    expect(find.text('No stops yet.'), findsOneWidget);
    expect((await seed.cachedStops('c1'))!.single.status, StopStatus.rejected);

    await tester.tap(find.text('Undo'));
    await pumpFor(tester, const Duration(seconds: 2));
    expect(find.byKey(Key('stop-$id')), findsOneWidget);
    expect(find.text('PROPOSED'), findsOneWidget);
    expect((await seed.cachedStops('c1'))!.single.status, StopStatus.proposed);
    await unmountAndSettle(tester);
  }, skip: skip);
}

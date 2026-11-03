import 'package:drift/drift.dart' show Value;
import 'package:drivalry/app/deep_links.dart';
import 'package:drivalry/app/router.dart';
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/google/places_client.dart' show StopCategory;
import 'package:drivalry/data/repos/convoy_repo.dart';
import 'package:drivalry/data/sync/outbox.dart';
import 'package:drivalry/features/convoy/convoy_screen.dart';
import 'package:drivalry/features/convoy/create_convoy_screen.dart';
import 'package:drivalry/features/convoy/expenses/convoy_expenses_screen.dart';
import 'package:drivalry/features/convoy/join_convoy_screen.dart';
import 'package:drivalry/features/convoy/recap/convoy_recap_screen.dart';
import 'package:drivalry/features/convoy/stops/convoy_stops_screen.dart';
import 'package:drivalry/tracking/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_tracking_port.dart';
import 'support/sqlite_support.dart';
import 'support/widget_support.dart';

void main() {
  final skip = skipWithoutSqlite() != null;
  late AppDatabase db;
  late FakeTrackingPort port;
  late ConvoyRepo seed;
  setUp(() {
    db = memoryDatabase();
    port = FakeTrackingPort();
    // Seeds the local cache the way a signed-in session would have.
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

  Widget wrap(Widget child) => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      trackingPortProvider.overrideWithValue(port),
      deepLinkSourceProvider.overrideWithValue(const NoDeepLinks()),
    ],
    child: MaterialApp(home: child),
  );

  testWidgets('convoy tab explains itself without a cloud project', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const ConvoyScreen()));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.widgetWithText(AppBar, 'Convoy'), findsOneWidget);
    expect(find.text('Not available in this version yet.'), findsOneWidget);
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets('convoy invite link lands on the join screen', (tester) async {
    await tester.pumpWidget(wrap(const JoinConvoyScreen(code: 'abc12345')));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.widgetWithText(AppBar, 'Convoy invite'), findsOneWidget);
    expect(find.text('Not available in this version yet.'), findsOneWidget);
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets('create screen renders its form', (tester) async {
    await tester.pumpWidget(wrap(const CreateConvoyScreen()));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.widgetWithText(AppBar, 'New convoy'), findsOneWidget);
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets('stops screen lists cached stops with their votes', (
    tester,
  ) async {
    await seed.proposeStop(
      'c1',
      category: StopCategory.food,
      name: 'Tacos',
      lat: 40,
      lon: -100,
    );
    await tester.pumpWidget(wrap(const ConvoyStopsScreen(convoyId: 'c1')));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('Tacos'), findsOneWidget);
    expect(find.text('PROPOSED'), findsOneWidget);
    expect(find.byIcon(Icons.thumb_up), findsNothing); // me is null here
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets('expenses screen shows totals and the settle-up', (tester) async {
    await seed.addExpense('c1', amountCents: 4500, category: 'gas');
    await tester.pumpWidget(wrap(const ConvoyExpensesScreen(convoyId: 'c1')));
    await pumpFor(tester, const Duration(seconds: 1));
    // The hero total and the expense row.
    expect(find.text('TOTAL'), findsOneWidget);
    expect(find.text(r'$45.00'), findsNWidgets(2));
    // Only the payer is known as a participant: nothing to settle.
    expect(find.text('All square.'), findsOneWidget);
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets('expenses in two currencies get their own totals and splits', (
    tester,
  ) async {
    await seed.addExpense('c1', amountCents: 4500, category: 'gas');
    await seed.addExpense(
      'c1',
      amountCents: 2000,
      category: 'food',
      currency: 'EUR',
      payerId: 'u2',
    );
    await tester.pumpWidget(wrap(const ConvoyExpensesScreen(convoyId: 'c1')));
    await pumpFor(tester, const Duration(seconds: 1));
    // One hero figure per currency plus its expense row.
    expect(find.text(r'$45.00'), findsNWidgets(2));
    expect(find.text('20.00 EUR'), findsNWidgets(2));
    expect(find.text(r'$65.00'), findsNothing, reason: 'never summed');
    expect(find.textContaining(r'10.00 EUR + $22.50 each'), findsOneWidget);
    // Two payers, two currencies: one transfer each way, never netted.
    expect(find.text('Someone → someone'), findsNWidgets(2));
    expect(find.text(r'$22.50'), findsOneWidget);
    expect(find.text('10.00 EUR'), findsOneWidget);
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets('a recap built right after the end waits for summaries', (
    tester,
  ) async {
    final fresh = ConvoyRepo(
      apiOf: () => null,
      db: db,
      outbox: OutboxWorker(db, now: () => 1),
      me: () => 'u1',
      now: () => DateTime.now().millisecondsSinceEpoch,
    );
    final id = await fresh.create('Night run');
    await fresh.setStatus(id, ConvoyStatus.ended);
    await tester.pumpWidget(wrap(ConvoyRecapScreen(convoyId: id)));
    await pumpFor(tester, const Duration(seconds: 2));
    expect(find.text('Night run'), findsOneWidget);
    // No member summaries yet and the end was seconds ago: not stored as
    // final, so the next open rebuilds it with whatever has uploaded.
    final local = await db.convoyLocalFor(id);
    expect(local?.recapJson, isNull);
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets('recap builds from local tracks and the cached convoy', (
    tester,
  ) async {
    final id = await seed.create('Coast run');
    await seed.setStatus(id, ConvoyStatus.ended);
    for (var i = 0; i < 5; i++) {
      await db.insertConvoyTrack(
        ConvoyTracksCompanion(
          convoyId: Value(id),
          userId: const Value('u1'),
          t: Value(1_000_000 + i * 10_000),
          lat: Value(40.0 + i * 0.01),
          lon: const Value(-100.0),
        ),
      );
    }
    await tester.pumpWidget(wrap(ConvoyRecapScreen(convoyId: id)));
    await pumpFor(tester, const Duration(seconds: 2));
    expect(find.text('Coast run'), findsOneWidget);
    expect(find.textContaining('2.8 mi'), findsOneWidget);
    // The replay button sits at the bottom of the map, just under the fold.
    await tester.drag(find.byType(ListView), const Offset(0, -240));
    await tester.pump();
    await tester.tap(find.byKey(const Key('replay')));
    await pumpFor(tester, const Duration(seconds: 9));
    // Awards sit below the replay; scroll them into view.
    await tester.scrollUntilVisible(
      find.text('Navigator'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Navigator'), findsOneWidget);
    // The recap of an ended convoy is stored for next time.
    final local = await db.convoyLocalFor(id);
    expect(local?.recapJson, isNotNull);
    await unmountAndSettle(tester);
  }, skip: skip);

  test('convoy routes are registered', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final router = container.read(routerProvider);
    for (final path in [
      Routes.convoy,
      Routes.createConvoy,
      Routes.convoyDetail('c1'),
      Routes.convoyRadio('c1'),
      Routes.convoyStops('c1'),
      Routes.convoyChat('c1'),
      Routes.convoyMusic('c1'),
      Routes.convoyGames('c1'),
      Routes.convoyExpenses('c1'),
      Routes.convoyAlbum('c1'),
      Routes.convoyRecap('c1'),
      Routes.joinConvoy('abc'),
    ]) {
      final match = router.configuration.findMatch(Uri.parse(path));
      expect(match.isError, isFalse, reason: path);
      expect(match.matches, isNotEmpty, reason: path);
    }
  });
}

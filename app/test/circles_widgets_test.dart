import 'package:drivalry/app/deep_links.dart';
import 'package:drivalry/app/router.dart';
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/repos/places_repo.dart';
import 'package:drivalry/features/circles/circles_list_screen.dart';
import 'package:drivalry/features/circles/circles_view.dart';
import 'package:drivalry/features/friends/join_circle_screen.dart';
import 'package:drivalry/features/places/places_screen.dart';
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
  setUp(() {
    db = memoryDatabase();
    port = FakeTrackingPort();
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

  testWidgets('circles list explains itself without a cloud project', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const CirclesListScreen()));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.widgetWithText(AppBar, 'Circles'), findsOneWidget);
    // Signed out / offline: the scope notice, never the circles list.
    expect(find.byType(CirclesView), findsNothing);
    expect(find.text('Not available in this version yet.'), findsOneWidget);
    expect(find.text('I got home'), findsNothing);
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets('circle invite link lands on the join screen', (tester) async {
    await tester.pumpWidget(wrap(const JoinCircleScreen(code: 'abc12345')));
    await pumpFor(tester, const Duration(seconds: 1));
    // Signed out / offline: the scope notice, never the router error page.
    expect(find.byType(JoinCircleScreen), findsOneWidget);
    expect(find.text('Join this circle?'), findsNothing);
    expect(find.text('Not available in this version yet.'), findsOneWidget);
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets('places screen lists saved places from the phone', (
    tester,
  ) async {
    await PlacesRepo(
      db,
      now: () => 1,
    ).addPlace(label: 'Home', kind: PlaceKind.home, lat: 38.9, lon: -77.03);
    await tester.pumpWidget(wrap(const PlacesScreen()));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('Home'), findsOneWidget);
    // 150 m, or about 490 ft for people whose speeds are in mph.
    expect(find.textContaining(RegExp(r'150 m|490 ft')), findsOneWidget);
    // With places on screen the action is an app-bar icon, never a floating
    // button over a tile.
    expect(find.byTooltip('Add where I am'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    await unmountAndSettle(tester);
  }, skip: skip);

  test('circle and place routes are registered', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final router = container.read(routerProvider);
    for (final path in [
      Routes.circles,
      Routes.createCircle,
      Routes.circle('c1'),
      Routes.places,
      Routes.place('p1'),
      Routes.joinCircle('abc'),
    ]) {
      final match = router.configuration.findMatch(Uri.parse(path));
      expect(match.isError, isFalse, reason: path);
      expect(match.matches, isNotEmpty, reason: path);
    }
  });
}

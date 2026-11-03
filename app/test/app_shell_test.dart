import 'package:drivalry/app/app.dart';
import 'package:drivalry/app/deep_links.dart';
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/features/drive/drive_screen.dart';
import 'package:drivalry/tracking/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_tracking_port.dart';
import 'support/sqlite_support.dart';
import 'support/widget_support.dart';

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
    expect(find.widgetWithText(AppBar, 'Garage'), findsOneWidget);
    await unmountAndSettle(tester);
  }, skip: skip);
}

import 'package:drift/drift.dart' show Value;
import 'package:drivalry/app/ui/ui.dart';
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/garage/vehicle_matcher.dart';
import 'package:drivalry/features/garage/garage_screen.dart';
import 'package:drivalry/tracking/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_tracking_port.dart';
import 'support/sqlite_support.dart';
import 'support/widget_support.dart';

Widget harness(AppDatabase db, FakeTrackingPort port) => ProviderScope(
  overrides: [
    databaseProvider.overrideWithValue(db),
    trackingPortProvider.overrideWithValue(port),
  ],
  child: const MaterialApp(home: GarageScreen()),
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

  testWidgets('empty garage is one headline and one button', (tester) async {
    await tester.pumpWidget(harness(db, port));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('GARAGE'), findsOneWidget);
    expect(find.text('Add your car.'), findsOneWidget);
    expect(
      find.text(
        'Trips get credited to it, and the app can spot its Bluetooth.',
      ),
      findsOneWidget,
    );
    // The one action is the empty state's button; no FAB doubles it.
    expect(find.widgetWithText(FilledButton, 'Add vehicle'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets('vehicles are tiles with one caption line and a pill', (
    tester,
  ) async {
    await db.upsertVehicle(
      VehiclesCompanion.insert(
        id: 'v1',
        name: 'Mazda',
        make: const Value('Mazda'),
        model: const Value('CX-5'),
        year: const Value(2021),
        createdAt: 1,
      ),
    );
    await db.upsertVehicle(
      VehiclesCompanion.insert(
        id: 'v2',
        name: 'Work truck',
        neverTrack: const Value(true),
        createdAt: 2,
      ),
    );
    await db.setSetting(
      VehicleMatcher.ignoredNamesKey,
      VehicleMatcher.encodeNames(['Dad Camry']),
    );
    await tester.pumpWidget(harness(db, port));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.byType(EmptyState), findsNothing);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('Mazda'), findsOneWidget);
    expect(find.textContaining('2021 Mazda CX-5'), findsOneWidget);
    expect(find.textContaining('No trips yet'), findsNWidgets(2));
    expect(find.text('Work truck'), findsOneWidget);
    expect(find.widgetWithText(Pill, 'Never tracked'), findsOneWidget);
    expect(find.text('CARS YOU RIDE IN'), findsOneWidget);
    expect(find.text('Dad Camry'), findsOneWidget);
    expect(find.text('Ignored car audio'), findsNothing);
    await unmountAndSettle(tester);
  }, skip: skip);
}

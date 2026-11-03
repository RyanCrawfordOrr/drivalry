import 'dart:io';

import 'package:drivalry/app/ui/ui.dart';
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/garage/documents.dart';
import 'package:drivalry/data/repos/garage_repo.dart';
import 'package:drivalry/features/garage/tabs/fuel_tab.dart';
import 'package:drivalry/tracking/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_tracking_port.dart';
import 'support/sqlite_support.dart';
import 'support/widget_support.dart';

/// Direct manipulation on the garage logs (docs/12 §5b): a row swipes away,
/// the list cross-fades to its empty state, and Undo brings the row back.
void main() {
  final skip = skipWithoutSqlite() != null;
  late AppDatabase db;
  late FakeTrackingPort port;
  late GarageRepo repo;

  setUp(() {
    db = memoryDatabase();
    port = FakeTrackingPort();
    repo = GarageRepo(
      db,
      DocumentVault(InMemoryVaultKeyStore()),
      () async => Directory.systemTemp,
      now: () => 1_000,
    );
  });
  tearDown(() async {
    await port.dispose();
    await db.close();
  });

  Widget harness(Vehicle v) => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      trackingPortProvider.overrideWithValue(port),
      garageRepoProvider.overrideWithValue(repo),
    ],
    child: MaterialApp(
      home: Scaffold(body: FuelTab(vehicle: v)),
    ),
  );

  // The SnackBar wraps itself in a Dismissible, so look inside the tab only.
  Finder rows() => find.descendant(
    of: find.byType(FuelTab),
    matching: find.byType(Dismissible),
  );

  testWidgets('swiping a fill-up away removes it and Undo brings it back', (
    tester,
  ) async {
    await db.upsertVehicle(
      VehiclesCompanion.insert(id: 'v1', name: 'Mazda', createdAt: 1),
    );
    await repo.addFuelEntry(
      vehicleId: 'v1',
      litres: 40,
      odometerKm: 1000,
      costCents: 6000,
      fullTank: true,
    );
    final v = (await db.vehicleById('v1'))!;
    await tester.pumpWidget(harness(v));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(rows(), findsOneWidget);
    expect(find.byType(EmptyState), findsNothing);
    expect(find.byType(FloatingActionButton), findsOneWidget);

    await tester.drag(rows(), const Offset(-600, 0));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(await db.fuelEntriesFor('v1'), isEmpty);
    expect(rows(), findsNothing);
    expect(find.text('Log your first fill-up.'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await pumpFor(tester, const Duration(seconds: 1));
    expect((await db.fuelEntriesFor('v1')).length, 1);
    expect(rows(), findsOneWidget);
    expect(find.byType(EmptyState), findsNothing);
    expect(tester.takeException(), isNull);
    await unmountAndSettle(tester);
  }, skip: skip);
}

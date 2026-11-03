import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/garage/documents.dart';
import 'package:drivalry/data/garage/vehicle_matcher.dart';
import 'package:drivalry/data/models/trip_phase.dart';
import 'package:drivalry/data/repos/garage_repo.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sqlite_support.dart';

Future<void> scoredTrip(
  AppDatabase db,
  String id, {
  String? vehicleId,
  int startedAt = 1000,
  bool passenger = false,
}) async {
  await db.ensureTrip(
    TripsCompanion.insert(
      id: id,
      startedAt: startedAt,
      phase: TripPhase.scored.wire,
      createdAt: startedAt,
      endedAt: Value(startedAt + 600_000),
      distanceM: const Value(5000),
      isPassenger: Value(passenger),
      vehicleId: Value(vehicleId),
      vehicleLabel: Value(vehicleId == null ? null : 'Car'),
    ),
  );
  await db.upsertScore(
    TripScoresCompanion.insert(
      tripId: id,
      scoreJson: '{}',
      score: const Value(88),
      xp: 50,
      reckless: false,
      scored: true,
      scoredAt: startedAt + 600_000,
    ),
  );
}

void main() {
  final skip = skipWithoutSqlite();

  test(
    'accepting the vehicle prompt credits the trip and re-scores it',
    () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final refinalized = <String>[];
      final repo = GarageRepo(
        db,
        DocumentVault(InMemoryVaultKeyStore()),
        () async => Directory.systemTemp,
        now: () => 1,
        refinalize: (id) async => refinalized.add(id),
      );
      await scoredTrip(db, 't1', passenger: true);
      await db.setPassengerHint('t1', true);

      final v = await repo.acceptPrompt(
        const VehiclePrompt(tripId: 't1', name: 'Dad Camry'),
      );

      final trip = (await db.tripById('t1'))!;
      expect(trip.vehicleId, v.id);
      expect(trip.vehicleLabel, v.name);
      expect(trip.isPassenger, isFalse, reason: 'it is the user\'s car');
      expect(trip.passengerHint, isFalse);
      expect(refinalized, ['t1'], reason: 'scored again as a driver trip');
      expect(await db.getSetting(VehiclePrompt.settingKey), '');
    },
    skip: skip,
  );

  test('vehicle stats recompute when a trip is scored', () async {
    final db = memoryDatabase();
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        documentVaultProvider.overrideWithValue(
          DocumentVault(InMemoryVaultKeyStore()),
        ),
        documentsDirProvider.overrideWithValue(
          () async => Directory.systemTemp,
        ),
      ],
    );
    addTearDown(container.dispose);
    await db.upsertVehicle(
      VehiclesCompanion.insert(id: 'v1', name: 'Mazda', createdAt: 1),
    );
    final sub = container.listen(vehicleStatsProvider('v1'), (_, _) {});
    addTearDown(sub.close);
    expect((await container.read(vehicleStatsProvider('v1').future)).trips, 0);

    await scoredTrip(db, 't1', vehicleId: 'v1');

    // The trips stream emits, the stats provider re-runs; no restart needed.
    var trips = 0;
    for (var i = 0; i < 40 && trips == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      trips = (await container.read(vehicleStatsProvider('v1').future)).trips;
    }
    expect(trips, 1);
  }, skip: skip);
}

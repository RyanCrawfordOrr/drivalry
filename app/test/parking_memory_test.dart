import 'package:drift/drift.dart' show Value;
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/models/trip_phase.dart';
import 'package:drivalry/features/drive/parking/parking_memory.dart';
import 'package:drivalry/tracking/tracking_models.dart';
import 'package:drivalry/widgets/relative_time.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sqlite_support.dart';

Future<void> endedTrip(
  AppDatabase db,
  String id, {
  required int endedAt,
  List<(double, double)> points = const [(38.9, -77.03), (38.91, -77.02)],
}) async {
  await db.ensureTrip(
    TripsCompanion.insert(
      id: id,
      startedAt: endedAt - 60_000,
      phase: TripPhase.scored.wire,
      createdAt: endedAt - 60_000,
      endedAt: Value(endedAt),
    ),
  );
  var t = endedAt - 60_000;
  await db.insertFixBatch(id, endedAt, [
    for (final (lat, lon) in points)
      SamplesCompanion.insert(
        tripId: id,
        t: t += 1000,
        lat: lat,
        lon: lon,
        accuracy: 7,
      ),
  ]);
}

void main() {
  final skip = skipWithoutSqlite();

  group('ParkingMemory', () {
    late AppDatabase db;
    late ParkingMemory memory;
    setUp(() {
      db = memoryDatabase();
      memory = ParkingMemory(db);
    });
    tearDown(() => db.close());

    test('records the last fix once when a trip ends', () async {
      await endedTrip(db, 't1', endedAt: 100_000);
      await memory.handle(
        const PhaseEvent(
          tripId: 't1',
          t: 100_000,
          phase: TripPhaseSignal.ended,
        ),
      );
      final spot = (await db.parkingSpotFor('t1'))!;
      expect(spot.lat, 38.91);
      expect(spot.lon, -77.02);
      expect(spot.accuracy, 7);
      expect(await memory.recordSpot('t1'), isFalse, reason: 'already there');
    });

    test('a trip without samples records nothing', () async {
      await db.ensureTrip(
        TripsCompanion.insert(
          id: 'empty',
          startedAt: 1,
          phase: TripPhase.unscored.wire,
          createdAt: 1,
          endedAt: const Value(2),
        ),
      );
      expect(await memory.recordSpot('empty'), isFalse);
    });

    test('catch-up covers a trip that ended while the app was dead', () async {
      await endedTrip(db, 'old', endedAt: 50_000);
      await endedTrip(db, 'new', endedAt: 90_000);
      await memory.catchUp();
      expect(await db.parkingSpotFor('new'), isNotNull);
      expect(await db.parkingSpotFor('old'), isNull, reason: 'only the newest');
    });

    test('latest spot follows the newest non-deleted trip', () async {
      await endedTrip(db, 'a', endedAt: 10_000);
      await endedTrip(db, 'b', endedAt: 20_000);
      await memory.recordSpot('a');
      await memory.recordSpot('b');
      expect((await db.watchLatestParkingSpot().first)!.tripId, 'b');
      await db.softDeleteTrip('b', 30_000);
      expect((await db.watchLatestParkingSpot().first)!.tripId, 'a');
      await memory.forget('a');
      expect(await db.watchLatestParkingSpot().first, isNull);
    });

    test('forget sticks across the boot-time catch-up', () async {
      await endedTrip(db, 'f1', endedAt: 100_000);
      await memory.recordSpot('f1');
      await memory.forget('f1');
      await memory.catchUp();
      expect(await db.parkingSpotFor('f1'), isNull);
      expect(await memory.recordSpot('f1'), isFalse);
      expect(await db.watchLatestParkingSpot().first, isNull);
    });

    test(
      'a soft-deleted trip records no spot; a hard delete removes one',
      () async {
        await endedTrip(db, 'd1', endedAt: 100_000);
        await db.softDeleteTrip('d1', 100_500);
        expect(await memory.recordSpot('d1'), isFalse);
        await endedTrip(db, 'd2', endedAt: 200_000);
        expect(await memory.recordSpot('d2'), isTrue);
        await db.deleteTripHard('d2');
        expect(await db.parkingSpotFor('d2'), isNull);
      },
    );

    test('note and photo updates', () async {
      await endedTrip(db, 'n', endedAt: 10_000);
      await memory.recordSpot('n');
      await memory.setNote('n', 'Level 3');
      await memory.setPhoto('n', '/tmp/x.jpg');
      final spot = (await db.parkingSpotFor('n'))!;
      expect(spot.note, 'Level 3');
      expect(spot.photoPath, '/tmp/x.jpg');
      await memory.setNote('n', '');
      expect((await db.parkingSpotFor('n'))!.note, isNull);
    });
  }, skip: skip);

  test('card time text', () {
    final now = DateTime(2026, 11, 3, 12, 0);
    expect(
      relativeTime(now.subtract(const Duration(minutes: 12)), now),
      '12 min ago',
    );
    expect(
      relativeTime(now.subtract(const Duration(hours: 3)), now),
      '3 h ago',
    );
  });
}

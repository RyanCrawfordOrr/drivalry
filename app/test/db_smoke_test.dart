import 'package:drift/drift.dart' show Value;
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/models/trip_phase.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sqlite_support.dart';

void main() {
  final skip = skipWithoutSqlite();

  test('schema creates and a trip round-trips', () async {
    final db = memoryDatabase();
    addTearDown(db.close);

    await db.ensureTrip(
      TripsCompanion.insert(
        id: 't1',
        startedAt: 1000,
        phase: TripPhase.recording.wire,
        createdAt: 1000,
      ),
    );
    final inserted = await db.insertFixBatch('t1', 2000, [
      SamplesCompanion.insert(
        tripId: 't1',
        t: 1000,
        lat: 1,
        lon: 2,
        accuracy: 5,
      ),
      SamplesCompanion.insert(
        tripId: 't1',
        t: 2000,
        lat: 1,
        lon: 2,
        accuracy: 5,
      ),
    ]);
    expect(inserted, isTrue);
    expect(await db.insertFixBatch('t1', 2000, const []), isFalse);
    expect(await db.sampleCount('t1'), 2);

    final counts = await db.tableCounts();
    expect(counts['trips'], 1);
    expect(counts['samples'], 2);
  }, skip: skip);

  test(
    'watchUnansweredTrips asks only about scored or about-to-be-scored trips',
    () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      Future<void> seed(String id, TripPhase phase, {int? deletedAt}) =>
          db.ensureTrip(
            TripsCompanion.insert(
              id: id,
              startedAt: 1000,
              phase: phase.wire,
              createdAt: 1000,
              deletedAt: Value(deletedAt),
            ),
          );
      await seed('scored', TripPhase.scored);
      await seed('pending', TripPhase.pendingPassenger);
      await seed('short', TripPhase.unscored);
      await seed('recording', TripPhase.recording);
      await seed('gone', TripPhase.scored, deletedAt: 5000);

      final asked = await db.watchUnansweredTrips().first;
      expect(asked.map((t) => t.id).toSet(), {'scored', 'pending'});
    },
    skip: skip,
  );
}

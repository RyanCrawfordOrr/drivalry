import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drivalry/data/db/database.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scored_trips.dart';
import 'support/sqlite_support.dart';

/// The per-trip aggregates the stats engine is fed from (schema 5): computed
/// once per trip, stored on the row, backfilled for older rows.
void main() {
  final skip = skipWithoutSqlite() != null;
  late AppDatabase db;
  setUp(() => db = memoryDatabase());
  tearDown(() => db.close());

  Future<void> seed(
    String id,
    int startedAt,
    List<(double, double, double?)> fixes,
  ) async {
    await seedScoredTrip(db, id: id, startedAt: startedAt);
    await db.insertFixBatch(id, startedAt, [
      for (var i = 0; i < fixes.length; i++)
        SamplesCompanion.insert(
          tripId: id,
          t: startedAt + i * 1000,
          lat: fixes[i].$1,
          lon: fixes[i].$2,
          accuracy: 5,
          altitude: Value(fixes[i].$3),
        ),
    ]);
  }

  Future<void> seg(String trip, String? name, int from) => db
      .into(db.segments)
      .insert(
        SegmentsCompanion.insert(
          tripId: trip,
          fromIdx: from,
          toIdx: from + 1,
          confidence: 0.9,
          roadClass: 'residential',
          name: Value(name),
        ),
      );

  test(
    'tripExtentFor gives the bounding box and the highest altitude',
    () async {
      await seed('a', 1000, [
        (36.1, -86.8, 150),
        (36.3, -86.6, 420.5),
        (36.2, -86.9, null),
      ]);
      await seed('b', 2000, [(40.0, -75.0, null)]);
      final a = (await db.tripExtentFor('a'))!;
      expect(a.minLat, 36.1);
      expect(a.maxLat, 36.3);
      expect(a.minLon, -86.9);
      expect(a.maxLon, -86.6);
      expect(a.maxAltitudeM, 420.5);
      expect((await db.tripExtentFor('b'))!.maxAltitudeM, isNull);
      expect(await db.tripExtentFor('nope'), isNull);
    },
    skip: skip,
  );

  test('tripEndpointsFor returns the first and last fix', () async {
    await seed('a', 1000, [
      (36.1, -86.8, null),
      (36.2, -86.7, null),
      (36.3, -86.6, null),
    ]);
    await seed('b', 2000, [(40.0, -75.0, null)]);
    final a = (await db.tripEndpointsFor('a'))!;
    expect((a.startLat, a.startLon), (36.1, -86.8));
    expect((a.endLat, a.endLon), (36.3, -86.6));
    final b = (await db.tripEndpointsFor('b'))!;
    expect(
      (b.startLat, b.startLon, b.endLat, b.endLon),
      (40.0, -75.0, 40.0, -75.0),
    );
    expect(await db.tripEndpointsFor('nope'), isNull);
  }, skip: skip);

  test('roadNamesFor lists each named road once', () async {
    await seedScoredTrip(db, id: 'a', startedAt: 1000);
    await seg('a', 'Broadway', 0);
    await seg('a', 'Broadway', 1);
    await seg('a', 'I-40', 2);
    await seg('a', null, 3);
    await seg('a', '', 4);
    expect(await db.roadNamesFor('a'), {'Broadway', 'I-40'});
    expect(await db.roadNamesFor('nope'), isEmpty);
  }, skip: skip);

  test('computeTripStats stores the aggregates on the row', () async {
    await seed('a', 1000, [(36.1, -86.8, 150), (36.3, -86.6, 420.5)]);
    await seg('a', 'Broadway', 0);
    await db.computeTripStats('a', 777);
    final t = (await db.tripById('a'))!;
    expect(t.statsAt, 777);
    final e = TripExtent.of(t)!;
    expect(
      (e.minLat, e.maxLat, e.minLon, e.maxLon, e.maxAltitudeM),
      (36.1, 36.3, -86.8, -86.6, 420.5),
    );
    final p = TripEndpoints.of(t)!;
    expect(
      (p.startLat, p.startLon, p.endLat, p.endLon),
      (36.1, -86.8, 36.3, -86.6),
    );
    expect(tripRoadNames(t), {'Broadway'});
    expect(jsonDecode(t.roadNames!), ['Broadway']);
  }, skip: skip);

  test(
    'a trip without samples is still marked done, with nothing to read',
    () async {
      await seedScoredTrip(db, id: 'old', startedAt: 1000);
      await db.computeTripStats('old', 5);
      final t = (await db.tripById('old'))!;
      expect(t.statsAt, 5);
      expect(TripExtent.of(t), isNull);
      expect(TripEndpoints.of(t), isNull);
      expect(tripRoadNames(t), isEmpty);
    },
    skip: skip,
  );

  test(
    'tripsNeedingStats lists ended rows not yet computed, oldest first',
    () async {
      await seedScoredTrip(db, id: 'b', startedAt: 2000);
      await seedScoredTrip(db, id: 'a', startedAt: 1000);
      // Still recording: not a candidate.
      await db.ensureTrip(
        TripsCompanion.insert(
          id: 'live',
          startedAt: 3000,
          phase: 'recording',
          createdAt: 3000,
        ),
      );
      expect(await db.tripsNeedingStats(), ['a', 'b']);
      expect(await db.tripsNeedingStats(limit: 1), ['a']);
      await db.computeTripStats('a', 1);
      expect(await db.tripsNeedingStats(), ['b']);
      await db.computeTripStats('b', 1);
      expect(
        await db.tripsNeedingStats(),
        isEmpty,
        reason: 'the backfill converges',
      );
    },
    skip: skip,
  );

  test('allConvoyLocal lists memberships newest first', () async {
    await db.upsertConvoyLocal(
      const ConvoyLocalCompanion(
        convoyId: Value('old'),
        joinedAt: Value(1000),
        updatedAt: Value(1000),
      ),
    );
    await db.upsertConvoyLocal(
      const ConvoyLocalCompanion(
        convoyId: Value('new'),
        joinedAt: Value(5000),
        updatedAt: Value(5000),
      ),
    );
    final rows = await db.allConvoyLocal();
    expect(rows.map((r) => r.convoyId), ['new', 'old']);
  }, skip: skip);
}

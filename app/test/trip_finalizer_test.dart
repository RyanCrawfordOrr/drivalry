import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/models/trip_phase.dart';
import 'package:drivalry/tracking/match_runner.dart';
import 'package:drivalry/tracking/trip_finalizer.dart';
import 'package:drivalry_packs/drivalry_packs.dart';
import 'package:drivalry_scoring/drivalry_scoring.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sqlite_support.dart';

const startLat = 36.1627;
const startLon = -86.7816;

/// A straight 3 km east-west road posted at 25 mph.
PackWay elmStreet() {
  final end = destination(startLat, startLon, 90, 3000);
  return PackWay(
    id: 4242,
    roadClass: RoadClass.residential,
    name: 'Elm St',
    lats: [startLat, end.lat],
    lons: [startLon, end.lon],
    maxForward: 25,
    mph: true,
    source: LimitSource.tag,
  );
}

/// 1 Hz samples driving east along Elm St at [speed] m/s for [seconds].
List<SamplesCompanion> drive(String tripId, int t0, int seconds, double speed) {
  final out = <SamplesCompanion>[];
  var lat = startLat;
  var lon = startLon;
  for (var i = 0; i < seconds; i++) {
    out.add(
      SamplesCompanion.insert(
        tripId: tripId,
        t: t0 + i * 1000,
        lat: lat,
        lon: lon,
        speed: Value(speed),
        accuracy: 5,
        heading: const Value(90),
      ),
    );
    final next = destination(lat, lon, 90, speed);
    lat = next.lat;
    lon = next.lon;
  }
  return out;
}

Future<void> seedTrip(
  AppDatabase db,
  String id,
  int t0,
  int seconds,
  double speed,
) async {
  await db.ensureTrip(
    TripsCompanion.insert(
      id: id,
      startedAt: t0,
      phase: TripPhase.pendingPassenger.wire,
      createdAt: t0,
      endedAt: Value(t0 + seconds * 1000),
    ),
  );
  await db.insertFixBatch(
    id,
    t0 + seconds * 1000,
    drive(id, t0, seconds, speed),
  );
}

Future<void> installFakePack(AppDatabase db) => db.upsertPack(
  PacksCompanion.insert(
    region: 'us-tn',
    name: 'Tennessee (test)',
    osmTimestamp: '2026-10-31T00:00:00Z',
    path: 'memory://us-tn',
    sha256: 'deadbeef',
    bytes: 1,
    wayCount: 1,
    bboxMinLat: 35,
    bboxMinLon: -90,
    bboxMaxLat: 37,
    bboxMaxLon: -82,
    installedAt: 0,
  ),
);

void main() {
  final skip = skipWithoutSqlite();
  // 2026-06-15 18:00 UTC = 13:00 in Nashville: daylight.
  final noon = DateTime.utc(2026, 6, 15, 18).millisecondsSinceEpoch;

  late AppDatabase db;
  setUp(() => db = memoryDatabase());
  tearDown(() => db.close());

  TripFinalizer finalizer() => TripFinalizer(
    db,
    matcher: InlineMatchRunner((_) => MemoryPack.fromWays([elmStreet()])),
    now: () => 5,
  );

  test('speeding on a known road is matched, scored and roasted', () async {
    await installFakePack(db);
    await seedTrip(db, 'fast', noon, 150, 18); // 40 mph in a 25 for 2.7 km

    final result = await finalizer().finalize('fast');
    final score = result!.score!;
    expect(score.scored, isTrue);
    expect(score.events.map((e) => e.kind), contains(EventKind.speeding));
    expect(score.score, lessThan(90));
    expect(score.roastText, isNotNull);
    expect(score.roastText, contains('Elm St'));

    final trip = result.trip;
    expect(trip.phase, TripPhase.scored.wire);
    expect(trip.limitCoverage, closeTo(1.0, 0.01));
    expect(trip.packRegion, 'us-tn');
    expect(trip.distanceM, closeTo(150 * 18, 150 * 18 * 0.02));
    expect(trip.nightFraction, 0);
    expect(trip.isPassenger, isFalse);

    final segments = await db.segmentsFor('fast');
    expect(segments.map((s) => s.wayId), everyElement('4242'));
    expect(segments.first.speedLimit, closeTo(25 * mph, 1e-6));
    expect(segments.first.name, 'Elm St');

    final row = (await db.scoreFor('fast'))!;
    expect(row.score, score.score);
    expect(row.roastText, score.roastText);
  }, skip: skip);

  test(
    'without a pack the trip is still scored, with one unknown segment',
    () async {
      await seedTrip(db, 'nopack', noon, 150, 18);
      final result = await finalizer().finalize('nopack');
      final score = result!.score!;
      expect(score.scored, isTrue);
      expect(
        score.events.map((e) => e.kind),
        isNot(contains(EventKind.speeding)),
      );
      expect(result.trip.limitCoverage, 0);
      expect(result.trip.packRegion, isNull);
      final segments = await db.segmentsFor('nopack');
      expect(segments, hasLength(1));
      expect(segments.single.roadClass, RoadClass.unknown);
      expect(segments.single.toIdx, 149);
    },
    skip: skip,
  );

  test(
    'passenger answer re-scores as unscored and marks the question answered',
    () async {
      await installFakePack(db);
      await seedTrip(db, 'pax', noon, 150, 18);
      final f = finalizer();
      await f.finalize('pax');
      final again = await f.finalize(
        'pax',
        isPassenger: true,
        markAnswered: true,
      );
      expect(again!.score!.scored, isFalse);
      expect(again.score!.unscoredReason, 'passenger');
      expect(again.trip.phase, TripPhase.unscored.wire);
      expect(again.trip.passengerAnswered, isTrue);
      expect(again.trip.isPassenger, isTrue);
    },
    skip: skip,
  );

  test('a pending limit flag silences the road for this phone', () async {
    await installFakePack(db);
    await seedTrip(db, 'flagged', noon, 150, 18);
    await db.addLimitFlag(
      LimitFlagsCompanion.insert(
        wayId: '4242',
        region: const Value('us-tn'),
        suggestedMps: 40 * mph,
        createdAt: 1,
      ),
    );
    final result = await finalizer().finalize('flagged');
    expect(
      result!.score!.events.map((e) => e.kind),
      isNot(contains(EventKind.speeding)),
    );
    // Still seen, just not scored: it shows up as an observation at most.
    final segments = await db.segmentsFor('flagged');
    expect(segments.first.confidence, 0.5);
  }, skip: skip);

  test('too few samples → unscored without running the engine', () async {
    await db.ensureTrip(
      TripsCompanion.insert(
        id: 'tiny',
        startedAt: noon,
        phase: TripPhase.pendingPassenger.wire,
        createdAt: noon,
      ),
    );
    await db.insertFixBatch('tiny', noon, drive('tiny', noon, 1, 3));
    final result = await finalizer().finalize('tiny');
    expect(result!.score, isNull);
    expect(result.trip.phase, TripPhase.unscored.wire);
  }, skip: skip);

  test('resumePending finalises every ended-but-unscored trip', () async {
    await seedTrip(db, 'a', noon, 150, 10);
    await seedTrip(db, 'b', noon + 10 * 60 * 1000, 150, 10);
    final done = await finalizer().resumePending();
    expect(done.toSet(), {'a', 'b'});
    expect(await db.tripsInPhase(TripPhase.pendingPassenger), isEmpty);
  }, skip: skip);

  test('daily credited km and clean streak feed the context', () async {
    await installFakePack(db);
    final f = finalizer();
    // Two clean trips earlier today.
    await seedTrip(db, 'c1', noon - 3600 * 1000 * 3, 150, 10);
    await seedTrip(db, 'c2', noon - 3600 * 1000 * 2, 150, 10);
    await f.finalize('c1');
    await f.finalize('c2');
    expect(await db.cleanStreakBefore(noon), 2);
    expect(
      await db.creditedKmBetween(noon - 86400 * 1000, noon),
      closeTo(3.0, 0.1),
    );
  }, skip: skip);

  test('samples without a speed get one from positions', () {
    final rows = [
      const Sample(
        tripId: 'x',
        t: 0,
        lat: 0,
        lon: 0,
        speed: null,
        accuracy: 5,
        heading: null,
        altitude: null,
      ),
      Sample(
        tripId: 'x',
        t: 1000,
        lat: destination(0, 0, 0, 10).lat,
        lon: 0,
        speed: null,
        accuracy: 5,
        heading: null,
        altitude: null,
      ),
    ];
    final s = TripFinalizer.toGpsSamples(rows);
    expect(s[0].speed, closeTo(10, 0.1));
    expect(s[1].speed, closeTo(10, 0.1));
  });
}

import 'package:drift/drift.dart' show Value;
import 'package:drivalry/data/crash/crash_monitor.dart' show CrashKeys;
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/models/trip_phase.dart';
import 'package:drivalry/tracking/match_runner.dart';
import 'package:drivalry/tracking/tracking_models.dart';
import 'package:drivalry/tracking/trip_finalizer.dart';
import 'package:drivalry/tracking/trip_recorder.dart';
import 'package:drivalry_packs/drivalry_packs.dart';
import 'package:drivalry_scoring/drivalry_scoring.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sqlite_support.dart';

const lat0 = 36.1627;
const lon0 = -86.7816;

PackWay road() {
  final end = destination(lat0, lon0, 90, 3000);
  return PackWay(
    id: 7,
    roadClass: RoadClass.residential,
    name: 'Elm St',
    lats: [lat0, end.lat],
    lons: [lon0, end.lon],
    maxForward: 25,
    mph: true,
    source: LimitSource.tag,
  );
}

FixesEvent batch(String tripId, int t0, int seconds, double speed) {
  final fixes = <Fix>[];
  var lat = lat0;
  var lon = lon0;
  for (var i = 0; i < seconds; i++) {
    fixes.add(
      Fix(
        t: t0 + i * 1000,
        lat: lat,
        lon: lon,
        accuracy: 5,
        speed: speed,
        heading: 90,
      ),
    );
    final n = destination(lat, lon, 90, speed);
    lat = n.lat;
    lon = n.lon;
  }
  return FixesEvent(tripId: tripId, t: t0 + (seconds - 1) * 1000, fixes: fixes);
}

CrashCandidateEvent candidate(String tripId, int t) => CrashCandidateEvent(
  tripId: tripId,
  t: t,
  peakMps2: 48,
  speedBeforeMps: 14,
  lat: lat0,
  lon: lon0,
  accuracy: 5,
);

void main() {
  final skip = skipWithoutSqlite();
  final noon = DateTime.utc(2026, 6, 15, 18).millisecondsSinceEpoch;
  late AppDatabase db;
  late List<CrashCandidateEvent> seen;
  late List<String> ended;
  late TripFinalizer finalizer;
  late TripRecorder recorder;

  setUp(() async {
    db = memoryDatabase();
    seen = [];
    ended = [];
    finalizer = TripFinalizer(
      db,
      matcher: InlineMatchRunner((_) => MemoryPack.fromWays([road()])),
      now: () => 5,
    );
    recorder = TripRecorder(
      db,
      onTripEnded: (id) async {
        ended.add(id);
        await finalizer.finalize(id);
      },
      onCrashCandidate: seen.add,
      now: () => 1,
    );
    await db.upsertPack(
      PacksCompanion.insert(
        region: 'us-tn',
        name: 'Tennessee (test)',
        osmTimestamp: 'x',
        path: 'memory://us-tn',
        sha256: 'd',
        bytes: 1,
        wayCount: 1,
        bboxMinLat: 35,
        bboxMinLon: -90,
        bboxMaxLat: 37,
        bboxMaxLon: -82,
        installedAt: 0,
      ),
    );
  });
  tearDown(() => db.close());

  Future<void> record(String id, {bool crash = true}) async {
    await recorder.handle(
      PhaseEvent(
        tripId: id,
        t: noon,
        phase: TripPhaseSignal.active,
        startedAt: noon,
        reason: 'manual',
      ),
    );
    await recorder.handle(batch(id, noon, 150, 14));
    if (crash) await recorder.handle(candidate(id, noon + 149 * 1000));
    await recorder.handle(
      PhaseEvent(
        tripId: id,
        t: noon + 200 * 1000,
        phase: TripPhaseSignal.ended,
        reason: 'stationary',
      ),
    );
    await recorder.flush();
  }

  test('a candidate flags the trip and reaches the monitor hook', () async {
    await record('c1');
    expect(seen.map((e) => e.tripId), ['c1']);
    final trip = (await db.tripById('c1'))!;
    expect(trip.crashCandidate, isTrue);
  }, skip: skip);

  test(
    'a flagged trip ends unscored and is scored once the flag clears',
    () async {
      await record('c2');
      expect(ended, ['c2']);
      var trip = (await db.tripById('c2'))!;
      expect(trip.phase, TripPhase.unscored.wire, reason: 'parked, not scored');
      expect(await db.scoreFor('c2'), isNull);

      // Re-finalising while flagged changes nothing.
      expect(await finalizer.finalize('c2'), isNull);
      expect((await db.tripById('c2'))!.phase, TripPhase.unscored.wire);

      // "I'm OK": clear the flag, finalize → scored.
      await db.setCrashCandidate('c2', false);
      final result = await finalizer.finalize('c2');
      expect(result, isNotNull);
      expect(result!.score, isNotNull);
      trip = (await db.tripById('c2'))!;
      expect(trip.phase, TripPhase.scored.wire);
      expect(await db.scoreFor('c2'), isNotNull);
    },
    skip: skip,
  );

  test('without a candidate the same trip scores immediately', () async {
    await record('ok', crash: false);
    expect(seen, isEmpty);
    expect((await db.tripById('ok'))!.phase, TripPhase.scored.wire);
  }, skip: skip);

  test('a replayed candidate is a no-op on an already-cleared trip', () async {
    await record('c3');
    await db.setCrashCandidate('c3', false);
    await finalizer.finalize('c3');
    // Spool replay after the user said they were fine: the recorder flags
    // again (it cannot know), the monitor sees it; the clear path is the
    // user's. Here we only pin that nothing crashes and the row survives.
    await recorder.handle(candidate('c3', noon + 149 * 1000));
    await recorder.flush();
    expect(seen.length, 2);
    expect((await db.tripById('c3'))!.crashCandidate, isTrue);
  }, skip: skip);

  test('with detection switched off a candidate is ignored entirely', () async {
    await db.setSetting(CrashKeys.enabled, 'false');
    await record('off');
    expect(seen, isEmpty);
    final trip = (await db.tripById('off'))!;
    expect(trip.crashCandidate, isFalse);
    expect(trip.phase, TripPhase.scored.wire, reason: 'scored normally');
  }, skip: skip);

  test('crashFlaggedTrips lists only flagged, undeleted trips', () async {
    await record('f1');
    await record('f2', crash: false);
    final flagged = await db.crashFlaggedTrips();
    expect(flagged.map((t) => t.id), ['f1']);
    await db.updateTrip('f1', const TripsCompanion(deletedAt: Value(9)));
    expect(await db.crashFlaggedTrips(), isEmpty);
  }, skip: skip);
}

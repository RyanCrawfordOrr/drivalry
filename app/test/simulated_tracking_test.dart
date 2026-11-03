import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/models/trip_phase.dart';
import 'package:drivalry/tracking/match_runner.dart';
import 'package:drivalry/tracking/simulated_tracking.dart';
import 'package:drivalry/tracking/tracking_models.dart';
import 'package:drivalry/tracking/trip_finalizer.dart';
import 'package:drivalry/tracking/trip_recorder.dart';
import 'package:drivalry_scoring/drivalry_scoring.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sqlite_support.dart';

void main() {
  final skip = skipWithoutSqlite();
  late AppDatabase db;
  setUp(() => db = memoryDatabase());
  tearDown(() => db.close());

  test('replaying the messy commute ends with a scored trip', () async {
    // No pack is installed, so the finalizer must never reach the matcher.
    final finalizer = TripFinalizer(
      db,
      matcher: InlineMatchRunner((_) => throw StateError('no pack expected')),
      now: () => 1,
    );
    final recorder = TripRecorder(db, onTripEnded: finalizer.finalize);
    final sim = SimulatedTracking(speedUp: 0);
    final events = <TrackingEvent>[];
    final sub = sim.events.listen((e) {
      events.add(e);
      recorder.handle(e);
    });

    final id = await sim.play(messyCommute(), rebaseToNow: true);
    await recorder.flush(); // every write, including the finalisation
    await sub.cancel();
    sim.dispose();

    // Shape of the replay: one tentative, one active, N fix batches, phone
    // events, one ended.
    expect(events.whereType<PhaseEvent>().map((e) => e.phase).toList(), [
      TripPhaseSignal.tentative,
      TripPhaseSignal.active,
      TripPhaseSignal.ended,
    ]);
    expect(events.whereType<PhoneEventRaw>(), hasLength(3));
    final fixes = events.whereType<FixesEvent>().toList();
    expect(
      fixes.fold<int>(0, (n, e) => n + e.fixes.length),
      messyCommute().samples.length,
    );
    expect(fixes.first.fixes, hasLength(15));

    final trip = (await db.tripById(id))!;
    expect(trip.phase, TripPhase.scored.wire);
    expect(trip.endedAt, isNotNull);
    final score = (await db.scoreFor(id))!;
    expect(score.scored, isTrue);
    // No pack in this test, so speeding is silent; phone handling and the
    // slam still cost points.
    expect(score.score, lessThan(100));
    expect(await db.phoneEventsFor(id), hasLength(3));
    expect(await db.sampleCount(id), messyCommute().samples.length);
  }, skip: skip);

  test('spooled events replay identically', () async {
    final sim = SimulatedTracking(speedUp: 0)..spoolEvents = true;
    final live = <TrackingEvent>[];
    final sub = sim.events.listen(live.add);
    await sim.play(cleanCommute());
    await sub.cancel();
    final spooled = await sim.drainSpool();
    expect(spooled.length, live.length);
    expect(
      [for (final e in spooled) e.toMap()],
      [for (final e in live) e.toMap()],
    );
    expect(await sim.drainSpool(), isEmpty);
    sim.dispose();
  });
}

import 'package:drift/drift.dart' show Value;
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/models/trip_phase.dart';
import 'package:drivalry/tracking/tracking_models.dart';
import 'package:drivalry/tracking/trip_recorder.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sqlite_support.dart';

FixesEvent batch(String tripId, int t0, int n) => FixesEvent(
  tripId: tripId,
  t: t0 + (n - 1) * 1000,
  fixes: [
    for (var i = 0; i < n; i++)
      Fix(
        t: t0 + i * 1000,
        lat: 36.0 + i * 1e-4,
        lon: -86.0,
        accuracy: 5,
        speed: 12,
        heading: 0,
      ),
  ],
);

void main() {
  final skip = skipWithoutSqlite();
  late AppDatabase db;
  late List<String> ended;
  late TripRecorder recorder;

  setUp(() {
    db = memoryDatabase();
    ended = [];
    recorder = TripRecorder(db, onTripEnded: ended.add, now: () => 999);
  });
  tearDown(() => db.close());

  test(
    'tentative → active → fixes → ended produces a pendingPassenger trip',
    () async {
      await recorder.handle(
        const PhaseEvent(
          tripId: 't1',
          t: 1000,
          phase: TripPhaseSignal.tentative,
          reason: 'activity',
        ),
      );
      await recorder.handle(
        const PhaseEvent(
          tripId: 't1',
          t: 21000,
          phase: TripPhaseSignal.active,
          startedAt: 20000,
        ),
      );
      await recorder.handle(batch('t1', 20000, 15));
      await recorder.handle(
        const PhaseEvent(
          tripId: 't1',
          t: 40000,
          phase: TripPhaseSignal.ended,
          reason: 'stationary',
        ),
      );

      final trip = (await db.tripById('t1'))!;
      expect(trip.phase, TripPhase.pendingPassenger.wire);
      expect(trip.startedAt, 20000);
      expect(trip.endedAt, 40000);
      expect(trip.endReason, 'stationary');
      expect(trip.triggerKind, 'activity');
      expect(await db.sampleCount('t1'), 15);
      expect(ended, ['t1']);
    },
    skip: skip,
  );

  test('a replayed fixes batch is stored once', () async {
    final b = batch('t2', 1000, 10);
    await recorder.handle(b);
    await recorder.handle(b);
    await recorder.handle(
      FixesEvent(tripId: 't2', t: b.t, fixes: b.fixes.sublist(0, 3)),
    );
    expect(await db.sampleCount('t2'), 10);
  }, skip: skip);

  test('a replayed ended event does not fire twice', () async {
    await recorder.handle(batch('t3', 1000, 5));
    const end = PhaseEvent(
      tripId: 't3',
      t: 9000,
      phase: TripPhaseSignal.ended,
      reason: 'exit',
    );
    await recorder.handle(end);
    await recorder.handle(end);
    expect(ended, ['t3']);
  }, skip: skip);

  test('discarded deletes everything about the trip', () async {
    await recorder.handle(
      const PhaseEvent(tripId: 't4', t: 1000, phase: TripPhaseSignal.tentative),
    );
    await recorder.handle(batch('t4', 1000, 4));
    await recorder.handle(
      const PhaseEvent(tripId: 't4', t: 9000, phase: TripPhaseSignal.discarded),
    );
    expect(await db.tripById('t4'), isNull);
    expect(await db.sampleCount('t4'), 0);
    expect((await db.tableCounts())['trips'], 0);
  }, skip: skip);

  test(
    'phone events map to engine kinds and are dropped while projecting',
    () async {
      await recorder.handleAll(const [
        PhaseEvent(
          tripId: 't5',
          t: 1000,
          phase: TripPhaseSignal.active,
          startedAt: 1000,
        ),
        PhoneEventRaw(tripId: 't5', t: 2000, kind: PhoneSignal.unlock),
        PhoneEventRaw(tripId: 't5', t: 2500, kind: PhoneSignal.screenOn),
        PhoneEventRaw(tripId: 't5', t: 3000, kind: PhoneSignal.callStart),
        PhoneEventRaw(tripId: 't5', t: 4000, kind: PhoneSignal.projectionOn),
        PhoneEventRaw(tripId: 't5', t: 5000, kind: PhoneSignal.unlock),
        PhoneEventRaw(tripId: 't5', t: 6000, kind: PhoneSignal.interaction),
        PhoneEventRaw(tripId: 't5', t: 7000, kind: PhoneSignal.projectionOff),
        PhoneEventRaw(tripId: 't5', t: 8000, kind: PhoneSignal.interaction),
      ]);
      final rows = await db.phoneEventsFor('t5');
      expect(
        [for (final r in rows) (r.t, r.kind)],
        [(2000, 'unlock'), (3000, 'call_handheld'), (8000, 'interaction')],
      );
    },
    skip: skip,
  );

  test('an interaction within a second of an unlock is the same act', () async {
    await recorder.handleAll(const [
      PhaseEvent(
        tripId: 't7',
        t: 1000,
        phase: TripPhaseSignal.active,
        startedAt: 1000,
      ),
      // Android: USER_PRESENT arrives as unlock + interaction at the same time.
      PhoneEventRaw(tripId: 't7', t: 5000, kind: PhoneSignal.unlock),
      PhoneEventRaw(tripId: 't7', t: 5000, kind: PhoneSignal.interaction),
      // Reverse order, 300 ms apart: still one unlock.
      PhoneEventRaw(tripId: 't7', t: 9000, kind: PhoneSignal.interaction),
      PhoneEventRaw(tripId: 't7', t: 9300, kind: PhoneSignal.unlock),
      // Far enough apart to be a second act.
      PhoneEventRaw(tripId: 't7', t: 12000, kind: PhoneSignal.interaction),
    ]);
    final rows = await db.phoneEventsFor('t7');
    expect(
      [for (final r in rows) (r.t, r.kind)],
      [(5000, 'unlock'), (9300, 'unlock'), (12000, 'interaction')],
    );
  }, skip: skip);

  test(
    'bluetooth hint sets the vehicle label; motion peaks are stored',
    () async {
      await recorder.handleAll(const [
        PhaseEvent(
          tripId: 't6',
          t: 1000,
          phase: TripPhaseSignal.active,
          startedAt: 1000,
        ),
        HintEvent(tripId: 't6', t: 1200, kind: 'bluetooth', name: 'Civic'),
        MotionPeaksEvent(
          tripId: 't6',
          t: 3000,
          peaks: [
            MotionPeakSample(t: 2000, peak: 2.9),
            MotionPeakSample(t: 3000, peak: 4.2),
          ],
        ),
      ]);
      expect((await db.tripById('t6'))!.vehicleLabel, 'Civic');
      expect(await db.motionPeaksFor('t6'), hasLength(2));
    },
    skip: skip,
  );

  test('replaying a scored trip from the spool changes nothing and does not '
      're-finalise it', () async {
    const tentative = PhaseEvent(
      tripId: 't8',
      t: 1000,
      phase: TripPhaseSignal.tentative,
      reason: 'activity',
    );
    const active = PhaseEvent(
      tripId: 't8',
      t: 22000,
      phase: TripPhaseSignal.active,
      startedAt: 2000,
    );
    final fixes = batch('t8', 2000, 20);
    const end = PhaseEvent(
      tripId: 't8',
      t: 60000,
      phase: TripPhaseSignal.ended,
      reason: 'stationary',
    );
    await recorder.handleAll([tentative, active, fixes, end]);
    expect(ended, ['t8']);
    // The finalizer scored it and the user answered the passenger question.
    await db.updateTrip(
      't8',
      TripsCompanion(
        phase: Value(TripPhase.scored.wire),
        passengerAnswered: const Value(true),
      ),
    );

    // Next launch: the spool still holds every event of the trip (docs/08 §5).
    await recorder.handleAll([tentative, active, fixes, end]);

    final trip = (await db.tripById('t8'))!;
    expect(trip.phase, TripPhase.scored.wire);
    expect(trip.startedAt, 2000);
    expect(trip.endedAt, 60000);
    expect(trip.passengerAnswered, isTrue);
    expect(await db.sampleCount('t8'), 20);
    expect(ended, ['t8'], reason: 'ended must not fire a second time');
  }, skip: skip);

  test('a replayed active does not regress a pending trip either', () async {
    const active = PhaseEvent(
      tripId: 't10',
      t: 2000,
      phase: TripPhaseSignal.active,
      startedAt: 2000,
    );
    const end = PhaseEvent(
      tripId: 't10',
      t: 9000,
      phase: TripPhaseSignal.ended,
      reason: 'manual',
    );
    await recorder.handleAll([active, batch('t10', 2000, 5), end]);
    await recorder.handle(active);
    expect((await db.tripById('t10'))!.phase, TripPhase.pendingPassenger.wire);
    expect(ended, ['t10']);
  }, skip: skip);

  test(
    'a tentative replayed after its discard does not resurrect the trip',
    () async {
      const tentative = PhaseEvent(
        tripId: 't9',
        t: 1000,
        phase: TripPhaseSignal.tentative,
      );
      const discarded = PhaseEvent(
        tripId: 't9',
        t: 5000,
        phase: TripPhaseSignal.discarded,
        reason: 'unconfirmed',
      );
      await recorder.handleAll([tentative, discarded, tentative, discarded]);
      await recorder.handle(tentative);
      expect(await db.tripById('t9'), isNull);
      expect((await db.tableCounts())['trips'], 0);
    },
    skip: skip,
  );
}

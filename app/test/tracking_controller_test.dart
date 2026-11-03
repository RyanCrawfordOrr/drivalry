import 'package:drift/drift.dart' show Value;
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/models/trip_phase.dart';
import 'package:drivalry/tracking/providers.dart';
import 'package:drivalry/tracking/tracking_controller.dart';
import 'package:drivalry/tracking/tracking_models.dart';
import 'package:drivalry/tracking/weather.dart';
import 'package:drivalry_scoring/drivalry_scoring.dart' show destination;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_tracking_port.dart';
import 'support/sqlite_support.dart';

FixesEvent batch(String tripId, int t0, int n, {double lat0 = 36.0}) =>
    FixesEvent(
      tripId: tripId,
      t: t0 + (n - 1) * 1000,
      fixes: [
        for (var i = 0; i < n; i++)
          Fix(
            t: t0 + i * 1000,
            lat: lat0 + i * 1e-4,
            lon: -86.0,
            accuracy: 5,
            speed: 12,
            heading: 0,
          ),
      ],
    );

/// Emits [liveDuringDrain] on the live stream while `drainSpool` is running,
/// which is exactly the window the controller must already be listening in.
class DrainingPort extends FakeTrackingPort {
  DrainingPort({super.state, super.spool});

  final List<TrackingEvent> liveDuringDrain = [];

  @override
  Future<List<TrackingEvent>> drainSpool() async {
    for (final e in liveDuringDrain) {
      emit(e);
    }
    liveDuringDrain.clear();
    return super.drainSpool();
  }
}

/// Every forced start fails the way the Android plugin reports failures.
class FailingPort extends FakeTrackingPort {
  FailingPort({super.state});

  @override
  Future<TrackingState> forceStartTrip() async {
    calls.add('forceStartTrip');
    throw PlatformException(code: 'native', message: 'boom: no permission');
  }
}

void main() {
  final skip = skipWithoutSqlite();
  late AppDatabase db;
  late FakeTrackingPort port;
  late ProviderContainer container;

  setUp(() => db = memoryDatabase());
  tearDown(() async {
    container.dispose();
    await port.dispose();
    await db.close();
  });

  ProviderContainer makeContainer(FakeTrackingPort p) {
    port = p;
    return container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        trackingPortProvider.overrideWithValue(p),
        weatherClientProvider.overrideWithValue(const NoWeather()),
      ],
    );
  }

  Future<void> settle() async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await container.read(tripRecorderProvider).flush();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await container.read(tripRecorderProvider).flush();
  }

  test('boot listens before it drains: live events during the drain are stored '
      'once, and spool duplicates are deduped', () async {
    const active = PhaseEvent(
      tripId: 'x',
      t: 1000,
      phase: TripPhaseSignal.active,
      startedAt: 1000,
    );
    final b1 = batch('x', 1000, 10);
    final b2 = batch('x', 11000, 5, lat0: 36.01);
    final p = DrainingPort(
      state: const TrackingState(phase: TrackingPhase.active, tripId: 'x'),
      spool: [active, b1],
    );
    // b1 arrives live too (the plugin streams and spools every batch); b2
    // arrives live only, in the middle of the drain.
    p.liveDuringDrain.addAll([b1, b2]);
    final c = makeContainer(p);

    final notifier = c.read(trackingControllerProvider.notifier);
    await notifier.boot();
    await settle();

    expect(await db.sampleCount('x'), 15, reason: 'b1 once, b2 once');
    expect(c.read(trackingControllerProvider).booted, isTrue);
    expect(c.read(trackingControllerProvider).live?.fixCount, 15);
    // boot() shares one run between the provider's own call and ours.
    expect(p.calls.where((call) => call == 'drainSpool').length, 1);
  }, skip: skip);

  test('the spool is drained again after every ended event', () async {
    final c = makeContainer(FakeTrackingPort());
    final notifier = c.read(trackingControllerProvider.notifier);
    await notifier.boot();
    expect(port.calls.where((call) => call == 'drainSpool').length, 1);

    port.emit(
      const PhaseEvent(
        tripId: 'y',
        t: 1000,
        phase: TripPhaseSignal.active,
        startedAt: 1000,
      ),
    );
    port.emit(batch('y', 1000, 5));
    port.emit(
      const PhaseEvent(
        tripId: 'y',
        t: 9000,
        phase: TripPhaseSignal.ended,
        reason: 'manual',
      ),
    );
    await settle();

    expect(port.calls.where((call) => call == 'drainSpool').length, 2);
    expect(c.read(trackingControllerProvider).live, isNull);
  }, skip: skip);

  test('a PlatformException from a user action becomes state.error', () async {
    final c = makeContainer(FailingPort());
    final notifier = c.read(trackingControllerProvider.notifier);
    await notifier.boot();

    await notifier.startNow(); // must not throw
    expect(c.read(trackingControllerProvider).error, contains('boom'));

    await notifier.endNow(); // succeeds and clears the error
    expect(c.read(trackingControllerProvider).error, isNull);
    expect(port.calls, containsAll(['forceStartTrip', 'forceEndTrip']));
  }, skip: skip);

  test('rescore keeps the passenger answer; answerPassenger sets it', () async {
    final c = makeContainer(FakeTrackingPort());
    final notifier = c.read(trackingControllerProvider.notifier);
    await notifier.boot();

    // 150 s east at 12 m/s: long enough to score.
    const t0 = 1_700_000_000_000;
    var lat = 36.1627;
    var lon = -86.7816;
    final rows = <SamplesCompanion>[];
    for (var i = 0; i < 150; i++) {
      rows.add(
        SamplesCompanion.insert(
          tripId: 'z',
          t: t0 + i * 1000,
          lat: lat,
          lon: lon,
          speed: const Value(12),
          accuracy: 5,
          heading: const Value(90),
        ),
      );
      final next = destination(lat, lon, 90, 12);
      lat = next.lat;
      lon = next.lon;
    }
    await db.ensureTrip(
      TripsCompanion.insert(
        id: 'z',
        startedAt: t0,
        phase: TripPhase.pendingPassenger.wire,
        createdAt: t0,
        endedAt: const Value(t0 + 150000),
      ),
    );
    await db.insertFixBatch('z', t0 + 150000, rows);

    await notifier.rescore('z');
    var trip = (await db.tripById('z'))!;
    expect(trip.phase, TripPhase.scored.wire);
    expect(trip.passengerAnswered, isFalse, reason: 'rescore is not an answer');
    expect(trip.isPassenger, isFalse, reason: 'hint-derived, not answered');

    await notifier.answerPassenger('z', true);
    trip = (await db.tripById('z'))!;
    expect(trip.passengerAnswered, isTrue);
    expect(trip.isPassenger, isTrue);

    await notifier.rescore('z');
    trip = (await db.tripById('z'))!;
    expect(trip.passengerAnswered, isTrue);
    expect(trip.isPassenger, isTrue, reason: 'rescore preserves the answer');
  }, skip: skip);

  test('boot runs once even when called twice', () async {
    final c = makeContainer(FakeTrackingPort());
    final notifier = c.read(trackingControllerProvider.notifier);
    await Future.wait([notifier.boot(), notifier.boot()]);
    await settle();
    expect(port.calls.where((call) => call == 'drainSpool').length, 1);
  }, skip: skip);
}

import 'package:drift/drift.dart' show Value;
import 'package:drivalry/car/car_actions.dart';
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/tracking/providers.dart';
import 'package:drivalry/tracking/tracking_controller.dart';
import 'package:drivalry/tracking/tracking_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_tracking_port.dart';
import '../support/sqlite_support.dart';

void main() {
  group('CarAction.fromWire', () {
    test('accepts known names and normalises args', () {
      final a = CarAction.fromWire({
        'name': 'voteStop',
        'args': {'stopId': 's1', 'vote': 1},
      });
      expect(a, isNotNull);
      expect(a!.name, CarActionNames.voteStop);
      expect(a.string('stopId'), 's1');
      expect(a.integer('vote'), 1);
      expect(a.string('vote'), isNull);
      expect(a.toWire(), {
        'name': 'voteStop',
        'args': {'stopId': 's1', 'vote': 1},
      });
    });

    test('rejects unknown names and malformed payloads', () {
      expect(CarAction.fromWire({'name': 'selfDestruct'}), isNull);
      expect(CarAction.fromWire('endTrip'), isNull);
      expect(CarAction.fromWire({'args': {}}), isNull);
      expect(CarAction.fromWire(null), isNull);
    });

    test('missing args are an empty map', () {
      final a = CarAction.fromWire({'name': 'endTrip'});
      expect(a!.args, isEmpty);
    });
  });

  group('tripEnded', () {
    const active = TrackingState(phase: TrackingPhase.active, tripId: 't1');
    test(
      'active to idle or to another trip counts; anything else does not',
      () {
        expect(tripEnded(active, const TrackingState()), isTrue);
        expect(
          tripEnded(
            active,
            const TrackingState(phase: TrackingPhase.tentative, tripId: 't2'),
          ),
          isTrue,
        );
        expect(tripEnded(active, active), isFalse);
        expect(
          tripEnded(
            const TrackingState(phase: TrackingPhase.tentative, tripId: 't1'),
            const TrackingState(),
          ),
          isFalse,
          reason: 'an unconfirmed trip never recorded anything',
        );
      },
    );
  });

  group('CarActionHandler', () {
    late AppDatabase db;
    late FakeTrackingPort port;
    late ProviderContainer container;

    setUp(() {
      db = memoryDatabase();
      port = FakeTrackingPort(
        state: const TrackingState(phase: TrackingPhase.active, tripId: 't1'),
      );
      container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          trackingPortProvider.overrideWithValue(port),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    Future<void> seedTrip({int? endedAt}) => db.ensureTrip(
      TripsCompanion.insert(
        id: 't1',
        startedAt: 1000,
        phase: endedAt == null ? 'recording' : 'pendingPassenger',
        createdAt: 1000,
        endedAt: Value(endedAt),
      ),
    );

    test('endTrip forces the native trip to end', () async {
      await container.read(trackingControllerProvider.notifier).boot();
      final ok = await container
          .read(carActionHandlerProvider)
          .handle(const CarAction(CarActionNames.endTrip));
      expect(ok, isTrue);
      expect(port.calls, contains('forceEndTrip'));
    }, skip: skipWithoutSqlite());

    test(
      'markPassenger sets the hint and remembers the intent',
      () async {
        await seedTrip();
        await container.read(trackingControllerProvider.notifier).boot();
        final ok = await container
            .read(carActionHandlerProvider)
            .handle(
              const CarAction(CarActionNames.markPassenger, {'tripId': 't1'}),
            );
        expect(ok, isTrue);
        final trip = await db.tripById('t1');
        expect(trip!.passengerHint, isTrue);
        expect(trip.passengerAnswered, isFalse, reason: 'not finalised yet');
        expect(await db.getSetting(carPassengerIntentKey), 't1');

        // The snapshot flag follows the setting for the current trip only. A
        // listener keeps the stream running (Riverpod 3 pauses unlistened
        // streams, which is also why the bridge watches it rather than reads).
        final sub = container.listen(carPassengerMarkedProvider, (_, _) {});
        expect(await container.read(carPassengerMarkedProvider.future), isTrue);
        sub.close();
      },
      skip: skipWithoutSqlite(),
    );

    test(
      'markPassenger without a trip id uses the recording trip',
      () async {
        await seedTrip();
        await container.read(trackingControllerProvider.notifier).boot();
        final ok = await container
            .read(carActionHandlerProvider)
            .handle(const CarAction(CarActionNames.markPassenger));
        expect(ok, isTrue);
        expect((await db.tripById('t1'))!.passengerHint, isTrue);
      },
      skip: skipWithoutSqlite(),
    );

    test('markPassenger with nothing recording is refused', () async {
      port.state = const TrackingState();
      await container.read(trackingControllerProvider.notifier).boot();
      final ok = await container
          .read(carActionHandlerProvider)
          .handle(const CarAction(CarActionNames.markPassenger));
      expect(ok, isFalse);
    }, skip: skipWithoutSqlite());

    test('the intent is confirmed once the trip has ended', () async {
      await seedTrip(endedAt: 5000);
      await db.setSetting(carPassengerIntentKey, 't1');
      await container.read(trackingControllerProvider.notifier).boot();
      await container
          .read(carActionHandlerProvider)
          .confirmPassengerIfMarked('t1');
      final trip = await db.tripById('t1');
      expect(trip!.isPassenger, isTrue);
      expect(trip.passengerAnswered, isTrue);
      expect(await db.getSetting(carPassengerIntentKey), '');
    }, skip: skipWithoutSqlite());

    test('a trip still recording is not finalised early', () async {
      await seedTrip();
      await db.setSetting(carPassengerIntentKey, 't1');
      await container.read(trackingControllerProvider.notifier).boot();
      await container
          .read(carActionHandlerProvider)
          .confirmPassengerIfMarked('t1');
      final trip = await db.tripById('t1');
      expect(trip!.passengerAnswered, isFalse);
      expect(trip.endedAt, isNull);
      expect(await db.getSetting(carPassengerIntentKey), 't1');
    }, skip: skipWithoutSqlite());

    test(
      'a passenger tap replayed after the trip ended flips the trip',
      () async {
        // The trip ended while Dart was dead; boot finalised it as a driver
        // trip, then the queued car action is replayed.
        await seedTrip(endedAt: 5000);
        await container.read(trackingControllerProvider.notifier).boot();
        var trip = await db.tripById('t1');
        expect(trip!.isPassenger, isFalse);
        final ok = await container
            .read(carActionHandlerProvider)
            .handle(
              const CarAction(CarActionNames.markPassenger, {'tripId': 't1'}),
            );
        expect(ok, isTrue);
        trip = await db.tripById('t1');
        expect(trip!.isPassenger, isTrue);
        expect(trip.passengerAnswered, isTrue);
        expect(await db.getSetting(carPassengerIntentKey), anyOf(isNull, ''));
      },
      skip: skipWithoutSqlite(),
    );

    test(
      'convoy actions without a convoy are refused, not thrown',
      () async {
        await container.read(trackingControllerProvider.notifier).boot();
        final h = container.read(carActionHandlerProvider);
        expect(
          await h.handle(
            const CarAction(CarActionNames.voteStop, {
              'stopId': 's',
              'vote': 1,
            }),
          ),
          isFalse,
        );
        expect(
          await h.handle(const CarAction(CarActionNames.proposeStop)),
          isFalse,
        );
        expect(
          await h.handle(const CarAction(CarActionNames.talkStart)),
          isFalse,
        );
        expect(
          await h.handle(const CarAction(CarActionNames.radioOn)),
          isFalse,
        );
        expect(
          await h.handle(const CarAction(CarActionNames.regroupHere)),
          isFalse,
        );
      },
      skip: skipWithoutSqlite(),
    );
  });
}

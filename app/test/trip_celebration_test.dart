import 'package:drift/drift.dart' show Value;
import 'package:drivalry/app/ui/ui.dart';
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/models/trip_phase.dart';
import 'package:drivalry/features/drive/trip_celebration.dart';
import 'package:drivalry/tracking/providers.dart';
import 'package:drivalry/tracking/tracking_models.dart';
import 'package:drivalry/tracking/weather.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_tracking_port.dart';
import 'support/scored_trips.dart';
import 'support/sqlite_support.dart';
import 'support/widget_support.dart';

Trip _trip(String id, {String phase = 'scored'}) => Trip(
  id: id,
  startedAt: 1000,
  endedAt: 2000,
  phase: phase,
  distanceM: 5000,
  movingS: 600,
  passengerHint: false,
  passengerAnswered: true,
  crashCandidate: false,
  createdAt: 1000,
).copyWith(isPassenger: const Value(false));

TripScoreRow _score(String id, {bool scored = true}) => TripScoreRow(
  tripId: id,
  scoreJson: '{}',
  score: scored ? 88 : null,
  xp: 50,
  reckless: false,
  scored: scored,
  scoredAt: 2001,
);

TripWithScore scored(String id) => TripWithScore(_trip(id), _score(id));
TripWithScore pending(String id) =>
    TripWithScore(_trip(id, phase: TripPhase.pendingPassenger.wire), null);
TripWithScore unscored(String id) => TripWithScore(
  _trip(id, phase: TripPhase.unscored.wire),
  _score(id, scored: false),
);

List<String> ids(List<TripWithScore> rows) => [for (final r in rows) r.trip.id];

void main() {
  group('CelebrationQueue', () {
    test('the first snapshot is the baseline: nothing celebrates', () {
      final q = CelebrationQueue();
      expect(q.onTrips([scored('a'), scored('b')], recording: false), isEmpty);
      expect(q.shown, {'a', 'b'});
      // Feeding the same rows again changes nothing.
      expect(q.onTrips([scored('a'), scored('b')], recording: false), isEmpty);
    });

    test('a trip scored later celebrates exactly once', () {
      final q = CelebrationQueue();
      q.onTrips([pending('c'), scored('a')], recording: false);
      expect(ids(q.onTrips([scored('c'), scored('a')], recording: false)), [
        'c',
      ]);
      expect(q.onTrips([scored('c'), scored('a')], recording: false), isEmpty);
      expect(q.onParked(), isEmpty);
      expect(q.shown, containsAll(['a', 'c']));
    });

    test('while recording the moment waits until the car is parked', () {
      final q = CelebrationQueue();
      q.onTrips(const [], recording: false);
      expect(q.onTrips([scored('d')], recording: true), isEmpty);
      expect(ids(q.queued), ['d']);
      // Still recording on the next snapshot: still waiting, not duplicated.
      expect(q.onTrips([scored('d')], recording: true), isEmpty);
      expect(ids(q.queued), ['d']);
      expect(ids(q.onParked()), ['d']);
      expect(q.onParked(), isEmpty);
      expect(q.onTrips([scored('d')], recording: false), isEmpty);
    });

    test('unscored and pending trips never celebrate', () {
      final q = CelebrationQueue();
      q.onTrips(const [], recording: false);
      expect(
        q.onTrips([pending('p'), unscored('u')], recording: false),
        isEmpty,
      );
      expect(q.shown, isEmpty);
    });

    test(
      'a restored queue celebrates what was scored while the app was away',
      () {
        final q = CelebrationQueue(shown: {'old'}, primed: true);
        expect(
          ids(q.onTrips([scored('new'), scored('old')], recording: false)),
          ['new'],
        );
        expect(q.shown, {'old', 'new'});
      },
    );
  });

  group('CelebratedTripsStore', () {
    final skip = skipWithoutSqlite();

    test('round-trips the shown ids and keeps the newest', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final store = CelebratedTripsStore(db);
      expect(await store.load(), isNull);
      await store.save({'a', 'b'});
      expect(await store.load(), {'a', 'b'});
      final many = {for (var i = 0; i < 250; i++) 't$i'};
      await store.save(many);
      final loaded = (await store.load())!;
      expect(loaded.length, CelebratedTripsStore.keep);
      expect(loaded, contains('t249'));
      expect(loaded, isNot(contains('t0')));
    }, skip: skip);
  });

  group('TripCelebrationHost', () {
    final skip = skipWithoutSqlite() != null;
    late AppDatabase db;
    late FakeTrackingPort port;
    setUp(() {
      Haptics.enabled = false;
      db = memoryDatabase();
    });
    tearDown(() async {
      await port.dispose();
      await db.close();
    });

    testWidgets('shows the moment once the car is parked, then never again', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const liveId = 'live';
      port = FakeTrackingPort(
        state: const TrackingState(
          phase: TrackingPhase.active,
          tripId: liveId,
          tripStartedAt: 1000,
          permissions: TrackingPermissions(
            location: LocationPermission.always,
            preciseLocation: true,
            motion: SimplePermission.granted,
          ),
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            trackingPortProvider.overrideWithValue(port),
            weatherClientProvider.overrideWithValue(const NoWeather()),
          ],
          child: const MaterialApp(
            home: TripCelebrationHost(
              child: Scaffold(body: Center(child: Text('home'))),
            ),
          ),
        ),
      );
      // Boot: the controller restores the live trip, the first (empty)
      // snapshot primes the queue.
      await pumpFor(tester, const Duration(seconds: 1));

      await seedScoredTrip(
        db,
        id: 'scored-mid-drive',
        startedAt: 5000,
        score: 93,
        xp: 70,
        headline: 'Smooth from start to finish.',
      );
      await pumpFor(tester, const Duration(seconds: 1));
      // Still recording: no moment over the driving screen.
      expect(find.text('TRIP SCORED'), findsNothing);

      // Parked (the plugin dropped the tentative trip).
      port.emit(
        const PhaseEvent(
          tripId: liveId,
          t: 9000,
          phase: TripPhaseSignal.discarded,
        ),
      );
      await pumpFor(tester, const Duration(seconds: 2));
      expect(find.text('TRIP SCORED'), findsOneWidget);
      expect(find.text('Smooth from start to finish.'), findsOneWidget);
      expect(find.text('93'), findsOneWidget);

      await tester.tap(find.text('Nice'));
      await pumpFor(tester, const Duration(seconds: 1));
      expect(find.text('TRIP SCORED'), findsNothing);
      expect(
        await db.getSetting(CelebratedTripsStore.key),
        contains('scored-mid-drive'),
      );

      // The same trip re-scoring never celebrates twice.
      await db.updateTrip(
        'scored-mid-drive',
        const TripsCompanion(limitCoverage: Value(0.5)),
      );
      await pumpFor(tester, const Duration(seconds: 1));
      expect(find.text('TRIP SCORED'), findsNothing);
      await unmountAndSettle(tester);
    }, skip: skip);
  });
}

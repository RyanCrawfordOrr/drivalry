import 'package:drivalry/data/alerts/auto_checkin.dart';
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/tracking/tracking_models.dart';
import 'package:flutter_test/flutter_test.dart';

Place _home() => Place(
  id: 'home',
  label: 'Home',
  kind: 'home',
  lat: 38.9000,
  lon: -77.0300,
  radiusM: 150,
  createdAt: 0,
);

Place _work() => Place(
  id: 'work',
  label: 'Work',
  kind: 'work',
  lat: 38.9000,
  lon: -77.0300,
  radiusM: 150,
  createdAt: 0,
);

void main() {
  group('AutoCheckinEngine', () {
    test('checks in once per trip when inside Home after the end', () {
      final engine = AutoCheckinEngine();
      expect(
        engine.onPosition(lat: 38.9, lon: -77.03, atMs: 10, places: [_home()]),
        isNull,
        reason: 'no trip has ended yet',
      );
      engine.onTripEnded('t1', 1000);
      final first = engine.onPosition(
        lat: 38.9001,
        lon: -77.03,
        atMs: 2000,
        places: [_home()],
      );
      expect(first?.label, 'Home');
      expect(
        engine.onPosition(
          lat: 38.9001,
          lon: -77.03,
          atMs: 3000,
          places: [_home()],
        ),
        isNull,
        reason: 'same trip, already posted',
      );
      engine.onTripEnded('t2', 5000);
      expect(
        engine
            .onPosition(lat: 38.9, lon: -77.03, atMs: 6000, places: [_home()])
            ?.label,
        'Home',
      );
    });

    test('only Home-kind places and only within the window', () {
      final engine = AutoCheckinEngine(window: const Duration(minutes: 10));
      engine.onTripEnded('t1', 0);
      expect(
        engine.onPosition(
          lat: 38.9,
          lon: -77.03,
          atMs: 1000,
          places: [_work()],
        ),
        isNull,
      );
      expect(
        engine.onPosition(
          lat: 38.9,
          lon: -77.03,
          atMs: 11 * 60 * 1000,
          places: [_home()],
        ),
        isNull,
      );
      expect(
        engine.onPosition(
          lat: 38.95,
          lon: -77.03,
          atMs: 1000,
          places: [_home()],
        ),
        isNull,
        reason: 'outside the radius',
      );
    });
  });

  group('AutoCheckinRunner', () {
    test(
      'posts once from the last fix when the trip ends inside Home',
      () async {
        var enabled = true;
        final posted = <String>[];
        final runner = AutoCheckinRunner(
          engine: AutoCheckinEngine(),
          places: () async => [_home()],
          enabled: () async => enabled,
          checkIn: (label) async => posted.add(label),
        );
        await runner.onEvent(
          const FixesEvent(
            tripId: 't1',
            t: 900,
            fixes: [Fix(t: 900, lat: 38.9001, lon: -77.03, accuracy: 5)],
          ),
        );
        await runner.onEvent(
          const PhaseEvent(tripId: 't1', t: 1000, phase: TripPhaseSignal.ended),
        );
        expect(posted, ['Home']);
        // A parked fix a minute later: same arrival, no second post.
        await runner.onEvent(
          const ParkedFixEvent(
            t: 61_000,
            lat: 38.9001,
            lon: -77.03,
            accuracy: 20,
          ),
        );
        expect(posted, ['Home']);
      },
    );

    test('does nothing while the setting is off', () async {
      final posted = <String>[];
      final runner = AutoCheckinRunner(
        engine: AutoCheckinEngine(),
        places: () async => [_home()],
        enabled: () async => false,
        checkIn: (label) async => posted.add(label),
      );
      await runner.onEvent(
        const FixesEvent(
          tripId: 't1',
          t: 900,
          fixes: [Fix(t: 900, lat: 38.9, lon: -77.03, accuracy: 5)],
        ),
      );
      await runner.onEvent(
        const PhaseEvent(tripId: 't1', t: 1000, phase: TripPhaseSignal.ended),
      );
      expect(posted, isEmpty);
    });
  });
}

import 'dart:convert';

import 'package:drivalry/data/convoy/eta.dart';
import 'package:drivalry/data/google/google_quota.dart';
import 'package:drivalry/data/google/routes_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/sqlite_support.dart';

void main() {
  final skip = skipWithoutSqlite();

  test('formatEta', () {
    expect(formatEta(20), 'now');
    expect(formatEta(600), '10 min');
    expect(formatEta(3900), '1 h 05');
  });

  test('EtaInfo payload round trip', () {
    const e = EtaInfo(
      userId: 'u',
      seconds: 300,
      estimated: true,
      at: 5,
      distanceM: 4000,
      toStopId: 's1',
    );
    final back = EtaInfo.fromPayload('u', 5, e.toPayload())!;
    expect(back.seconds, 300);
    expect(back.estimated, isTrue);
    expect(back.distanceM, 4000);
    expect(back.toStopId, 's1');
    expect(EtaInfo.fromPayload('u', 5, {'nope': 1}), isNull);
  });

  group('EtaTracker', () {
    test('routes once, then extrapolates, then refreshes', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      var calls = 0;
      final client = MockClient((req) async {
        calls++;
        return http.Response(
          jsonEncode({
            'routes': [
              {
                'distanceMeters': 13000, // 10 km straight → ratio 1.3
                'duration': '650s', // 20 m/s
                'polyline': {'encodedPolyline': '_p~iF~ps|U_ulLnnqC'},
              },
            ],
          }),
          200,
        );
      });
      final routes = RoutesClient(client, GoogleQuota(db), apiKey: 'k');
      var now = 1_000_000;
      final tracker = EtaTracker(routes: routes, now: () => now);
      const target = LatLon(40.0, -100.0);
      // ~10 km south of the target (0.09° lat ≈ 10.0 km).
      final start = const LatLon(40.0 - 0.09, -100.0);

      final first = await tracker.maybeUpdate(
        me: start,
        speedMps: 25,
        target: target,
      );
      expect(first!.seconds, 650);
      expect(first.estimated, isFalse);
      expect(first.polyline, isNotEmpty);
      expect(calls, 1);

      // 30 s later: not due.
      now += 30_000;
      expect(
        await tracker.maybeUpdate(me: start, speedMps: 25, target: target),
        isNull,
      );

      // 60 s later, halfway there: extrapolated, no Routes call.
      now += 30_000;
      final half = await tracker.maybeUpdate(
        me: const LatLon(40.0 - 0.045, -100.0),
        speedMps: 25,
        target: target,
      );
      expect(calls, 1);
      expect(half!.seconds, closeTo(325, 10));
      expect(half.distanceM, closeTo(6500, 150));

      // Parked: no update even when due.
      now += 60_000;
      expect(
        await tracker.maybeUpdate(me: start, speedMps: 0, target: target),
        isNull,
      );

      // After five minutes a real route is fetched again.
      now += 5 * 60_000;
      await tracker.maybeUpdate(me: start, speedMps: 25, target: target);
      expect(calls, 2);

      // A new target routes immediately.
      now += 1000;
      await tracker.maybeUpdate(
        me: start,
        speedMps: 25,
        target: const LatLon(41, -100),
      );
      expect(calls, 3);
      expect(tracker.routeCalls, 3);
    }, skip: skip);

    test('falls back to the straight-line estimate without a key', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final routes = RoutesClient(
        MockClient((_) async => http.Response('', 500)),
        GoogleQuota(db),
        apiKey: '',
      );
      final tracker = EtaTracker(routes: routes, now: () => 1);
      final r = await tracker.maybeUpdate(
        me: const LatLon(40, -100),
        speedMps: 20,
        target: const LatLon(40.09, -100),
      );
      expect(r!.estimated, isTrue);
      expect(r.seconds, greaterThan(0));
    }, skip: skip);
  });
}

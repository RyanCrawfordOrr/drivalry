import 'dart:convert';

import 'package:drivalry/data/google/google_quota.dart';
import 'package:drivalry/data/google/places_client.dart';
import 'package:drivalry/data/google/routes_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/sqlite_support.dart';

void main() {
  final skip = skipWithoutSqlite();

  group('GoogleQuota', () {
    test('counts per api per UTC day and exhausts', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      var now = DateTime.utc(2026, 11, 3, 23, 50).millisecondsSinceEpoch;
      final q = GoogleQuota(db, now: () => now, placesPerDay: 2);
      expect(await q.tryConsume(GoogleQuota.places), isTrue);
      expect(await q.tryConsume(GoogleQuota.places), isTrue);
      expect(await q.tryConsume(GoogleQuota.places), isFalse);
      expect(await q.remaining(GoogleQuota.routes), 40);
      now += const Duration(minutes: 20).inMilliseconds; // next UTC day
      expect(await q.tryConsume(GoogleQuota.places), isTrue);
      await q.exhaust(GoogleQuota.places);
      expect(await q.tryConsume(GoogleQuota.places), isFalse);
    });
  }, skip: skip);

  group('RoutesClient', () {
    test('decodes a polyline', () {
      final pts = RoutesClient.decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@');
      expect(pts.length, 3);
      expect(pts.first.lat, closeTo(38.5, 1e-5));
      expect(pts.first.lon, closeTo(-120.2, 1e-5));
      expect(pts.last.lat, closeTo(43.252, 1e-5));
      expect(pts.last.lon, closeTo(-126.453, 1e-5));
    });

    test('parses a route and falls back to an estimate on 429', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final quota = GoogleQuota(db);
      var calls = 0;
      final client = MockClient((req) async {
        calls++;
        expect(req.headers['X-Goog-Api-Key'], 'k');
        expect(req.headers['X-Goog-FieldMask'], contains('distanceMeters'));
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['routingPreference'], 'TRAFFIC_UNAWARE');
        if (calls == 1) {
          return http.Response(
            jsonEncode({
              'routes': [
                {
                  'distanceMeters': 12345,
                  'duration': '900s',
                  'polyline': {'encodedPolyline': '_p~iF~ps|U_ulLnnqC'},
                },
              ],
            }),
            200,
          );
        }
        return http.Response('{"error":"RESOURCE_EXHAUSTED"}', 429);
      });
      final routes = RoutesClient(client, quota, apiKey: 'k');
      final a = const LatLon(38.9, -77.03);
      final b = const LatLon(39.0, -76.9);

      final r1 = await routes.route(a, b);
      expect(r1.estimated, isFalse);
      expect(r1.distanceM, 12345);
      expect(r1.duration, const Duration(minutes: 15));
      expect(r1.polyline.length, 2);

      final r2 = await routes.route(a, b);
      expect(r2.estimated, isTrue);
      expect(r2.polyline, isEmpty);
      expect(r2.distanceM, closeTo(a.distanceTo(b) * 1.3, 1));
      // Quota is now exhausted: no further HTTP calls.
      final r3 = await routes.route(a, b);
      expect(r3.estimated, isTrue);
      expect(calls, 2);
    }, skip: skip);

    test('no key means estimate without network', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final client = MockClient((_) async => fail('must not call'));
      final routes = RoutesClient(client, GoogleQuota(db), apiKey: '');
      final r = await routes.route(const LatLon(0, 0), const LatLon(0, 1));
      expect(r.estimated, isTrue);
      expect(r.distanceM, greaterThan(100000));
    }, skip: skip);
  });

  group('PlacesClient', () {
    test('maps suggestions and returns null past the cap', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final quota = GoogleQuota(db, placesPerDay: 1);
      final client = MockClient((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['includedTypes'], contains('gas_station'));
        return http.Response(
          jsonEncode({
            'places': [
              {
                'id': 'p1',
                'displayName': {'text': 'Sheetz', 'languageCode': 'en'},
                'location': {'latitude': 38.9, 'longitude': -77.0},
                'formattedAddress': '1 Main St',
                'rating': 4.2,
                'currentOpeningHours': {'openNow': true},
              },
            ],
          }),
          200,
        );
      });
      final places = PlacesClient(client, quota, apiKey: 'k');
      final list = await places.nearby(
        const LatLon(38.9, -77.0),
        StopCategory.gas,
      );
      expect(list, isNotNull);
      expect(list!.single.name, 'Sheetz');
      expect(list.single.openNow, isTrue);
      expect(list.single.rating, 4.2);
      expect(
        await places.nearby(const LatLon(38.9, -77.0), StopCategory.gas),
        isNull,
      );
    }, skip: skip);
  });
}

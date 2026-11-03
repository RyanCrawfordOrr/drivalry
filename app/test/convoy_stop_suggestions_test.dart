import 'package:drivalry/data/convoy/stop_suggestions.dart';
import 'package:drivalry/data/google/google_quota.dart';
import 'package:drivalry/data/google/places_client.dart';
import 'package:drivalry/data/google/routes_client.dart' show LatLon;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/sqlite_support.dart';

void main() {
  final skip = skipWithoutSqlite();

  group('samplePoints', () {
    test('picks the start and two thirds along by distance', () {
      final route = [
        for (var i = 0; i <= 30; i++) LatLon(40.0 + i * 0.01, -100.0),
      ];
      final pts = samplePoints(route);
      expect(pts.length, 3);
      expect(pts[0].lat, 40.0);
      expect(pts[1].lat, closeTo(40.10, 0.011));
      expect(pts[2].lat, closeTo(40.20, 0.011));
    });

    test('degenerate routes', () {
      expect(samplePoints(const []), isEmpty);
      expect(samplePoints(const [LatLon(1, 1)]).single.lat, 1);
    });
  });

  test('distanceToRoute uses vertices and midpoints', () {
    const route = [LatLon(40.0, -100.0), LatLon(40.0, -99.9)];
    // Right between the two vertices, 1.1 km north.
    final d = distanceToRoute(const LatLon(40.01, -99.95), route);
    expect(d, closeTo(1112, 20));
    expect(distanceToRoute(const LatLon(1, 1), const []), double.infinity);
  });

  group('suggestStops', () {
    const route = [LatLon(40.0, -100.0), LatLon(40.5, -100.0)];

    test('null when Places answered nowhere', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final places = PlacesClient(
        MockClient((_) async => http.Response('', 429)),
        GoogleQuota(db),
        apiKey: 'k',
      );
      expect(
        await suggestStops(
          places: places,
          category: StopCategory.food,
          remainingRoute: route,
        ),
        isNull,
      );
      expect(
        await suggestStops(
          places: places,
          category: StopCategory.food,
          remainingRoute: const [],
        ),
        isNull,
      );
    });

    test('dedupes by place id and sorts by detour', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      var calls = 0;
      final places = PlacesClient(
        MockClient((req) async {
          calls++;
          return http.Response(
            '{"places": ['
            '{"id": "near", "displayName": {"text": "Near"}, '
            '"location": {"latitude": 40.25, "longitude": -100.001}},'
            '{"id": "far", "displayName": {"text": "Far"}, '
            '"location": {"latitude": 40.25, "longitude": -100.2}}'
            ']}',
            200,
          );
        }),
        GoogleQuota(db),
        apiKey: 'k',
      );
      final found = await suggestStops(
        places: places,
        category: StopCategory.gas,
        remainingRoute: route,
      );
      expect(calls, 3, reason: 'one lookup per sample point');
      expect(found!.map((s) => s.place.placeId), ['near', 'far']);
      expect(found.first.detourM, lessThan(200));
      expect(found.last.detourM, greaterThan(10000));
    });

    test('empty when every point had nothing', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final places = PlacesClient(
        MockClient((_) async => http.Response('{"places": []}', 200)),
        GoogleQuota(db),
        apiKey: 'k',
      );
      expect(
        await suggestStops(
          places: places,
          category: StopCategory.food,
          remainingRoute: route,
        ),
        isEmpty,
      );
    });
  }, skip: skip);
}

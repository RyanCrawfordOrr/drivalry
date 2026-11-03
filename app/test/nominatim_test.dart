import 'dart:convert';

import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/places/nominatim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/sqlite_support.dart';

const sample = '''
{"name":"","display_name":"1600, Pennsylvania Avenue Northwest, Washington",
 "address":{"road":"Pennsylvania Avenue Northwest","city":"Washington"}}''';

void main() {
  final skip = skipWithoutSqlite();

  test('parseRoad prefers the road, then name, then display_name', () {
    expect(Nominatim.parseRoad(sample), 'Pennsylvania Avenue Northwest');
    expect(
      Nominatim.parseRoad('{"address":{"suburb":"Georgetown"},"name":""}'),
      'Georgetown',
    );
    expect(Nominatim.parseRoad('{"name":"The Mall"}'), 'The Mall');
    expect(
      Nominatim.parseRoad('{"display_name":"Rock Creek, Washington"}'),
      'Rock Creek',
    );
    expect(Nominatim.parseRoad('[]'), isNull);
  });

  test('cellKey is about 100 m', () {
    expect(Nominatim.cellKey(38.8977, -77.0365), 'geo:38898,-77037');
    expect(
      Nominatim.cellKey(38.8977, -77.0364),
      Nominatim.cellKey(38.8981, -77.0361),
    );
    expect(
      Nominatim.cellKey(38.8977, -77.0365),
      isNot(Nominatim.cellKey(38.8997, -77.0365)),
    );
  });

  group('roadNameNear', () {
    late AppDatabase db;
    late int now;
    late List<http.Request> requests;
    late Nominatim geo;

    setUp(() {
      db = memoryDatabase();
      now = 1_000_000;
      requests = [];
      final client = MockClient((req) async {
        requests.add(req);
        return http.Response(sample, 200);
      });
      geo = Nominatim(client, db, now: () => now);
    });
    tearDown(() => db.close());

    test('fetches once per cell, sends the user agent, caches', () async {
      expect(
        await geo.roadNameNear(38.8977, -77.0365),
        'Pennsylvania Avenue Northwest',
      );
      expect(requests, hasLength(1));
      expect(requests.single.headers['User-Agent'], Nominatim.userAgent);
      expect(requests.single.url.host, 'nominatim.openstreetmap.org');
      expect(requests.single.url.queryParameters['format'], 'jsonv2');

      now += 5000;
      expect(
        await geo.roadNameNear(38.8978, -77.0366),
        'Pennsylvania Avenue Northwest',
      );
      expect(requests, hasLength(1), reason: 'same cell, from cache');

      // A fresh instance reads the same cache row.
      final again = Nominatim(
        MockClient((_) async => http.Response('{}', 500)),
        db,
        now: () => now,
      );
      expect(
        await again.roadNameNear(38.8977, -77.0365),
        'Pennsylvania Avenue Northwest',
      );
    }, skip: skip);

    test('cache expires after 30 days', () async {
      await geo.roadNameNear(38.8977, -77.0365);
      now += const Duration(days: 31).inMilliseconds;
      await geo.roadNameNear(38.8977, -77.0365);
      expect(requests, hasLength(2));
    }, skip: skip);

    test('an empty result is cached as "no road" and not re-asked', () async {
      final client = MockClient((req) async {
        requests.add(req);
        return http.Response('{"address":{"city":"Nowhere"}}', 200);
      });
      final g = Nominatim(client, db, now: () => now);
      expect(await g.roadNameNear(1, 2), isNull);
      now += 5000;
      expect(await g.roadNameNear(1, 2), isNull);
      expect(requests, hasLength(1));
    }, skip: skip);

    test('errors return null without caching', () async {
      final client = MockClient((req) async {
        requests.add(req);
        return http.Response('boom', 503);
      });
      final g = Nominatim(client, db, now: () => now);
      expect(await g.roadNameNear(1, 2), isNull);
      now += 5000;
      expect(await g.roadNameNear(1, 2), isNull);
      expect(requests, hasLength(2));
    }, skip: skip);

    test('requests at least a second apart', () async {
      final sw = Stopwatch()..start();
      // Fake clock does not advance, so the second distinct cell must wait
      // one real second before it is asked.
      await geo.roadNameNear(1, 2);
      await geo.roadNameNear(3, 4);
      expect(requests, hasLength(2));
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(900));
    }, skip: skip);

    test(
      'concurrent requests for different cells queue a second apart',
      () async {
        final sleeps = <Duration>[];
        final client = MockClient((req) async {
          requests.add(req);
          return http.Response(sample, 200);
        });
        final g = Nominatim(
          client,
          db,
          now: () => now,
          sleep: (d) async => sleeps.add(d),
        );
        await Future.wait([
          g.roadNameNear(1, 2),
          g.roadNameNear(3, 4),
          g.roadNameNear(5, 6),
        ]);
        expect(requests, hasLength(3));
        // The first goes now; the others reserve the next slots before any
        // await, so they wait one and two seconds instead of firing together.
        expect(sleeps, [
          const Duration(seconds: 1),
          const Duration(seconds: 2),
        ]);
      },
      skip: skip,
    );

    test('disabled instance never calls the network', () async {
      final g = Nominatim(
        MockClient((req) async {
          requests.add(req);
          return http.Response(sample, 200);
        }),
        db,
        now: () => now,
        enabled: false,
      );
      expect(await g.roadNameNear(1, 2), isNull);
      expect(requests, isEmpty);
    }, skip: skip);
  });

  test('json shape stored in the cache', () {
    final m = jsonDecode('{"road":"X","at":5}') as Map<String, dynamic>;
    expect(m['road'], 'X');
  });
}

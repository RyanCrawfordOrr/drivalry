import 'dart:convert';

import 'package:drivalry/features/convoy/radio/ice_servers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/sqlite_support.dart';

void main() {
  final skip = skipWithoutSqlite();

  test('without Metered values: STUN only, no network', () async {
    final db = memoryDatabase();
    addTearDown(db.close);
    final client = MockClient((_) async => fail('must not call'));
    final p = IceServersProvider(
      db,
      client,
      meteredDomain: '',
      meteredApiKey: '',
    );
    final r = await p.servers();
    expect(r.relay, isFalse);
    expect(r.servers, IceServersProvider.stunOnly);
  }, skip: skip);

  test('fetches, caches for 12 h, refreshes after', () async {
    final db = memoryDatabase();
    addTearDown(db.close);
    var now = 1_000_000;
    var calls = 0;
    final client = MockClient((req) async {
      calls++;
      expect(req.url.host, 'x.metered.live');
      expect(req.url.queryParameters['apiKey'], 'k');
      return http.Response(
        jsonEncode([
          {
            'urls': 'turn:x.metered.live:80',
            'username': 'u',
            'credential': 'c',
          },
        ]),
        200,
      );
    });
    final p = IceServersProvider(
      db,
      client,
      meteredDomain: 'x.metered.live',
      meteredApiKey: 'k',
      now: () => now,
    );
    final r1 = await p.servers();
    expect(r1.relay, isTrue);
    expect(r1.servers.first, IceServersProvider.stunOnly.first);
    expect(r1.servers.last['urls'], 'turn:x.metered.live:80');
    now += const Duration(hours: 11).inMilliseconds;
    final r2 = await p.servers();
    expect(r2.servers, r1.servers);
    expect(calls, 1, reason: 'served from cache');
    now += const Duration(hours: 2).inMilliseconds;
    await p.servers();
    expect(calls, 2);
  }, skip: skip);

  test('a failing fetch falls back to STUN only', () async {
    final db = memoryDatabase();
    addTearDown(db.close);
    final client = MockClient((_) async => http.Response('nope', 500));
    final p = IceServersProvider(
      db,
      client,
      meteredDomain: 'x.metered.live',
      meteredApiKey: 'k',
    );
    final r = await p.servers();
    expect(r.relay, isFalse);
    expect(r.servers, IceServersProvider.stunOnly);
  }, skip: skip);
}

import 'dart:convert';

import 'package:drivalry/data/spotify/spotify_auth.dart';
import 'package:drivalry/data/spotify/spotify_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  SpotifyAuth signedIn(http.Client c) => SpotifyAuth(
    c,
    InMemorySpotifyTokenStore()
      ..tokens = const SpotifyTokens(
        accessToken: 'tok',
        refreshToken: 'r',
        expiresAtMs: 1 << 50,
      ),
    clientId: 'cid',
    now: () => 0,
  );

  String err(int status, {String? reason, String? message}) => jsonEncode({
    'error': {'status': status, 'reason': ?reason, 'message': ?message},
  });

  group('mapError', () {
    test('403 PREMIUM_REQUIRED', () {
      final e = SpotifyClient.mapError(
        403,
        err(403, reason: 'PREMIUM_REQUIRED'),
      );
      expect(e.kind, SpotifyErrorKind.premiumRequired);
      expect(e.message, 'Convoy DJ needs Spotify Premium on this account.');
    });

    test('other 403s and any 401 mean the allowlist', () {
      final e = SpotifyClient.mapError(
        403,
        err(403, message: 'User not registered in the Developer Dashboard'),
      );
      expect(e.kind, SpotifyErrorKind.notAllowlisted);
      expect(
        e.message,
        'Ask Ryan to add your Spotify account to the Drivalry allowlist.',
      );
      expect(
        SpotifyClient.mapError(401, err(401, message: 'bad token')).kind,
        SpotifyErrorKind.notAllowlisted,
      );
    });

    test('404 NO_ACTIVE_DEVICE', () {
      expect(
        SpotifyClient.mapError(404, err(404, reason: 'NO_ACTIVE_DEVICE')).kind,
        SpotifyErrorKind.noActiveDevice,
      );
      expect(
        SpotifyClient.mapError(404, 'not json').kind,
        SpotifyErrorKind.other,
      );
    });

    test('429 and the rest', () {
      expect(
        SpotifyClient.mapError(429, '').kind,
        SpotifyErrorKind.rateLimited,
      );
      expect(SpotifyClient.mapError(500, 'boom').kind, SpotifyErrorKind.other);
      expect(SpotifyClient.mapError(500, 'boom').detail, 'HTTP 500');
    });
  });

  test('play sends the uri and position with the bearer token', () async {
    late http.Request seen;
    final client = MockClient((req) async {
      seen = req;
      return http.Response('', 204);
    });
    await SpotifyClient(
      client,
      signedIn(client),
    ).play('spotify:track:1', positionMs: 1234);
    expect(seen.method, 'PUT');
    expect(seen.url.toString(), 'https://api.spotify.com/v1/me/player/play');
    expect(seen.headers['Authorization'], 'Bearer tok');
    expect(jsonDecode(seen.body), {
      'uris': ['spotify:track:1'],
      'position_ms': 1234,
    });
  });

  test(
    'pause and seek hit the player endpoints; negative seeks clamp',
    () async {
      final seen = <http.Request>[];
      final client = MockClient((req) async {
        seen.add(req);
        return http.Response('', 204);
      });
      final c = SpotifyClient(client, signedIn(client));
      await c.pause();
      await c.seek(-50);
      expect(seen[0].url.path, '/v1/me/player/pause');
      expect(seen[1].url.path, '/v1/me/player/seek');
      expect(seen[1].url.queryParameters['position_ms'], '0');
    },
  );

  test('search parses tracks and picks the smallest art', () async {
    late http.Request seen;
    final client = MockClient((req) async {
      seen = req;
      return http.Response(
        jsonEncode({
          'tracks': {
            'items': [
              {
                'uri': 'spotify:track:x',
                'name': 'Song',
                'duration_ms': 200000,
                'artists': [
                  {'name': 'A'},
                  {'name': 'B'},
                ],
                'album': {
                  'images': [
                    {'url': 'big'},
                    {'url': 'small'},
                  ],
                },
              },
            ],
          },
        }),
        200,
      );
    });
    final tracks = await SpotifyClient(client, signedIn(client)).search('song');
    expect(seen.url.path, '/v1/search');
    expect(seen.url.queryParameters['q'], 'song');
    expect(seen.url.queryParameters['type'], 'track');
    final t = tracks.single;
    expect(t.uri, 'spotify:track:x');
    expect(t.name, 'Song');
    expect(t.artists, 'A, B');
    expect(t.durationMs, 200000);
    expect(t.imageUrl, 'small');
    // The wire form used inside `dj play` commands round-trips.
    expect(SpotifyTrack.fromJson(t.toJson()).artists, 'A, B');
  });

  test('blank searches do not hit the network', () async {
    var calls = 0;
    final client = MockClient((req) async {
      calls++;
      return http.Response('{}', 200);
    });
    expect(
      await SpotifyClient(client, signedIn(client)).search('   '),
      isEmpty,
    );
    expect(calls, 0);
  });

  test('currentlyPlaying handles no content and a playing track', () async {
    var body = '';
    var status = 204;
    final client = MockClient((req) async => http.Response(body, status));
    final c = SpotifyClient(client, signedIn(client));
    expect(await c.currentlyPlaying(), isNull);

    status = 200;
    body = jsonEncode({
      'is_playing': true,
      'progress_ms': 4321,
      'device': {'name': 'Car'},
      'item': {'uri': 'spotify:track:y', 'name': 'Y', 'artists': []},
    });
    final np = await c.currentlyPlaying();
    expect(np!.isPlaying, isTrue);
    expect(np.progressMs, 4321);
    expect(np.deviceName, 'Car');
    expect(np.track?.uri, 'spotify:track:y');
  });

  test('not signed in fails before any request', () async {
    var calls = 0;
    final client = MockClient((req) async {
      calls++;
      return http.Response('', 200);
    });
    final auth = SpotifyAuth(
      client,
      InMemorySpotifyTokenStore(),
      clientId: 'cid',
      now: () => 0,
    );
    await expectLater(
      SpotifyClient(client, auth).pause(),
      throwsA(
        isA<SpotifyException>().having(
          (e) => e.kind,
          'kind',
          SpotifyErrorKind.notSignedIn,
        ),
      ),
    );
    expect(calls, 0);
  });

  test('HTTP failures become typed exceptions', () async {
    final client = MockClient(
      (req) async => http.Response(err(403, reason: 'PREMIUM_REQUIRED'), 403),
    );
    await expectLater(
      SpotifyClient(client, signedIn(client)).pause(),
      throwsA(
        isA<SpotifyException>().having(
          (e) => e.kind,
          'kind',
          SpotifyErrorKind.premiumRequired,
        ),
      ),
    );
  });
}

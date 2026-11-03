import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drivalry/data/spotify/spotify_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Pretends to be the system browser: records the URL it was asked to open
/// and answers with a callback carrying the same `state`.
class FakeBrowser implements AuthBrowser {
  Uri? opened;
  String? callbackScheme;
  String? error;
  bool wrongState = false;

  @override
  Future<String> authenticate(Uri url, String scheme) async {
    opened = url;
    callbackScheme = scheme;
    final state = wrongState ? 'nope' : url.queryParameters['state'];
    if (error != null) {
      return 'drivalry-auth://spotify-callback?error=$error&state=$state';
    }
    return 'drivalry-auth://spotify-callback?code=the-code&state=$state';
  }
}

void main() {
  const now = 1_000_000;
  late List<http.Request> requests;
  late Map<String, String> lastForm;

  http.Client client({int status = 200, Map<String, Object?>? body}) =>
      MockClient((req) async {
        requests.add(req);
        lastForm = Uri.splitQueryString(req.body);
        return http.Response(
          jsonEncode(
            body ??
                {
                  'access_token': 'at1',
                  'refresh_token': 'rt1',
                  'expires_in': 3600,
                },
          ),
          status,
        );
      });

  setUp(() {
    requests = [];
    lastForm = {};
  });

  test(
    'signIn runs PKCE against the token endpoint and stores tokens',
    () async {
      final store = InMemorySpotifyTokenStore();
      final browser = FakeBrowser();
      final auth = SpotifyAuth(
        client(),
        store,
        browser: browser,
        clientId: 'cid',
        now: () => now,
      );
      final tokens = await auth.signIn();

      expect(tokens.accessToken, 'at1');
      expect(store.tokens?.refreshToken, 'rt1');
      expect(store.tokens?.expiresAtMs, now + 3600 * 1000);
      expect(browser.callbackScheme, 'drivalry-auth');

      final q = browser.opened!.queryParameters;
      expect(browser.opened!.host, 'accounts.spotify.com');
      expect(q['client_id'], 'cid');
      expect(q['response_type'], 'code');
      expect(q['redirect_uri'], 'drivalry-auth://spotify-callback');
      expect(q['code_challenge_method'], 'S256');
      expect(q['scope'], contains('user-modify-playback-state'));
      expect(q['scope'], contains('user-read-playback-state'));
      expect(q['scope'], contains('user-read-currently-playing'));

      // The verifier sent to the token endpoint hashes to the challenge shown
      // to the browser, and no client secret travels anywhere.
      final verifier = lastForm['code_verifier']!;
      expect(verifier.length, 64);
      final challenge = base64Url
          .encode(sha256.convert(ascii.encode(verifier)).bytes)
          .replaceAll('=', '');
      expect(q['code_challenge'], challenge);
      expect(lastForm['grant_type'], 'authorization_code');
      expect(lastForm['code'], 'the-code');
      expect(lastForm['client_id'], 'cid');
      expect(lastForm.containsKey('client_secret'), isFalse);
      expect(
        requests.single.url.toString(),
        'https://accounts.spotify.com/api/token',
      );
    },
  );

  test(
    'a state mismatch or a denial never reaches the token endpoint',
    () async {
      final store = InMemorySpotifyTokenStore();
      final auth = SpotifyAuth(
        client(),
        store,
        browser: FakeBrowser()..wrongState = true,
        clientId: 'cid',
        now: () => now,
      );
      await expectLater(auth.signIn(), throwsA(isA<SpotifyAuthException>()));
      expect(store.tokens, isNull);

      final denied = SpotifyAuth(
        client(),
        store,
        browser: FakeBrowser()..error = 'access_denied',
        clientId: 'cid',
        now: () => now,
      );
      await expectLater(denied.signIn(), throwsA(isA<SpotifyAuthException>()));
      expect(requests, isEmpty);
    },
  );

  test('without a client id nothing opens', () async {
    final browser = FakeBrowser();
    final auth = SpotifyAuth(
      client(),
      InMemorySpotifyTokenStore(),
      browser: browser,
      clientId: '',
      now: () => now,
    );
    expect(auth.configured, isFalse);
    await expectLater(auth.signIn(), throwsA(isA<SpotifyAuthException>()));
    expect(browser.opened, isNull);
  });

  test(
    'accessToken refreshes inside the margin and keeps the old refresh token',
    () async {
      final store = InMemorySpotifyTokenStore()
        ..tokens = const SpotifyTokens(
          accessToken: 'old',
          refreshToken: 'rt-old',
          expiresAtMs: now + 10_000,
        );
      final auth = SpotifyAuth(
        client(body: {'access_token': 'new', 'expires_in': 1800}),
        store,
        browser: FakeBrowser(),
        clientId: 'cid',
        now: () => now,
      );
      // 10 s left is inside the 30 s safety margin, so refresh now.
      expect(await auth.accessToken(), 'new');
      expect(lastForm['grant_type'], 'refresh_token');
      expect(lastForm['refresh_token'], 'rt-old');
      expect(store.tokens?.refreshToken, 'rt-old');
      expect(store.tokens?.expiresAtMs, now + 1800 * 1000);

      // Fresh token: no network.
      requests.clear();
      expect(await auth.accessToken(), 'new');
      expect(requests, isEmpty);
    },
  );

  test('a rejected refresh signs the user out', () async {
    final store = InMemorySpotifyTokenStore()
      ..tokens = const SpotifyTokens(
        accessToken: 'old',
        refreshToken: 'rt',
        expiresAtMs: now - 1,
      );
    final auth = SpotifyAuth(
      client(status: 400, body: {'error': 'invalid_grant'}),
      store,
      browser: FakeBrowser(),
      clientId: 'cid',
      now: () => now,
    );
    await expectLater(auth.accessToken(), throwsA(isA<SpotifyAuthException>()));
    expect(store.tokens, isNull);
    expect(await auth.isSignedIn, isFalse);
  });

  test('signed out means null and no network', () async {
    final auth = SpotifyAuth(
      client(),
      InMemorySpotifyTokenStore(),
      browser: FakeBrowser(),
      clientId: 'cid',
      now: () => now,
    );
    expect(await auth.accessToken(), isNull);
    expect(requests, isEmpty);
    await auth.signOut();
    expect(await auth.isSignedIn, isFalse);
  });

  test('tokens round-trip through json and expire with a margin', () {
    const t = SpotifyTokens(
      accessToken: 'a',
      refreshToken: 'r',
      expiresAtMs: 5,
    );
    final back = SpotifyTokens.fromJson(
      jsonDecode(jsonEncode(t.toJson())) as Map<String, dynamic>,
    );
    expect(back.accessToken, 'a');
    expect(back.refreshToken, 'r');
    expect(back.expiresAtMs, 5);
    expect(t.isExpired(5 - 30_000), isTrue);
    expect(t.isExpired(5 - 30_001), isFalse);
  });
}

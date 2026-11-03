import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;

import '../../config/env.dart';

/// Where Spotify tokens live. Secure storage in the app, memory in tests.
abstract class SpotifyTokenStore {
  Future<SpotifyTokens?> read();
  Future<void> write(SpotifyTokens? tokens);
}

class SpotifyTokens {
  const SpotifyTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAtMs,
  });

  final String accessToken;
  final String refreshToken;

  /// Epoch milliseconds when [accessToken] stops working.
  final int expiresAtMs;

  bool isExpired(int nowMs) => nowMs >= expiresAtMs - 30_000;

  Map<String, Object> toJson() => {
    'access': accessToken,
    'refresh': refreshToken,
    'expiresAt': expiresAtMs,
  };

  static SpotifyTokens fromJson(Map<String, dynamic> j) => SpotifyTokens(
    accessToken: j['access'] as String,
    refreshToken: j['refresh'] as String,
    expiresAtMs: (j['expiresAt'] as num).toInt(),
  );
}

class SecureSpotifyTokenStore implements SpotifyTokenStore {
  SecureSpotifyTokenStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _key = 'spotify_tokens';

  @override
  Future<SpotifyTokens?> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    return SpotifyTokens.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<void> write(SpotifyTokens? tokens) => tokens == null
      ? _storage.delete(key: _key)
      : _storage.write(key: _key, value: jsonEncode(tokens.toJson()));
}

class InMemorySpotifyTokenStore implements SpotifyTokenStore {
  SpotifyTokens? tokens;

  @override
  Future<SpotifyTokens?> read() async => tokens;

  @override
  Future<void> write(SpotifyTokens? t) async => tokens = t;
}

/// Opens the system browser for the user to approve. The app uses
/// flutter_web_auth_2; tests return a canned callback URL.
abstract class AuthBrowser {
  /// Returns the full callback URL (`drivalry-auth://spotify-callback?code=…`).
  Future<String> authenticate(Uri url, String callbackScheme);
}

class WebAuthBrowser implements AuthBrowser {
  @override
  Future<String> authenticate(Uri url, String callbackScheme) =>
      FlutterWebAuth2.authenticate(
        url: url.toString(),
        callbackUrlScheme: callbackScheme,
      );
}

/// Spotify Authorization Code with PKCE (no client secret). Scopes are the
/// three playback scopes Convoy DJ needs. The callback uses its own URL scheme
/// (`drivalry-auth`) so it never collides with the `drivalry://` invite links.
class SpotifyAuth {
  SpotifyAuth(
    this._http,
    this.store, {
    AuthBrowser? browser,
    String? clientId,
    int Function()? now,
    Random? random,
  }) : _browser = browser ?? WebAuthBrowser(),
       clientId = clientId ?? Env.spotifyClientId,
       _now = now ?? (() => DateTime.now().millisecondsSinceEpoch),
       _random = random ?? Random.secure();

  final http.Client _http;
  final SpotifyTokenStore store;
  final AuthBrowser _browser;
  final String clientId;
  final int Function() _now;
  final Random _random;

  static const callbackScheme = 'drivalry-auth';
  static const redirectUri = 'drivalry-auth://spotify-callback';
  static const scopes =
      'user-read-playback-state user-modify-playback-state user-read-currently-playing';
  static final Uri authorizeEndpoint = Uri.parse(
    'https://accounts.spotify.com/authorize',
  );
  static final Uri tokenEndpoint = Uri.parse(
    'https://accounts.spotify.com/api/token',
  );

  bool get configured => clientId.isNotEmpty;

  /// Runs the browser flow and stores the tokens.
  Future<SpotifyTokens> signIn() async {
    if (!configured) throw const SpotifyAuthException('not configured');
    final verifier = _randomString(64);
    final challenge = base64Url
        .encode(sha256.convert(ascii.encode(verifier)).bytes)
        .replaceAll('=', '');
    final state = _randomString(16);
    final url = authorizeEndpoint.replace(
      queryParameters: {
        'client_id': clientId,
        'response_type': 'code',
        'redirect_uri': redirectUri,
        'code_challenge_method': 'S256',
        'code_challenge': challenge,
        'scope': scopes,
        'state': state,
      },
    );
    final callback = Uri.parse(
      await _browser.authenticate(url, callbackScheme),
    );
    if (callback.queryParameters['state'] != state) {
      throw const SpotifyAuthException('state mismatch');
    }
    final error = callback.queryParameters['error'];
    if (error != null) throw SpotifyAuthException(error);
    final code = callback.queryParameters['code'];
    if (code == null) throw const SpotifyAuthException('no code in callback');
    final tokens = await _exchange({
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': redirectUri,
      'client_id': clientId,
      'code_verifier': verifier,
    }, previousRefresh: null);
    await store.write(tokens);
    return tokens;
  }

  /// A valid access token, refreshing when needed; null when signed out.
  Future<String?> accessToken() async {
    final t = await store.read();
    if (t == null) return null;
    if (!t.isExpired(_now())) return t.accessToken;
    final fresh = await _exchange({
      'grant_type': 'refresh_token',
      'refresh_token': t.refreshToken,
      'client_id': clientId,
    }, previousRefresh: t.refreshToken);
    await store.write(fresh);
    return fresh.accessToken;
  }

  Future<bool> get isSignedIn async => (await store.read()) != null;

  Future<void> signOut() => store.write(null);

  Future<SpotifyTokens> _exchange(
    Map<String, String> form, {
    required String? previousRefresh,
  }) async {
    final res = await _http.post(
      tokenEndpoint,
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: form,
    );
    if (res.statusCode != 200) {
      if (form['grant_type'] == 'refresh_token' &&
          (res.statusCode == 400 || res.statusCode == 401)) {
        await store.write(null);
        throw const SpotifyAuthException('session expired, sign in again');
      }
      throw SpotifyAuthException('token endpoint ${res.statusCode}');
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return SpotifyTokens(
      accessToken: j['access_token'] as String,
      // Spotify may omit the refresh token on refresh; keep the old one.
      refreshToken: (j['refresh_token'] as String?) ?? previousRefresh ?? '',
      expiresAtMs: _now() + ((j['expires_in'] as num?)?.toInt() ?? 3600) * 1000,
    );
  }

  String _randomString(int length) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    return String.fromCharCodes(
      List.generate(
        length,
        (_) => chars.codeUnitAt(_random.nextInt(chars.length)),
      ),
    );
  }
}

class SpotifyAuthException implements Exception {
  const SpotifyAuthException(this.message);
  final String message;
  @override
  String toString() => 'SpotifyAuthException($message)';
}

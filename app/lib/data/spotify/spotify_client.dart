import 'dart:convert';

import 'package:http/http.dart' as http;

import 'spotify_auth.dart';

/// Why a Spotify call failed, with the sentence the UI shows.
enum SpotifyErrorKind {
  notSignedIn('Connect Spotify first.'),
  premiumRequired('Convoy DJ needs Spotify Premium on this account.'),
  notAllowlisted(
    'Ask Ryan to add your Spotify account to the Drivalry allowlist.',
  ),
  noActiveDevice('Open Spotify and start playing anything, then try again.'),
  rateLimited('Spotify is asking us to slow down. Try again in a minute.'),
  network('Could not reach Spotify.'),
  other('Spotify returned an error.');

  const SpotifyErrorKind(this.message);
  final String message;
}

class SpotifyException implements Exception {
  const SpotifyException(this.kind, [this.detail]);
  final SpotifyErrorKind kind;
  final String? detail;
  String get message => kind.message;
  @override
  String toString() =>
      'SpotifyException(${kind.name}${detail == null ? '' : ': $detail'})';
}

class SpotifyTrack {
  const SpotifyTrack({
    required this.uri,
    required this.name,
    required this.artists,
    required this.durationMs,
    this.imageUrl,
  });

  final String uri;
  final String name;
  final String artists;
  final int durationMs;
  final String? imageUrl;

  Map<String, Object?> toJson() => {
    'uri': uri,
    'name': name,
    'artists': artists,
    'durationMs': durationMs,
    'imageUrl': ?imageUrl,
  };

  static SpotifyTrack fromJson(Map<String, dynamic> j) => SpotifyTrack(
    uri: j['uri'] as String,
    name: j['name'] as String,
    artists: j['artists'] as String? ?? '',
    durationMs: (j['durationMs'] as num?)?.toInt() ?? 0,
    imageUrl: j['imageUrl'] as String?,
  );

  static SpotifyTrack fromApi(Map<String, dynamic> t) => SpotifyTrack(
    uri: t['uri'] as String,
    name: t['name'] as String? ?? 'Unknown',
    artists: ((t['artists'] as List?) ?? const [])
        .map((a) => (a as Map<String, dynamic>)['name'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .join(', '),
    durationMs: (t['duration_ms'] as num?)?.toInt() ?? 0,
    imageUrl: _smallestImage(t['album']),
  );

  static String? _smallestImage(Object? album) {
    final images = (album as Map<String, dynamic>?)?['images'] as List?;
    if (images == null || images.isEmpty) return null;
    return (images.last as Map<String, dynamic>)['url'] as String?;
  }
}

class NowPlaying {
  const NowPlaying({
    required this.isPlaying,
    required this.progressMs,
    this.track,
    this.deviceName,
  });

  final bool isPlaying;
  final int progressMs;
  final SpotifyTrack? track;
  final String? deviceName;
}

/// The handful of Web API calls Convoy DJ uses. Every method throws
/// [SpotifyException] with a kind the UI can explain.
class SpotifyClient {
  SpotifyClient(this._http, this.auth);

  final http.Client _http;
  final SpotifyAuth auth;

  static const _base = 'https://api.spotify.com/v1';

  Future<NowPlaying?> currentlyPlaying() async {
    final res = await _get('/me/player');
    if (res.statusCode == 204 || res.body.isEmpty) return null;
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final item = j['item'] as Map<String, dynamic>?;
    return NowPlaying(
      isPlaying: j['is_playing'] == true,
      progressMs: (j['progress_ms'] as num?)?.toInt() ?? 0,
      track: item == null ? null : SpotifyTrack.fromApi(item),
      deviceName: (j['device'] as Map<String, dynamic>?)?['name'] as String?,
    );
  }

  Future<void> play(String uri, {int positionMs = 0}) => _put(
    '/me/player/play',
    body: {
      'uris': [uri],
      'position_ms': positionMs < 0 ? 0 : positionMs,
    },
  );

  Future<void> pause() => _put('/me/player/pause');

  Future<void> seek(int positionMs) =>
      _put('/me/player/seek?position_ms=${positionMs < 0 ? 0 : positionMs}');

  Future<List<SpotifyTrack>> search(String query, {int limit = 10}) async {
    if (query.trim().isEmpty) return const [];
    final res = await _get(
      '/search?${Uri(queryParameters: {'q': query, 'type': 'track', 'limit': '$limit'}).query}',
    );
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final items =
        ((j['tracks'] as Map<String, dynamic>?)?['items'] as List?) ?? const [];
    return [
      for (final t in items) SpotifyTrack.fromApi(t as Map<String, dynamic>),
    ];
  }

  Future<List<String>> devices() async {
    final res = await _get('/me/player/devices');
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return [
      for (final d in (j['devices'] as List? ?? const []))
        (d as Map<String, dynamic>)['name'] as String? ?? 'device',
    ];
  }

  Future<http.Response> _get(String path) => _send(
    (token) => _http.get(
      Uri.parse('$_base$path'),
      headers: {'Authorization': 'Bearer $token'},
    ),
  );

  Future<http.Response> _put(String path, {Object? body}) => _send(
    (token) => _http.put(
      Uri.parse('$_base$path'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: body == null ? null : jsonEncode(body),
    ),
  );

  Future<http.Response> _send(
    Future<http.Response> Function(String token) call,
  ) async {
    String? token;
    try {
      token = await auth.accessToken();
    } on SpotifyAuthException {
      throw const SpotifyException(SpotifyErrorKind.notSignedIn);
    }
    if (token == null) {
      throw const SpotifyException(SpotifyErrorKind.notSignedIn);
    }
    http.Response res;
    try {
      res = await call(token).timeout(const Duration(seconds: 10));
    } catch (e) {
      throw SpotifyException(SpotifyErrorKind.network, e.toString());
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return res;
    throw mapError(res.statusCode, res.body);
  }

  /// Turns an HTTP failure into something the UI can say.
  static SpotifyException mapError(int status, String body) {
    final reason = _reason(body);
    switch (status) {
      case 401:
        // In Development Mode Spotify answers 401/403 for users who are not
        // on the app's allowlist.
        return SpotifyException(SpotifyErrorKind.notAllowlisted, reason);
      case 403:
        if (reason == 'PREMIUM_REQUIRED') {
          return const SpotifyException(SpotifyErrorKind.premiumRequired);
        }
        return SpotifyException(SpotifyErrorKind.notAllowlisted, reason);
      case 404:
        if (reason == 'NO_ACTIVE_DEVICE' || body.contains('NO_ACTIVE_DEVICE')) {
          return const SpotifyException(SpotifyErrorKind.noActiveDevice);
        }
        return SpotifyException(SpotifyErrorKind.other, 'HTTP 404');
      case 429:
        return const SpotifyException(SpotifyErrorKind.rateLimited);
      default:
        return SpotifyException(SpotifyErrorKind.other, 'HTTP $status');
    }
  }

  static String? _reason(String body) {
    try {
      final j = jsonDecode(body) as Map<String, dynamic>;
      final err = j['error'];
      if (err is Map<String, dynamic>) {
        return (err['reason'] as String?) ?? (err['message'] as String?);
      }
    } catch (_) {}
    return null;
  }
}

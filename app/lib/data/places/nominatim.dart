import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../db/database.dart';

/// Reverse geocoding for labels only ("near Elm St"), used when the trip's
/// own matched road name is missing. Budget rules from docs/03 §10: at most
/// one request per second, results cached by 100 m cell for 30 days, a real
/// User-Agent, and never on the critical path (callers await it lazily).
class Nominatim {
  Nominatim(
    this.client,
    this.db, {
    int Function()? now,
    Future<void> Function(Duration)? sleep,
    this.enabled = true,
  }) : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch),
       _sleep = sleep ?? ((d) => Future<void>.delayed(d));

  final http.Client client;
  final AppDatabase db;
  final int Function() _now;
  final Future<void> Function(Duration) _sleep;

  /// Off in tests and offline builds.
  final bool enabled;

  static const userAgent =
      'Drivalry/0.1 (https://github.com/RyanCrawfordOrr/drivalry)';
  static const Duration minSpacing = Duration(seconds: 1);
  static const Duration cacheTtl = Duration(days: 30);

  int _lastRequestAt = 0;
  final Map<String, Future<String?>> _inFlight = {};

  /// Cache key: about 100 m cells (0.001° of latitude is 111 m).
  static String cellKey(double lat, double lon) =>
      'geo:${(lat * 1000).round()},${(lon * 1000).round()}';

  /// The road name near a point, or null when unknown, rate-limited, or
  /// offline. An empty string is cached when the place has no road name so
  /// the same spot is not asked again.
  Future<String?> roadNameNear(double lat, double lon) async {
    final key = cellKey(lat, lon);
    final cached = await db.cacheGet(key);
    if (cached != null) {
      final m = jsonDecode(cached) as Map<String, dynamic>;
      final at = (m['at'] as num?)?.toInt() ?? 0;
      if (_now() - at < cacheTtl.inMilliseconds) {
        final road = m['road'] as String?;
        return (road == null || road.isEmpty) ? null : road;
      }
    }
    if (!enabled) return null;
    // The callback must not return the removed future, or whenComplete would
    // wait on the future it is itself producing.
    return _inFlight[key] ??= _fetch(key, lat, lon).whenComplete(() {
      _inFlight.remove(key);
    });
  }

  /// Reserves the next request slot synchronously (no await before the
  /// reservation), so concurrent callers for different cells queue a second
  /// apart instead of all firing together. Returns how long to wait.
  Duration _reserveSlot() {
    final now = _now();
    final earliest = _lastRequestAt + minSpacing.inMilliseconds;
    final scheduled = earliest > now ? earliest : now;
    _lastRequestAt = scheduled;
    return Duration(milliseconds: scheduled - now);
  }

  Future<String?> _fetch(String key, double lat, double lon) async {
    final wait = _reserveSlot();
    if (wait > Duration.zero) await _sleep(wait);
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'format': 'jsonv2',
        'lat': lat.toStringAsFixed(6),
        'lon': lon.toStringAsFixed(6),
        'zoom': '17',
        'addressdetails': '1',
      });
      final res = await client
          .get(
            uri,
            headers: {'User-Agent': userAgent, 'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final road = parseRoad(res.body);
      await db.cachePut(
        key,
        jsonEncode({'road': road ?? '', 'at': _now()}),
        _now(),
      );
      return road;
    } catch (e) {
      debugPrint('nominatim failed: $e');
      return null;
    }
  }

  /// The best road-like name in a Nominatim `jsonv2` reverse response.
  static String? parseRoad(String body) {
    final json = jsonDecode(body);
    if (json is! Map) return null;
    final address = json['address'];
    if (address is Map) {
      for (final k in const [
        'road',
        'pedestrian',
        'footway',
        'residential',
        'neighbourhood',
        'suburb',
      ]) {
        final v = address[k];
        if (v is String && v.isNotEmpty) return v;
      }
    }
    final name = json['name'];
    if (name is String && name.isNotEmpty) return name;
    final display = json['display_name'];
    if (display is String && display.isNotEmpty) {
      return display.split(',').first.trim();
    }
    return null;
  }
}

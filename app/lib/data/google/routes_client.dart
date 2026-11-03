import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../config/env.dart';
import '../../tracking/providers.dart';
import 'google_quota.dart';

/// A point on the map.
class LatLon {
  const LatLon(this.lat, this.lon);
  final double lat;
  final double lon;

  /// Great-circle distance in metres.
  double distanceTo(LatLon other) {
    const r = 6371000.0;
    final dLat = _rad(other.lat - lat);
    final dLon = _rad(other.lon - lon);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat)) *
            math.cos(_rad(other.lat)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return 2 * r * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _rad(double deg) => deg * math.pi / 180;

  Map<String, Object> toJson() => {'latitude': lat, 'longitude': lon};
}

/// One route from the Routes API, or the straight-line estimate used when the
/// quota is spent or the network is down (`estimated == true`).
class RouteResult {
  const RouteResult({
    required this.distanceM,
    required this.duration,
    required this.polyline,
    required this.estimated,
  });

  final double distanceM;
  final Duration duration;

  /// Decoded path (empty for estimates).
  final List<LatLon> polyline;
  final bool estimated;
}

/// Google Routes API (`computeRoutes`), Essentials SKU only: no traffic-aware
/// routing, no extra computations, at most 10 waypoints, so every call stays
/// inside the 10,000 free requests a month (docs/03 §10).
class RoutesClient {
  RoutesClient(this._http, this._quota, {String? apiKey})
    : _apiKey = apiKey ?? Env.googleMapsApiKey;

  final http.Client _http;
  final GoogleQuota _quota;
  final String _apiKey;

  static final Uri _endpoint = Uri.parse(
    'https://routes.googleapis.com/directions/v2:computeRoutes',
  );

  /// Average speed used for the straight-line fallback (about 45 mph).
  static const fallbackMps = 20.0;

  /// Routes from [origin] to [destination] through up to 8 [waypoints].
  /// Never throws: any failure returns a straight-line estimate.
  Future<RouteResult> route(
    LatLon origin,
    LatLon destination, {
    List<LatLon> waypoints = const [],
  }) async {
    if (_apiKey.isEmpty || waypoints.length > 8) {
      return _estimate(origin, destination, waypoints);
    }
    if (!await _quota.tryConsume(GoogleQuota.routes)) {
      return _estimate(origin, destination, waypoints);
    }
    try {
      final res = await _http
          .post(
            _endpoint,
            headers: {
              'Content-Type': 'application/json',
              'X-Goog-Api-Key': _apiKey,
              'X-Goog-FieldMask':
                  'routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline',
            },
            body: jsonEncode({
              'origin': {
                'location': {'latLng': origin.toJson()},
              },
              'destination': {
                'location': {'latLng': destination.toJson()},
              },
              if (waypoints.isNotEmpty)
                'intermediates': [
                  for (final w in waypoints)
                    {
                      'location': {'latLng': w.toJson()},
                    },
                ],
              'travelMode': 'DRIVE',
              'routingPreference': 'TRAFFIC_UNAWARE',
              'polylineQuality': 'OVERVIEW',
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 429) {
        await _quota.exhaust(GoogleQuota.routes);
        return _estimate(origin, destination, waypoints);
      }
      if (res.statusCode != 200) {
        return _estimate(origin, destination, waypoints);
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final routes = body['routes'] as List? ?? const [];
      if (routes.isEmpty) return _estimate(origin, destination, waypoints);
      final r = routes.first as Map<String, dynamic>;
      final seconds =
          int.tryParse(
            (r['duration'] as String? ?? '0s').replaceAll('s', ''),
          ) ??
          0;
      final encoded =
          (r['polyline'] as Map<String, dynamic>?)?['encodedPolyline']
              as String?;
      return RouteResult(
        distanceM: (r['distanceMeters'] as num? ?? 0).toDouble(),
        duration: Duration(seconds: seconds),
        polyline: encoded == null ? const [] : decodePolyline(encoded),
        estimated: false,
      );
    } catch (_) {
      return _estimate(origin, destination, waypoints);
    }
  }

  RouteResult _estimate(LatLon origin, LatLon destination, List<LatLon> via) {
    var d = 0.0;
    var prev = origin;
    for (final p in [...via, destination]) {
      d += prev.distanceTo(p);
      prev = p;
    }
    // Roads are longer than the crow flies; 1.3 is the usual detour factor.
    d *= 1.3;
    return RouteResult(
      distanceM: d,
      duration: Duration(seconds: (d / fallbackMps).round()),
      polyline: const [],
      estimated: true,
    );
  }

  /// Google's encoded polyline algorithm.
  static List<LatLon> decodePolyline(String encoded) {
    final points = <LatLon>[];
    var index = 0;
    var lat = 0;
    var lon = 0;
    while (index < encoded.length) {
      int shift = 0, result = 0, b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lon += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      points.add(LatLon(lat / 1e5, lon / 1e5));
    }
    return points;
  }
}

final routesClientProvider = Provider<RoutesClient>(
  (ref) => RoutesClient(
    ref.watch(httpClientProvider),
    ref.watch(googleQuotaProvider),
  ),
);

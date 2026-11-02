/// Great-circle helpers. Mirrors `packages/scoring/src/geo.ts`.
///
/// Expressions keep the TypeScript operand order and association so floating-point results
/// match bit for bit wherever the platform `sin`/`cos`/`atan2` agree.
library;

import 'dart:math' as math;

/// Earth radius, m.
const double _r = 6371000;

double _toRad(double d) => (d * math.pi) / 180;
double _toDeg(double r) => (r * 180) / math.pi;

/// Great-circle distance in metres.
double haversine(double lat1, double lon1, double lat2, double lon2) {
  final dLat = _toRad(lat2 - lat1);
  final dLon = _toRad(lon2 - lon1);
  final sLat = math.sin(dLat / 2);
  final sLon = math.sin(dLon / 2);
  // TS: sin(dLat/2) ** 2 + cos(φ1) * cos(φ2) * sin(dLon/2) ** 2   (x ** 2 is exactly x * x)
  final a =
      sLat * sLat +
      math.cos(_toRad(lat1)) * math.cos(_toRad(lat2)) * (sLon * sLon);
  return 2 * _r * math.asin(math.min(1.0, math.sqrt(a)));
}

/// Initial bearing from point 1 to point 2, degrees 0–360.
double bearing(double lat1, double lon1, double lat2, double lon2) {
  final phi1 = _toRad(lat1);
  final phi2 = _toRad(lat2);
  final dLambda = _toRad(lon2 - lon1);
  final y = math.sin(dLambda) * math.cos(phi2);
  final x =
      math.cos(phi1) * math.sin(phi2) -
      math.sin(phi1) * math.cos(phi2) * math.cos(dLambda);
  // JS `%` keeps the dividend's sign; Dart's `remainder` does the same (`%` does not).
  return (_toDeg(math.atan2(y, x)) + 360).remainder(360);
}

/// Destination point given start, bearing (deg) and distance (m).
({double lat, double lon}) destination(
  double lat,
  double lon,
  double bearingDeg,
  double distanceM,
) {
  final delta = distanceM / _r;
  final theta = _toRad(bearingDeg);
  final phi1 = _toRad(lat);
  final lambda1 = _toRad(lon);
  final phi2 = math.asin(
    math.sin(phi1) * math.cos(delta) +
        math.cos(phi1) * math.sin(delta) * math.cos(theta),
  );
  final lambda2 =
      lambda1 +
      math.atan2(
        math.sin(theta) * math.sin(delta) * math.cos(phi1),
        math.cos(delta) - math.sin(phi1) * math.sin(phi2),
      );
  return (lat: _toDeg(phi2), lon: (_toDeg(lambda2) + 540).remainder(360) - 180);
}

/// Smallest signed difference between two headings, degrees in (-180, 180].
double headingDelta(double from, double to) {
  var d = (to - from + 540).remainder(360) - 180;
  if (d == -180) d = 180;
  return d;
}

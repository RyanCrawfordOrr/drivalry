/// Planar geometry on a local equirectangular projection.
///
/// At the distances the matcher cares about (tens of metres) a flat projection
/// around the sample is accurate to millimetres, and far cheaper than
/// great-circle maths per polyline segment.
library;

import 'dart:math' as math;

/// Metres per degree of latitude (Earth radius 6 371 000 m × π / 180).
const double metresPerDegree = 111194.92664455873;

/// Local flat projection centred on a reference point.
class LocalProjection {
  LocalProjection(this.lat0, this.lon0)
    : _kx = metresPerDegree * math.cos(lat0 * math.pi / 180);

  final double lat0;
  final double lon0;
  final double _kx;

  /// East offset in metres.
  double x(double lon) => (lon - lon0) * _kx;

  /// North offset in metres.
  double y(double lat) => (lat - lat0) * metresPerDegree;
}

/// Result of projecting a point onto a polyline.
class PolylineHit {
  const PolylineHit({
    required this.distanceM,
    required this.segmentIndex,
    required this.t,
    required this.bearingDeg,
  });

  /// Distance from the point to the nearest point on the polyline, metres.
  final double distanceM;

  /// Index of the polyline segment (between point `i` and `i + 1`) hit.
  final int segmentIndex;

  /// Position along that segment, 0 at point `i`, 1 at point `i + 1`.
  final double t;

  /// Bearing of the segment in point order, degrees 0–360 (0 = north).
  final double bearingDeg;
}

/// Nearest point on the polyline `(lats, lons)` to `(lat, lon)`.
///
/// [proj] must be centred near the point. Returns null for a degenerate
/// polyline with fewer than two points.
PolylineHit? nearestPointOnPolyline(
  List<double> lats,
  List<double> lons,
  double lat,
  double lon,
  LocalProjection proj,
) {
  final n = lats.length;
  if (n < 2) return null;
  final px = proj.x(lon);
  final py = proj.y(lat);
  var bestD2 = double.infinity;
  var bestIdx = 0;
  var bestT = 0.0;
  var bestDx = 0.0;
  var bestDy = 0.0;
  var ax = proj.x(lons[0]);
  var ay = proj.y(lats[0]);
  for (var i = 0; i < n - 1; i++) {
    final bx = proj.x(lons[i + 1]);
    final by = proj.y(lats[i + 1]);
    final dx = bx - ax;
    final dy = by - ay;
    final len2 = dx * dx + dy * dy;
    var t = 0.0;
    if (len2 > 0) {
      t = ((px - ax) * dx + (py - ay) * dy) / len2;
      if (t < 0) {
        t = 0;
      } else if (t > 1) {
        t = 1;
      }
    }
    final cx = ax + t * dx;
    final cy = ay + t * dy;
    final ex = px - cx;
    final ey = py - cy;
    final d2 = ex * ex + ey * ey;
    if (d2 < bestD2) {
      bestD2 = d2;
      bestIdx = i;
      bestT = t;
      bestDx = dx;
      bestDy = dy;
    }
    ax = bx;
    ay = by;
  }
  return PolylineHit(
    distanceM: math.sqrt(bestD2),
    segmentIndex: bestIdx,
    t: bestT,
    bearingDeg: planarBearing(bestDx, bestDy),
  );
}

/// Bearing of the vector (east [dx], north [dy]) in degrees 0–360.
double planarBearing(double dx, double dy) {
  if (dx == 0 && dy == 0) return 0;
  final deg = math.atan2(dx, dy) * 180 / math.pi;
  return deg < 0 ? deg + 360 : deg;
}

/// Smallest absolute angle between two headings, degrees 0–180.
double angleDiff(double a, double b) {
  var d = (a - b).abs() % 360;
  if (d > 180) d = 360 - d;
  return d;
}

/// Normalises a heading to 0–360.
double normalizeHeading(double h) {
  final r = h % 360;
  return r < 0 ? r + 360 : r;
}

/// Flat-earth distance in metres between two coordinates, good to well under
/// a metre over the distances the matcher uses.
double flatDistanceM(double lat1, double lon1, double lat2, double lon2) {
  final kx = metresPerDegree * math.cos(((lat1 + lat2) / 2) * math.pi / 180);
  final dx = (lon2 - lon1) * kx;
  final dy = (lat2 - lat1) * metresPerDegree;
  return math.sqrt(dx * dx + dy * dy);
}

import 'database.dart';

/// Geometry of an installed pack's bounding box, shared by everyone who has
/// to decide which pack covers a point.
extension PackBounds on Pack {
  /// True when the point lies inside the pack's box (inclusive edges).
  bool contains(double lat, double lon) =>
      lat >= bboxMinLat &&
      lat <= bboxMaxLat &&
      lon >= bboxMinLon &&
      lon <= bboxMaxLon;

  /// Box area in square degrees; smaller boxes are more specific regions.
  double get bboxArea => (bboxMaxLat - bboxMinLat) * (bboxMaxLon - bboxMinLon);
}

/// The most specific (smallest-box) pack in [packs] that contains the point,
/// or null.
Pack? smallestPackContaining(Iterable<Pack> packs, double lat, double lon) {
  Pack? best;
  for (final p in packs) {
    if (!p.contains(lat, lon)) continue;
    if (best == null || p.bboxArea < best.bboxArea) best = p;
  }
  return best;
}

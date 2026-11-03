import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../data/repos/friends_repo.dart' show initialsOf;
import '../../../data/repos/presence_repo.dart';
import '../../../widgets/relative_time.dart';

/// A presence row as the map draws it.
class FriendMarker {
  const FriendMarker(this.row);

  final PresenceRow row;

  String get id => row.userId;
  LatLng get position => LatLng(row.lat, row.lon);
  String get title => row.name;
  String get initials => initialsOf(row.name);

  /// Older than a day: still shown, but greyed and never "driving".
  bool isStale(DateTime now) =>
      now.difference(row.updatedAt) > const Duration(hours: 24);

  bool isDriving(DateTime now) => row.driving && !isStale(now);

  String lastSeen(DateTime now) => relativeTime(row.updatedAt, now);

  String statusLine(DateTime now) =>
      isDriving(now) ? 'Driving now' : 'Parked · ${lastSeen(now)}';

  /// Stable per user, for the fallback coloured pins.
  double get hue => (row.userId.hashCode.abs() % 360).toDouble();

  /// Cache key for the rendered icon.
  String iconKey(DateTime now) => '$initials|${isDriving(now)}|${isStale(now)}';
}

/// Everyone except the viewer, newest update first.
List<FriendMarker> markersFrom(
  Iterable<PresenceRow> rows, {
  String? excludeUserId,
}) {
  final list = [
    for (final r in rows)
      if (r.userId != excludeUserId) FriendMarker(r),
  ];
  list.sort((a, b) => b.row.updatedAt.compareTo(a.row.updatedAt));
  return list;
}

/// Bounds around every marker, or null for none.
LatLngBounds? boundsOf(Iterable<FriendMarker> markers) {
  double? minLat, minLon, maxLat, maxLon;
  for (final m in markers) {
    minLat = minLat == null || m.row.lat < minLat ? m.row.lat : minLat;
    maxLat = maxLat == null || m.row.lat > maxLat ? m.row.lat : maxLat;
    minLon = minLon == null || m.row.lon < minLon ? m.row.lon : minLon;
    maxLon = maxLon == null || m.row.lon > maxLon ? m.row.lon : maxLon;
  }
  if (minLat == null) return null;
  // A single point or a tiny cluster still needs a visible box.
  const pad = 0.002;
  return LatLngBounds(
    southwest: LatLng(minLat - pad, minLon! - pad),
    northeast: LatLng(maxLat! + pad, maxLon! + pad),
  );
}

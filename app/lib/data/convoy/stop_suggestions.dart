import '../google/places_client.dart';
import '../google/routes_client.dart' show LatLon;

/// A place along the route with how far off the line it sits.
class StopSuggestion {
  const StopSuggestion({required this.place, required this.detourM});
  final PlaceSuggestion place;

  /// Straight-line distance from the planned route, metres.
  final double detourM;
}

/// Points at fractions of the remaining route length (0, 1/3, 2/3 by
/// default), where Places is asked for candidates.
List<LatLon> samplePoints(
  List<LatLon> remainingRoute, {
  List<double> fractions = const [0, 1 / 3, 2 / 3],
}) {
  if (remainingRoute.isEmpty) return const [];
  if (remainingRoute.length == 1) return [remainingRoute.first];
  final cumulative = <double>[0];
  for (var i = 1; i < remainingRoute.length; i++) {
    cumulative.add(
      cumulative.last + remainingRoute[i - 1].distanceTo(remainingRoute[i]),
    );
  }
  final total = cumulative.last;
  final out = <LatLon>[];
  for (final f in fractions) {
    final target = total * f.clamp(0, 1);
    var idx = 0;
    while (idx < cumulative.length - 1 && cumulative[idx + 1] < target) {
      idx++;
    }
    out.add(remainingRoute[idx]);
  }
  return out;
}

/// Shortest straight-line distance from [p] to the polyline, metres.
double distanceToRoute(LatLon p, List<LatLon> route) {
  if (route.isEmpty) return double.infinity;
  var best = double.infinity;
  for (var i = 0; i < route.length; i++) {
    final d = p.distanceTo(route[i]);
    if (d < best) best = d;
    if (i + 1 < route.length) {
      final m = LatLon(
        (route[i].lat + route[i + 1].lat) / 2,
        (route[i].lon + route[i + 1].lon) / 2,
      );
      final dm = p.distanceTo(m);
      if (dm < best) best = dm;
    }
  }
  return best;
}

/// Asks Places near a few points along the remaining route, dedupes by place
/// id and sorts by detour. Returns null when Places was unavailable for every
/// point (quota spent or offline), so the UI offers a pin instead.
Future<List<StopSuggestion>?> suggestStops({
  required PlacesClient places,
  required StopCategory category,
  required List<LatLon> remainingRoute,
  double radiusM = 5000,
}) async {
  final points = samplePoints(remainingRoute);
  if (points.isEmpty) return null;
  final seen = <String, StopSuggestion>{};
  var anyAnswer = false;
  for (final pt in points) {
    final found = await places.nearby(pt, category, radiusM: radiusM);
    if (found == null) continue;
    anyAnswer = true;
    for (final p in found) {
      if (seen.containsKey(p.placeId)) continue;
      seen[p.placeId] = StopSuggestion(
        place: p,
        detourM: distanceToRoute(p.location, remainingRoute),
      );
    }
  }
  if (!anyAnswer) return null;
  final list = seen.values.toList()
    ..sort((a, b) => a.detourM.compareTo(b.detourM));
  return list;
}

import '../google/routes_client.dart';

/// One car's ETA to the next waypoint (docs/10 §5 `eta`).
class EtaInfo {
  const EtaInfo({
    required this.userId,
    required this.seconds,
    required this.estimated,
    required this.at,
    this.distanceM,
    this.toStopId,
  });

  final String userId;
  final int seconds;

  /// True when the number is a straight-line guess (quota spent or offline).
  final bool estimated;

  /// When it was computed (epoch ms), so stale ETAs can be dimmed.
  final int at;
  final double? distanceM;
  final String? toStopId;

  Map<String, Object?> toPayload() => {
    'seconds': seconds,
    'estimated': estimated,
    'distanceM': ?distanceM,
    'toStopId': ?toStopId,
  };

  static EtaInfo? fromPayload(String userId, int t, Map<String, dynamic> p) {
    final s = p['seconds'];
    if (s is! num) return null;
    return EtaInfo(
      userId: userId,
      seconds: s.toInt(),
      estimated: p['estimated'] == true,
      at: t,
      distanceM: (p['distanceM'] as num?)?.toDouble(),
      toStopId: p['toStopId'] as String?,
    );
  }

  /// "12 min" / "1 h 05" style.
  String get label => formatEta(seconds);
}

String formatEta(int seconds) {
  final m = (seconds / 60).round();
  if (m < 1) return 'now';
  if (m < 60) return '$m min';
  final h = m ~/ 60;
  final r = (m % 60).toString().padLeft(2, '0');
  return '$h h $r';
}

/// What [EtaTracker.maybeUpdate] produces.
class EtaEstimate {
  const EtaEstimate({
    required this.seconds,
    required this.distanceM,
    required this.estimated,
    required this.polyline,
  });

  final int seconds;
  final double distanceM;
  final bool estimated;

  /// The last routed polyline (empty for straight-line guesses), for the map.
  final List<LatLon> polyline;
}

/// My ETA, recomputed at most every [minInterval] while moving. The Routes
/// API is asked at most every [routeRefresh] (or when the target changes);
/// in between, the last route's average speed is applied to the remaining
/// straight-line distance scaled by the route's detour ratio, so a 3-hour
/// drive costs a handful of Routes calls instead of 180.
class EtaTracker {
  EtaTracker({
    required this.routes,
    required this.now,
    this.minInterval = const Duration(seconds: 60),
    this.routeRefresh = const Duration(minutes: 5),
    this.movingSpeedMps = 2,
  });

  final RoutesClient routes;
  final int Function() now;
  final Duration minInterval;
  final Duration routeRefresh;
  final double movingSpeedMps;

  int? _lastAt;
  int? _lastRouteAt;
  LatLon? _lastTarget;
  RouteResult? _lastRoute;

  /// Straight-line distance at the time of the last routing, to scale later
  /// estimates (route length / straight length).
  double _lastStraightM = 0;
  EtaEstimate? last;
  int routeCalls = 0;

  /// Returns a fresh estimate when due, otherwise null (keep showing [last]).
  /// A changed target always recomputes.
  Future<EtaEstimate?> maybeUpdate({
    required LatLon me,
    required double? speedMps,
    required LatLon target,
  }) async {
    final t = now();
    final targetChanged =
        _lastTarget == null ||
        _lastTarget!.lat != target.lat ||
        _lastTarget!.lon != target.lon;
    final due = _lastAt == null || t - _lastAt! >= minInterval.inMilliseconds;
    final moving = (speedMps ?? 0) >= movingSpeedMps;
    if (!targetChanged && (!due || !moving)) return null;
    _lastAt = t;
    _lastTarget = target;
    final straight = me.distanceTo(target);
    final routeDue =
        targetChanged ||
        _lastRoute == null ||
        _lastRouteAt == null ||
        t - _lastRouteAt! >= routeRefresh.inMilliseconds;
    if (routeDue) {
      routeCalls++;
      _lastRouteAt = t;
      final r = await routes.route(me, target);
      _lastRoute = r;
      _lastStraightM = straight;
      return last = EtaEstimate(
        seconds: r.duration.inSeconds,
        distanceM: r.distanceM,
        estimated: r.estimated,
        polyline: r.polyline,
      );
    }
    final r = _lastRoute!;
    final ratio = _lastStraightM > 50 ? r.distanceM / _lastStraightM : 1.3;
    final remaining = straight * ratio.clamp(1.0, 3.0);
    final avgSpeed = r.duration.inSeconds > 0
        ? r.distanceM / r.duration.inSeconds
        : 20.0;
    final speed = avgSpeed < 5 ? 5.0 : avgSpeed;
    return last = EtaEstimate(
      seconds: (remaining / speed).round(),
      distanceM: remaining,
      estimated: r.estimated,
      polyline: r.polyline,
    );
  }

  void reset() {
    _lastAt = null;
    _lastRouteAt = null;
    _lastTarget = null;
    _lastRoute = null;
    _lastStraightM = 0;
    last = null;
  }
}

import '../../features/convoy/positions/peer_positions.dart';
import '../google/routes_client.dart' show LatLon;

/// One member who has fallen behind or gone quiet (docs/01 §4.6).
class LostSheep {
  const LostSheep({required this.userId, required this.reason});
  final String userId;

  /// `behind` (too far behind the leader) or `silent` (no position while the
  /// others move).
  final String reason;

  @override
  bool operator ==(Object other) =>
      other is LostSheep && other.userId == userId && other.reason == reason;

  @override
  int get hashCode => Object.hash(userId, reason);
}

/// Straight-line gap between two cars in minutes at the leader's speed (floor
/// 20 m/s so a stopped leader does not make everyone infinitely behind).
double gapMinutes(PeerPosition leader, PeerPosition member) {
  final d = LatLon(
    leader.lat,
    leader.lon,
  ).distanceTo(LatLon(member.lat, member.lon));
  final v = (leader.speed ?? 0) < 20 ? 20.0 : leader.speed!;
  return d / v / 60;
}

/// Decides who is lost, with hysteresis so a car hovering at the threshold
/// does not flap: a member becomes lost at [behindMinutes] and stops being
/// lost below `behindMinutes - 1`; silence starts at [silentFor] and ends on
/// the next position.
class LostSheepDetector {
  LostSheepDetector({
    this.behindMinutes = 5,
    this.silentFor = const Duration(minutes: 3),
    this.movingSpeedMps = 3,
  });

  final double behindMinutes;
  final Duration silentFor;
  final double movingSpeedMps;

  final Map<String, LostSheep> _current = {};

  Map<String, LostSheep> get current => Map.unmodifiable(_current);

  /// Evaluates the convoy. Returns members who became lost in this call (one
  /// event per episode); [current] holds everyone still lost.
  List<LostSheep> evaluate({
    required String leaderId,
    required Map<String, PeerPosition> positions,
    required Set<String> members,
    required int nowMs,
    String? me,
  }) {
    final started = <LostSheep>[];
    final leader = positions[leaderId];
    final othersMoving = positions.values.any(
      (p) =>
          nowMs - p.t < silentFor.inMilliseconds &&
          (p.speed ?? 0) >= movingSpeedMps,
    );
    for (final id in members) {
      if (id == leaderId) continue;
      final p = positions[id];
      final wasLost = _current[id];
      LostSheep? now;
      if (p == null || nowMs - p.t > silentFor.inMilliseconds) {
        if (othersMoving) now = LostSheep(userId: id, reason: 'silent');
      } else if (leader != null) {
        final gap = gapMinutes(leader, p);
        final threshold = wasLost?.reason == 'behind'
            ? behindMinutes - 1
            : behindMinutes;
        if (gap >= threshold) now = LostSheep(userId: id, reason: 'behind');
      }
      if (now == null) {
        _current.remove(id);
      } else {
        _current[id] = now;
        if (wasLost == null) started.add(now);
      }
    }
    _current.removeWhere((id, _) => !members.contains(id));
    return started;
  }

  void reset() => _current.clear();
}

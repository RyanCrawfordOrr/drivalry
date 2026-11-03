/// Nearest-road-with-heading matcher (`docs/03-architecture.md` §5).
///
/// Deliberately simple: per sample, score every way within reach by distance
/// and heading agreement, stick to the current way unless a rival is clearly
/// better for several consecutive samples, then emit road-segment runs.
library;

import 'dart:math' as math;

import 'package:drivalry_scoring/drivalry_scoring.dart'
    show GpsSample, RoadClass, RoadSegment, bearing;

import 'geometry.dart';
import 'pack_source.dart';
import 'pack_way.dart';
import 'tile_cache.dart';

/// A shared correction applied on top of the pack for one way.
class LimitOverride {
  const LimitOverride({
    required this.wayId,
    required this.limitMps,
    this.confidence = 0.85,
  });

  final int wayId;

  /// Corrected limit, m/s.
  final double limitMps;

  /// Confidence to report for segments on this way (0.85 for two agreeing
  /// flags, per `docs/03-architecture.md` §4.4).
  final double confidence;
}

/// One way considered for a sample, with its cost.
class RoadCandidate {
  const RoadCandidate({
    required this.way,
    required this.forward,
    required this.distanceM,
    required this.headingDeltaDeg,
    required this.cost,
  });

  final PackWay way;

  /// Direction of travel along the way implied by the heading comparison.
  final bool forward;
  final double distanceM;

  /// Heading disagreement used in the cost, degrees (0 when no heading).
  final double headingDeltaDeg;

  /// `distanceM / 10 + headingDeltaDeg / 30`.
  final double cost;
}

/// Scores every way near a point. Shared by [RoadMatcher] and the live
/// matcher. [heading] may be null (no usable heading): then the heading term
/// is 0 for every way and the direction defaults to the current direction for
/// the current way, or the way's allowed direction otherwise.
List<RoadCandidate> scoreCandidates(
  List<PackWay> ways,
  double lat,
  double lon, {
  required double radiusM,
  required double? heading,
  int? currentWayId,
  bool currentForward = true,
}) {
  final proj = LocalProjection(lat, lon);
  final dLat = radiusM / metresPerDegree;
  final dLon = dLat / math.max(0.01, math.cos(lat * math.pi / 180));
  final out = <RoadCandidate>[];
  for (final way in ways) {
    if (lat < way.minLat - dLat ||
        lat > way.maxLat + dLat ||
        lon < way.minLon - dLon ||
        lon > way.maxLon + dLon) {
      continue;
    }
    final hit = nearestPointOnPolyline(way.lats, way.lons, lat, lon, proj);
    if (hit == null || hit.distanceM > radiusM) continue;
    bool forward;
    double delta;
    if (heading == null) {
      delta = 0;
      forward = way.id == currentWayId ? currentForward : way.oneway != 2;
    } else {
      final along = angleDiff(heading, hit.bearingDeg);
      final against = angleDiff(heading, hit.bearingDeg + 180);
      switch (way.oneway) {
        case 1:
          forward = true;
          delta = along;
        case 2:
          forward = false;
          delta = against;
        default:
          forward = along <= against;
          delta = forward ? along : against;
      }
    }
    out.add(
      RoadCandidate(
        way: way,
        forward: forward,
        distanceM: hit.distanceM,
        headingDeltaDeg: delta,
        cost: hit.distanceM / 10 + delta / 30,
      ),
    );
  }
  out.sort((a, b) => a.cost.compareTo(b.cost));
  return out;
}

/// Output of [RoadMatcher.match].
class MatchResult {
  const MatchResult({
    required this.segments,
    required this.wayIdPerSample,
    required this.forwardPerSample,
    required this.limitCoverage,
    required this.matchedFraction,
  });

  /// Non-overlapping runs covering every sample index, in order. Unmatched
  /// runs have `speedLimit == null`, `confidence == 0` and
  /// `roadClass == RoadClass.unknown`.
  final List<RoadSegment> segments;

  /// Way id per sample, null when unmatched.
  final List<int?> wayIdPerSample;

  /// Direction of travel per sample (meaningless when unmatched).
  final List<bool> forwardPerSample;

  /// Moving seconds (speed ≥ 2 m/s) on segments with confidence ≥ 0.7 and a
  /// limit, divided by moving seconds. 0 when nothing moved.
  final double limitCoverage;

  /// Samples with a way ÷ samples. 0 for an empty trace.
  final double matchedFraction;
}

/// Matches a whole trace against a pack.
class RoadMatcher {
  const RoadMatcher({
    this.maxDistanceM = 35,
    this.switchMargin = 1.0,
    this.switchSamples = 3,
    this.maxAccuracyM = 50,
    this.minHeadingSpeedMps = 2,
  });

  /// Search radius; widened to the fix accuracy when that is larger.
  final double maxDistanceM;

  /// A rival must beat the current way's cost by this much...
  final double switchMargin;

  /// ...for this many consecutive samples before the matcher switches.
  final int switchSamples;

  /// Fixes less accurate than this inherit the previous way.
  final double maxAccuracyM;

  /// Below this speed the OS heading is ignored (a position-derived heading
  /// is still tried).
  final double minHeadingSpeedMps;

  /// Threshold under which a sample counts as not moving for coverage.
  static const double movingSpeedMps = 2;

  /// Segments with at least this confidence count as "limit known".
  static const double knownLimitConfidence = 0.7;

  /// Matches [samples] against [pack] using a fresh [TileCache].
  MatchResult match(
    List<GpsSample> samples,
    PackSource pack, {
    Map<int, LimitOverride> overrides = const {},
  }) => matchWithCache(samples, TileCache(pack), overrides: overrides);

  /// Matches using a caller-owned cache (for several trips against one pack).
  MatchResult matchWithCache(
    List<GpsSample> samples,
    TileCache cache, {
    Map<int, LimitOverride> overrides = const {},
  }) {
    final n = samples.length;
    final assigned = List<PackWay?>.filled(n, null);
    final forwardOf = List<bool>.filled(n, true);

    PackWay? current;
    var currentForward = true;
    PackWay? pending;
    var pendingCount = 0;
    var pendingStart = -1;
    final pendingDirs = <int, bool>{};

    void clearPending() {
      pending = null;
      pendingCount = 0;
      pendingStart = -1;
      pendingDirs.clear();
    }

    for (var i = 0; i < n; i++) {
      final s = samples[i];
      final heading = _usableHeading(samples, i);
      if (s.accuracy > maxAccuracyM ||
          (heading == null && s.speed < movingSpeedMps)) {
        assigned[i] = current;
        forwardOf[i] = currentForward;
        continue;
      }
      final candidates = scoreCandidates(
        cache.waysNear(s.lat, s.lon),
        s.lat,
        s.lon,
        radiusM: math.max(maxDistanceM, s.accuracy),
        heading: heading,
        currentWayId: current?.id,
        currentForward: currentForward,
      );
      if (candidates.isEmpty) {
        current = null;
        clearPending();
        assigned[i] = null;
        continue;
      }
      RoadCandidate? cur;
      if (current != null) {
        for (final c in candidates) {
          if (c.way.id == current.id) {
            cur = c;
            break;
          }
        }
      }
      if (cur == null) {
        final best = candidates.first;
        current = best.way;
        currentForward = best.forward;
        clearPending();
        assigned[i] = current;
        forwardOf[i] = currentForward;
        continue;
      }
      currentForward = cur.forward;
      assigned[i] = current;
      forwardOf[i] = currentForward;

      final best = candidates.first.way.id == current!.id
          ? (candidates.length > 1 ? candidates[1] : null)
          : candidates.first;
      if (best != null && best.cost < cur.cost - switchMargin) {
        if (pending?.id == best.way.id) {
          pendingCount++;
        } else {
          pending = best.way;
          pendingCount = 1;
          pendingStart = i;
          pendingDirs.clear();
        }
        pendingDirs[i] = best.forward;
        if (pendingCount >= switchSamples) {
          current = pending;
          var dir = best.forward;
          for (var k = pendingStart; k <= i; k++) {
            dir = pendingDirs[k] ?? dir;
            assigned[k] = current;
            forwardOf[k] = dir;
          }
          currentForward = dir;
          clearPending();
        }
      } else {
        clearPending();
      }
    }

    return _buildResult(samples, assigned, forwardOf, overrides);
  }

  double? _usableHeading(List<GpsSample> samples, int i) {
    final s = samples[i];
    final h = s.heading;
    if (h != null && s.speed >= minHeadingSpeedMps) {
      return normalizeHeading(h);
    }
    final a = i > 0 ? samples[i - 1] : s;
    final b = i + 1 < samples.length ? samples[i + 1] : s;
    if (identical(a, b)) return null;
    if (flatDistanceM(a.lat, a.lon, b.lat, b.lon) <= 3) return null;
    return bearing(a.lat, a.lon, b.lat, b.lon);
  }

  MatchResult _buildResult(
    List<GpsSample> samples,
    List<PackWay?> assigned,
    List<bool> forwardOf,
    Map<int, LimitOverride> overrides,
  ) {
    final n = samples.length;
    if (n == 0) {
      return const MatchResult(
        segments: [],
        wayIdPerSample: [],
        forwardPerSample: [],
        limitCoverage: 0,
        matchedFraction: 0,
      );
    }
    final segments = <RoadSegment>[];
    final confOf = List<double>.filled(n, 0);
    final limitOf = List<double?>.filled(n, null);

    bool same(int i, int j) {
      final a = assigned[i], b = assigned[j];
      if (a == null || b == null) return a == null && b == null;
      return a.id == b.id && forwardOf[i] == forwardOf[j];
    }

    void emit(int from, int to) {
      final way = assigned[from];
      RoadSegment seg;
      if (way == null) {
        seg = RoadSegment(
          fromIdx: from,
          toIdx: to,
          speedLimit: null,
          confidence: 0,
          roadClass: RoadClass.unknown,
        );
      } else {
        final ov = overrides[way.id];
        final limit = ov?.limitMps ?? way.limitMps(forward: forwardOf[from]);
        final conf = ov?.confidence ?? way.confidence;
        seg = RoadSegment(
          fromIdx: from,
          toIdx: to,
          speedLimit: limit,
          confidence: conf,
          roadClass: way.roadClass,
          name: way.name,
          wayId: '${way.id}',
        );
      }
      segments.add(seg);
      for (var k = from; k <= to; k++) {
        confOf[k] = seg.confidence;
        limitOf[k] = seg.speedLimit;
      }
    }

    var start = 0;
    for (var i = 1; i < n; i++) {
      if (!same(i, i - 1)) {
        emit(start, i - 1);
        start = i;
      }
    }
    emit(start, n - 1);

    var movingS = 0.0;
    var knownS = 0.0;
    var matched = 0;
    for (var i = 0; i < n; i++) {
      if (assigned[i] != null) matched++;
      final s = samples[i];
      if (s.speed < movingSpeedMps) continue;
      var dt = 1.0;
      if (i > 0) {
        dt = (s.t - samples[i - 1].t) / 1000;
        if (dt < 0) dt = 0;
        if (dt > 5) dt = 5;
      }
      movingS += dt;
      if (confOf[i] >= knownLimitConfidence && limitOf[i] != null) {
        knownS += dt;
      }
    }

    return MatchResult(
      segments: segments,
      wayIdPerSample: [for (final w in assigned) w?.id],
      forwardPerSample: forwardOf,
      limitCoverage: movingS > 0 ? knownS / movingS : 0,
      matchedFraction: matched / n,
    );
  }
}

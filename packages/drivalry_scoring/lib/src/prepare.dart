/// Per-sample derived values shared by every detector. Mirrors `packages/scoring/src/prepare.ts`.
library;

import 'dart:math' as math;

import 'constants.dart';
import 'geo.dart';
import 'js_compat.dart';
import 'types.dart';

/// Per-sample derived values used by every detector. Computed once.
class PreparedTrip {
  const PreparedTrip({
    required this.input,
    required this.samples,
    required this.dt,
    required this.speed,
    required this.accel,
    required this.heading,
    required this.lateral,
    required this.stepDistance,
    required this.segmentAt,
    required this.goodFix,
    required this.firstMoving,
    required this.lastMoving,
  });

  final TripInput input;

  /// Samples sorted by time.
  final List<GpsSample> samples;

  /// Seconds between sample i-1 and i (0 for i = 0).
  final List<double> dt;

  /// Median-filtered speed, m/s. Removes single-sample GPS spikes.
  final List<double> speed;

  /// Longitudinal acceleration between i-1 and i, m/s² (positive = speeding up).
  final List<double> accel;

  /// Heading in degrees, from the sample or derived from positions. NaN when unknown.
  final List<double> heading;

  /// Lateral acceleration estimate, m/s² (speed × heading rate). 0 when unknown.
  final List<double> lateral;

  /// Distance travelled between i-1 and i, m.
  final List<double> stepDistance;

  /// Segment covering sample i, or null.
  final List<RoadSegment?> segmentAt;

  /// True when accuracy is good enough for speeding judgments.
  final List<bool> goodFix;

  /// Index bounds of the "moving" part of the trip (trims stationary start/end).
  final int firstMoving;
  final int lastMoving;
}

double _median3(double a, double b, double c) =>
    math.max(math.min(a, b), math.min(math.max(a, b), c));

PreparedTrip prepare(TripInput input) {
  final samples = stableSorted(input.samples, (a, b) => a.t.compareTo(b.t));
  final n = samples.length;

  final dt = List<double>.filled(n, 0);
  final rawSpeed = [for (final s in samples) math.max(0.0, s.speed)];
  final speed = List<double>.filled(n, 0);
  final accel = List<double>.filled(n, 0);
  final heading = List<double>.filled(n, double.nan);
  final lateral = List<double>.filled(n, 0);
  final stepDistance = List<double>.filled(n, 0);
  final goodFix = [for (final s in samples) s.accuracy <= gpsMaxAccuracy];

  for (var i = 0; i < n; i++) {
    final prev = i > 0 ? rawSpeed[i - 1] : rawSpeed[i];
    final cur = rawSpeed[i];
    final next = i + 1 < n ? rawSpeed[i + 1] : cur;
    speed[i] = n >= 3 ? _median3(prev, cur, next) : cur;
  }

  for (var i = 1; i < n; i++) {
    final a = samples[i - 1];
    final b = samples[i];
    final d = math.max(0.001, (b.t - a.t) / 1000);
    dt[i] = d;
    stepDistance[i] = haversine(a.lat, a.lon, b.lat, b.lon);
    accel[i] = (speed[i] - speed[i - 1]) / d;
  }

  for (var i = 0; i < n; i++) {
    final s = samples[i];
    final h = s.heading;
    if (h != null && h.isFinite) {
      heading[i] = h;
    } else if (i > 0 && stepDistance[i] > 2) {
      final p = samples[i - 1];
      heading[i] = bearing(p.lat, p.lon, s.lat, s.lon);
    } else if (i > 0) {
      heading[i] = heading[i - 1];
    }
  }

  for (var i = 1; i < n; i++) {
    final h0 = heading[i - 1];
    final h1 = heading[i];
    if (h0.isNaN || h1.isNaN) continue;
    final rate = (headingDelta(h0, h1) * math.pi) / 180 / dt[i]; // rad/s
    lateral[i] = rate.abs() * speed[i];
  }

  final segmentAt = List<RoadSegment?>.filled(n, null);
  for (final seg in input.segments) {
    final from = math.max(0, seg.fromIdx);
    final to = math.min(n - 1, seg.toIdx);
    for (var i = from; i <= to; i++) {
      segmentAt[i] = seg;
    }
  }

  var firstMoving = 0;
  while (firstMoving < n && speed[firstMoving] <= movingSpeed) {
    firstMoving++;
  }
  var lastMoving = n - 1;
  while (lastMoving > firstMoving && speed[lastMoving] <= movingSpeed) {
    lastMoving--;
  }
  if (firstMoving >= n) {
    firstMoving = 0;
    lastMoving = math.max(0, n - 1);
  }

  return PreparedTrip(
    input: input,
    samples: samples,
    dt: dt,
    speed: speed,
    accel: accel,
    heading: heading,
    lateral: lateral,
    stepDistance: stepDistance,
    segmentAt: segmentAt,
    goodFix: goodFix,
    firstMoving: firstMoving,
    lastMoving: lastMoving,
  );
}

/// Index of the sample closest in time to `t` (binary search). Returns 0 for an empty list.
int sampleIndexAt(List<GpsSample> samples, int t) {
  var lo = 0;
  var hi = samples.length - 1;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (samples[mid].t < t) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  if (lo > 0 && (samples[lo - 1].t - t).abs() < (samples[lo].t - t).abs()) {
    return lo - 1;
  }
  return lo;
}

/// Group consecutive indices where `predicate(i)` holds into runs, merging runs separated
/// by a time gap smaller than `mergeGapS`. Returns `(startIdx, endIdx)` inclusive pairs.
///
/// Indices at or beyond `samples.length` never hit. (In TypeScript the predicates read
/// `undefined` there and return false; Dart lists would throw, so the guard lives here.)
List<(int, int)> runs(
  int from,
  int to,
  List<GpsSample> samples,
  bool Function(int i) predicate,
  double mergeGapS,
) {
  final out = <(int, int)>[];
  var start = -1;
  for (var i = from; i <= to; i++) {
    final hit = i < samples.length && predicate(i);
    if (hit && start == -1) start = i;
    if (!hit && start != -1) {
      out.add((start, i - 1));
      start = -1;
    }
  }
  if (start != -1) out.add((start, to));

  final merged = <(int, int)>[];
  for (final r in out) {
    if (merged.isNotEmpty &&
        (samples[r.$1].t - samples[merged.last.$2].t) / 1000 < mergeGapS) {
      merged[merged.length - 1] = (merged.last.$1, r.$2);
    } else {
      merged.add(r);
    }
  }
  return merged;
}

/// Seconds spanned by samples `[startIdx, endIdx]`; a one-sample run still represents
/// roughly one sampling interval.
double durationS(List<GpsSample> samples, int startIdx, int endIdx) {
  final d = (samples[endIdx].t - samples[startIdx].t) / 1000;
  return math.max(d, 1.0);
}

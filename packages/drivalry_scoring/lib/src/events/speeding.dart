/// Speeding detection. Mirrors `packages/scoring/src/events/speeding.ts`.
library;

import 'dart:math' as math;

import '../constants.dart';
import '../js_compat.dart';
import '../prepare.dart';
import '../types.dart';

class SpeedingResult {
  const SpeedingResult({
    required this.events,
    required this.observations,
    required this.secondsOverLimit,
    required this.secondsWithKnownLimit,
    required this.timeSavedBySpeedingS,
  });

  /// Episodes on confident segments. These score.
  final List<TripEvent> events;

  /// Episodes on low-confidence segments. Shown, never scored.
  final List<TripEvent> observations;

  /// Sum of confident episode durations.
  final double secondsOverLimit;
  final double secondsWithKnownLimit;
  final double timeSavedBySpeedingS;
}

Severity _severityForOver(double maxOver, double maxSpeed) {
  if (maxOver >= Speeding.thresholds.reckless ||
      maxSpeed >= Speeding.recklessAbsolute) {
    return Severity.reckless;
  }
  if (maxOver >= Speeding.thresholds.major) return Severity.major;
  if (maxOver >= Speeding.thresholds.moderate) return Severity.moderate;
  return Severity.minor;
}

TripEvent _buildEpisode(PreparedTrip p, int start, int end, bool confident) {
  final seg = p.segmentAt[start]!;
  final limit = seg.speedLimit!;
  var maxSpeed = 0.0;
  var maxOver = 0.0;
  var overSum = 0.0;
  var count = 0;
  var timeSaved = 0.0;
  for (var i = start; i <= end; i++) {
    final v = p.speed[i];
    final over = v - limit;
    if (v > maxSpeed) maxSpeed = v;
    if (over > maxOver) maxOver = over;
    if (over > 0) {
      overSum += over;
      count++;
      final d = p.stepDistance[i];
      // time at limit minus time actually taken
      timeSaved += d / limit - d / math.max(v, 0.1);
    }
  }
  final s = p.samples[start];
  return TripEvent(
    kind: EventKind.speeding,
    severity: confident ? _severityForOver(maxOver, maxSpeed) : Severity.minor,
    startT: s.t,
    endT: p.samples[end].t,
    durationS: durationS(p.samples, start, end),
    startIdx: start,
    endIdx: end,
    lat: s.lat,
    lon: s.lon,
    detail: SpeedingDetail(
      limit: limit,
      maxSpeed: maxSpeed,
      avgOver: count != 0 ? overSum / count : 0,
      maxOver: maxOver,
      roadName: seg.name,
      roadClass: seg.roadClass,
      timeSavedS: math.max(0.0, timeSaved),
    ),
  );
}

/// Samples exempt from speeding judgment because the posted limit just dropped and the car is
/// still slowing down (a 65 → 25 exit ramp takes ~12 s at a comfortable 1.5 m/s²).
///
/// The exemption lasts at most [Speeding.limitDropGraceS] after the drop, requires the car to
/// be decelerating after the first few seconds, and ends as soon as the driver accelerates or
/// gets under limit + minOver.
List<bool> _limitDropExemptions(PreparedTrip p) {
  final samples = p.samples;
  final speed = p.speed;
  final segmentAt = p.segmentAt;
  final n = samples.length;
  final exempt = List<bool>.filled(n, false);
  var dropAt = double.negativeInfinity;
  var active = false;

  for (var i = 1; i < n; i++) {
    final prev = segmentAt[i - 1];
    final seg = segmentAt[i];
    final prevLimit = prev?.speedLimit;
    final segLimit = seg?.speedLimit;
    if (seg != null &&
        prev != null &&
        !identical(seg, prev) &&
        segLimit != null &&
        prevLimit != null &&
        segLimit < prevLimit - 0.5) {
      dropAt = samples[i].t.toDouble();
      active = true;
    }
    if (!active || seg == null || segLimit == null) continue;

    final elapsed = (samples[i].t - dropAt) / 1000;
    final decelerating = speed[i] <= speed[i - 1] - Speeding.graceMinDecel;
    final underThreshold = speed[i] < segLimit + Speeding.minOver;

    if (underThreshold ||
        elapsed > Speeding.limitDropGraceS ||
        (elapsed > Speeding.graceFreeS && !decelerating)) {
      active = false;
      continue;
    }
    exempt[i] = true;
  }
  return exempt;
}

/// Detects speeding episodes. An episode is a run of samples over the limit by at least
/// [Speeding.minOver] on a single segment-confidence class, merged across short gaps,
/// lasting at least [Speeding.minDurationS].
///
/// Also detects the absolute-reckless case (≥ 100 mph) on any road, limit known or not.
SpeedingResult detectSpeeding(PreparedTrip p) {
  final samples = p.samples;
  final speed = p.speed;
  final segmentAt = p.segmentAt;
  final goodFix = p.goodFix;
  final firstMoving = p.firstMoving;
  final lastMoving = p.lastMoving;
  final exempt = _limitDropExemptions(p);

  bool overBy(int i, bool confident) {
    final seg = segmentAt[i];
    final limit = seg?.speedLimit;
    if (seg == null || limit == null || !goodFix[i] || exempt[i]) return false;
    final confOk = confident
        ? seg.confidence >= speedingMinConfidence
        : seg.confidence < speedingMinConfidence;
    return confOk && speed[i] - limit >= Speeding.minOver;
  }

  final events = <TripEvent>[];
  final observations = <TripEvent>[];

  for (final (a, b) in runs(
    firstMoving,
    lastMoving,
    samples,
    (i) => overBy(i, true),
    Speeding.mergeGapS,
  )) {
    if (durationS(samples, a, b) >= Speeding.minDurationS) {
      events.add(_buildEpisode(p, a, b, true));
    }
  }
  for (final (a, b) in runs(
    firstMoving,
    lastMoving,
    samples,
    (i) => overBy(i, false),
    Speeding.mergeGapS,
  )) {
    if (durationS(samples, a, b) >= Speeding.minDurationS) {
      observations.add(_buildEpisode(p, a, b, false));
    }
  }

  // Absolute reckless speed, independent of limit knowledge.
  bool absolute(int i) => goodFix[i] && speed[i] >= Speeding.recklessAbsolute;
  for (final (a, b) in runs(
    firstMoving,
    lastMoving,
    samples,
    absolute,
    Speeding.mergeGapS,
  )) {
    if (durationS(samples, a, b) < Speeding.recklessAbsoluteMinDurationS) {
      continue;
    }
    final overlapping = events.indexWhere(
      (e) => e.startIdx <= b && e.endIdx >= a,
    );
    if (overlapping != -1) {
      events[overlapping] = events[overlapping].withSeverity(Severity.reckless);
      continue;
    }
    final s = samples[a];
    final seg = segmentAt[a];
    var maxSpeed = 0.0;
    for (var i = a; i <= b; i++) {
      maxSpeed = math.max(maxSpeed, speed[i]);
    }
    final limit = seg?.speedLimit ?? double.nan;
    events.add(
      TripEvent(
        kind: EventKind.speeding,
        severity: Severity.reckless,
        startT: s.t,
        endT: samples[b].t,
        durationS: durationS(samples, a, b),
        startIdx: a,
        endIdx: b,
        lat: s.lat,
        lon: s.lon,
        detail: SpeedingDetail(
          limit: limit,
          maxSpeed: maxSpeed,
          avgOver: limit.isNaN ? double.nan : maxSpeed - limit,
          maxOver: limit.isNaN ? double.nan : maxSpeed - limit,
          roadName: seg?.name,
          roadClass: seg?.roadClass ?? RoadClass.unknown,
          timeSavedS: 0,
        ),
      ),
    );
  }

  final sortedEvents = stableSorted(
    events,
    (x, y) => x.startIdx.compareTo(y.startIdx),
  );

  var secondsWithKnownLimit = 0.0;
  for (var i = firstMoving + 1; i <= lastMoving; i++) {
    final seg = segmentAt[i];
    if (seg == null ||
        seg.speedLimit == null ||
        seg.confidence < speedingMinConfidence) {
      continue;
    }
    secondsWithKnownLimit += p.dt[i];
  }

  // Summed in sorted order, as the TS reduce() does, so floating-point totals match.
  var secondsOverLimit = 0.0;
  var timeSavedBySpeedingS = 0.0;
  for (final e in sortedEvents) {
    secondsOverLimit += e.durationS;
    final d = e.detail;
    timeSavedBySpeedingS += d is SpeedingDetail ? d.timeSavedS : 0;
  }

  return SpeedingResult(
    events: sortedEvents,
    observations: observations,
    secondsOverLimit: secondsOverLimit,
    secondsWithKnownLimit: secondsWithKnownLimit,
    timeSavedBySpeedingS: timeSavedBySpeedingS,
  );
}

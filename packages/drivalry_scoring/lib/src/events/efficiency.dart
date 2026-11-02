/// Idling and high-speed-cruise detection. Mirrors `packages/scoring/src/events/efficiency.ts`.
library;

import 'dart:math' as math;

import '../constants.dart';
import '../prepare.dart';
import '../types.dart';

/// Mid-trip stops longer than the free threshold. Trip start/end are already trimmed.
List<TripEvent> detectIdling(PreparedTrip p) {
  final samples = p.samples;
  final speed = p.speed;
  final out = <TripEvent>[];
  bool stopped(int i) => speed[i] < 0.5 || speed[i] <= movingSpeed * 0.5;
  for (final (a, b) in runs(p.firstMoving, p.lastMoving, samples, stopped, 5)) {
    final dur = durationS(samples, a, b);
    if (dur <= Efficiency.idle.freeS) continue;
    final s = samples[a];
    out.add(
      TripEvent(
        kind: EventKind.idling,
        severity: Severity.minor,
        startT: s.t,
        endT: samples[b].t,
        durationS: dur,
        startIdx: a,
        endIdx: b,
        lat: s.lat,
        lon: s.lon,
        detail: IdleDetail(excessS: dur - Efficiency.idle.freeS),
      ),
    );
  }
  return out;
}

/// Sustained driving at or above the fuel-cliff speed, regardless of the limit.
List<TripEvent> detectHighSpeedCruise(PreparedTrip p) {
  final samples = p.samples;
  final speed = p.speed;
  final goodFix = p.goodFix;
  final out = <TripEvent>[];
  bool cruising(int i) => goodFix[i] && speed[i] >= Efficiency.cruise.speed;
  for (final (a, b) in runs(
    p.firstMoving,
    p.lastMoving,
    samples,
    cruising,
    10,
  )) {
    final dur = durationS(samples, a, b);
    if (dur < Efficiency.cruise.minEventS) continue;
    var maxSpeed = 0.0;
    for (var i = a; i <= b; i++) {
      maxSpeed = math.max(maxSpeed, speed[i]);
    }
    final s = samples[a];
    out.add(
      TripEvent(
        kind: EventKind.highSpeedCruise,
        severity: Severity.minor,
        startT: s.t,
        endT: samples[b].t,
        durationS: dur,
        startIdx: a,
        endIdx: b,
        lat: s.lat,
        lon: s.lon,
        detail: CruiseDetail(maxSpeed: maxSpeed),
      ),
    );
  }
  return out;
}

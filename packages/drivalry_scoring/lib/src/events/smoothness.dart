/// Harsh brake / accel / corner detection. Mirrors `packages/scoring/src/events/smoothness.ts`.
library;

import 'dart:math' as math;

import '../constants.dart';
import '../js_compat.dart';
import '../prepare.dart';
import '../types.dart';

({double moderate, double severe}) _thresholdsFor(EventKind kind) =>
    switch (kind) {
      EventKind.harshBrake => Smoothness.brake,
      EventKind.harshAccel => Smoothness.accel,
      EventKind.hardCorner => Smoothness.corner,
      _ => throw ArgumentError.value(kind, 'kind', 'not a motion kind'),
    };

Severity? _severityFor(EventKind kind, double peak) {
  final t = _thresholdsFor(kind);
  if (peak >= t.severe) return Severity.severe;
  if (peak >= t.moderate) return Severity.moderate;
  return null;
}

TripEvent _makeEvent(
  PreparedTrip p,
  EventKind kind,
  int a,
  int b,
  double peak,
) {
  final s = p.samples[a];
  return TripEvent(
    kind: kind,
    severity: _severityFor(kind, peak) ?? Severity.moderate,
    startT: s.t,
    endT: p.samples[b].t,
    durationS: durationS(p.samples, a, b),
    startIdx: a,
    endIdx: b,
    lat: s.lat,
    lon: s.lon,
    detail: MotionDetail(
      kind: kind,
      peak: peak,
      speedAtStart: p.speed[math.max(0, a - 1)],
    ),
  );
}

/// Derives harsh brake / accel / corner events from GPS when no accelerometer events are supplied.
/// At 1 Hz, "sustained ≥ 0.7 s" means at least one full interval over threshold.
List<TripEvent> _fromGps(PreparedTrip p) {
  final out = <TripEvent>[];

  void detect(EventKind kind, double Function(int i) value) {
    final threshold = _thresholdsFor(kind).moderate;
    bool pred(int i) =>
        p.goodFix[i] &&
        p.goodFix[i - 1] &&
        p.dt[i] >= Smoothness.minSustainedS &&
        value(i) >= threshold;
    for (final (a, b) in runs(
      p.firstMoving + 1,
      p.lastMoving,
      p.samples,
      pred,
      Smoothness.mergeGapS,
    )) {
      var peak = 0.0;
      for (var i = a; i <= b; i++) {
        peak = math.max(peak, value(i));
      }
      out.add(_makeEvent(p, kind, a, b, peak));
    }
  }

  detect(EventKind.harshBrake, (i) => -p.accel[i]);
  detect(EventKind.harshAccel, (i) => p.accel[i]);
  detect(
    EventKind.hardCorner,
    (i) => p.speed[i] >= Smoothness.cornerMinSpeed ? p.lateral[i] : 0.0,
  );

  return out;
}

EventKind _eventKindFor(MotionEventKind kind) => switch (kind) {
  MotionEventKind.brake => EventKind.harshBrake,
  MotionEventKind.accel => EventKind.harshAccel,
  MotionEventKind.corner => EventKind.hardCorner,
};

/// Uses pre-detected accelerometer events, merging bursts within mergeGapS.
List<TripEvent> _fromMotionEvents(PreparedTrip p, List<MotionEvent> motion) {
  final out = <TripEvent>[];
  final sorted = stableSorted(motion, (a, b) => a.t.compareTo(b.t));
  for (final kind in MotionEventKind.values) {
    final mk = _eventKindFor(kind);
    ({int start, int end, double peak})? cur;
    void flush() {
      final c = cur;
      if (c == null) return;
      if (_severityFor(mk, c.peak) != null) {
        final a = sampleIndexAt(p.samples, c.start);
        final b = sampleIndexAt(p.samples, c.end);
        out.add(_makeEvent(p, mk, a, math.max(a, b), c.peak));
      }
      cur = null;
    }

    for (final m in sorted) {
      if (m.kind != kind) continue;
      final c = cur;
      if (c != null && (m.t - c.end) / 1000 < Smoothness.mergeGapS) {
        cur = (start: c.start, end: m.t, peak: math.max(c.peak, m.peak));
      } else {
        flush();
        cur = (start: m.t, end: m.t, peak: m.peak);
      }
    }
    flush();
  }
  return stableSorted(out, (x, y) => x.startIdx.compareTo(y.startIdx));
}

List<TripEvent> detectSmoothness(PreparedTrip p) {
  final motion = p.input.motionEvents;
  if (motion != null && motion.isNotEmpty) return _fromMotionEvents(p, motion);
  return _fromGps(p);
}

bool isMotionKind(EventKind kind) =>
    kind == EventKind.harshBrake ||
    kind == EventKind.harshAccel ||
    kind == EventKind.hardCorner;

/// Phone-handling detection. Mirrors `packages/scoring/src/events/attention.ts`.
library;

import 'dart:math' as math;

import '../constants.dart';
import '../js_compat.dart';
import '../prepare.dart';
import '../types.dart';

class _Episode {
  _Episode({
    required this.startT,
    required this.endT,
    required this.events,
    required this.maxSpeed,
  });

  final int startT;
  int endT;
  final List<PhoneEvent> events;
  double maxSpeed;
}

Severity _severityFor(double durationS, double maxSpeed) {
  if (maxSpeed >= Attention.majorSpeed) return Severity.major;
  if (durationS > Attention.thresholds.majorS) return Severity.major;
  if (durationS >= Attention.thresholds.moderateS) return Severity.moderate;
  return Severity.minor;
}

/// Phone-handling episodes: OS unlock/interaction/handheld-call events while moving faster than
/// [Attention.minSpeed], merged when within [Attention.mergeGapS] of each other.
List<TripEvent> detectPhoneHandling(PreparedTrip p) {
  final raw = p.input.phoneEvents ?? const <PhoneEvent>[];
  if (raw.isEmpty || p.samples.isEmpty) return [];

  final sorted = stableSorted(raw, (a, b) => a.t.compareTo(b.t));
  final episodes = <_Episode>[];

  for (final ev in sorted) {
    final idx = sampleIndexAt(p.samples, ev.t);
    final nearest = p.samples[idx];
    // Ignore events that fall outside the recorded trip by more than a sample gap.
    if ((nearest.t - ev.t).abs() > 5000) continue;
    final v = p.speed[idx];
    if (v <= Attention.minSpeed) continue;

    final cur = episodes.isEmpty ? null : episodes.last;
    if (cur != null && (ev.t - cur.endT) / 1000 < Attention.mergeGapS) {
      cur.endT = ev.t;
      cur.events.add(ev);
      cur.maxSpeed = math.max(cur.maxSpeed, v);
    } else {
      episodes.add(
        _Episode(startT: ev.t, endT: ev.t, events: [ev], maxSpeed: v),
      );
    }
  }

  return [
    for (final e in episodes)
      () {
        final a = sampleIndexAt(p.samples, e.startT);
        final b = math.max(a, sampleIndexAt(p.samples, e.endT));
        final dur = math.max(Attention.minEpisodeS, (e.endT - e.startT) / 1000);
        final s = p.samples[a];
        // Set iteration order is insertion order, like `[...new Set(...)]`.
        final kinds = e.events.map((x) => x.kind).toSet().toList();
        return TripEvent(
          kind: EventKind.phoneHandling,
          severity: _severityFor(dur, e.maxSpeed),
          startT: e.startT,
          endT: e.endT,
          durationS: dur,
          startIdx: a,
          endIdx: b,
          lat: s.lat,
          lon: s.lon,
          detail: PhoneDetail(
            interactions: e.events.length,
            maxSpeed: e.maxSpeed,
            kinds: kinds,
          ),
        );
      }(),
  ];
}

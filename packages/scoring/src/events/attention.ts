import { ATTENTION } from '../constants';
import { sampleIndexAt, type PreparedTrip } from '../prepare';
import type { PhoneEvent, PhoneEventKind, Severity, TripEvent } from '../types';

interface Episode {
  startT: number;
  endT: number;
  events: PhoneEvent[];
  maxSpeed: number;
}

function severityFor(durationS: number, maxSpeed: number): Severity {
  if (maxSpeed >= ATTENTION.majorSpeed) return 'major';
  if (durationS > ATTENTION.thresholds.majorS) return 'major';
  if (durationS >= ATTENTION.thresholds.moderateS) return 'moderate';
  return 'minor';
}

/**
 * Phone-handling episodes: OS unlock/interaction/handheld-call events while moving faster than
 * ATTENTION.minSpeed, merged when within ATTENTION.mergeGapS of each other.
 */
export function detectPhoneHandling(p: PreparedTrip): TripEvent[] {
  const raw = p.input.phoneEvents ?? [];
  if (raw.length === 0 || p.samples.length === 0) return [];

  const sorted = [...raw].sort((a, b) => a.t - b.t);
  const episodes: Episode[] = [];

  for (const ev of sorted) {
    const idx = sampleIndexAt(p.samples, ev.t);
    const nearest = p.samples[idx]!;
    // Ignore events that fall outside the recorded trip by more than a sample gap.
    if (Math.abs(nearest.t - ev.t) > 5_000) continue;
    const v = p.speed[idx]!;
    if (v <= ATTENTION.minSpeed) continue;

    const cur = episodes[episodes.length - 1];
    if (cur && (ev.t - cur.endT) / 1000 < ATTENTION.mergeGapS) {
      cur.endT = ev.t;
      cur.events.push(ev);
      cur.maxSpeed = Math.max(cur.maxSpeed, v);
    } else {
      episodes.push({ startT: ev.t, endT: ev.t, events: [ev], maxSpeed: v });
    }
  }

  return episodes.map((e) => {
    const a = sampleIndexAt(p.samples, e.startT);
    const b = Math.max(a, sampleIndexAt(p.samples, e.endT));
    const dur = Math.max(ATTENTION.minEpisodeS, (e.endT - e.startT) / 1000);
    const s = p.samples[a]!;
    const kinds = [...new Set(e.events.map((x) => x.kind))] as PhoneEventKind[];
    return {
      kind: 'phone_handling',
      severity: severityFor(dur, e.maxSpeed),
      startT: e.startT,
      endT: e.endT,
      durationS: dur,
      startIdx: a,
      endIdx: b,
      lat: s.lat,
      lon: s.lon,
      detail: { kind: 'phone_handling', interactions: e.events.length, maxSpeed: e.maxSpeed, kinds },
    };
  });
}

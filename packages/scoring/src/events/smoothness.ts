import { SMOOTHNESS } from '../constants';
import { durationS, runs, sampleIndexAt, type PreparedTrip } from '../prepare';
import type { EventKind, MotionEvent, Severity, TripEvent } from '../types';

type MotionKind = 'harsh_brake' | 'harsh_accel' | 'hard_corner';

const THRESH: Record<MotionKind, { moderate: number; severe: number }> = {
  harsh_brake: SMOOTHNESS.brake,
  harsh_accel: SMOOTHNESS.accel,
  hard_corner: SMOOTHNESS.corner,
};

function severityFor(kind: MotionKind, peak: number): Severity | null {
  const t = THRESH[kind];
  if (peak >= t.severe) return 'severe';
  if (peak >= t.moderate) return 'moderate';
  return null;
}

function makeEvent(p: PreparedTrip, kind: MotionKind, a: number, b: number, peak: number): TripEvent {
  const s = p.samples[a]!;
  return {
    kind,
    severity: severityFor(kind, peak) ?? 'moderate',
    startT: s.t,
    endT: p.samples[b]!.t,
    durationS: durationS(p.samples, a, b),
    startIdx: a,
    endIdx: b,
    lat: s.lat,
    lon: s.lon,
    detail: { kind, peak, speedAtStart: p.speed[Math.max(0, a - 1)]! },
  };
}

/**
 * Derives harsh brake / accel / corner events from GPS when no accelerometer events are supplied.
 * At 1 Hz, "sustained ≥ 0.7 s" means at least one full interval over threshold.
 */
function fromGps(p: PreparedTrip): TripEvent[] {
  const { samples, accel, lateral, speed, goodFix, firstMoving, lastMoving } = p;
  const out: TripEvent[] = [];

  const detect = (kind: MotionKind, value: (i: number) => number) => {
    const threshold = THRESH[kind].moderate;
    const pred = (i: number) => goodFix[i]! && goodFix[i - 1]! && p.dt[i]! >= SMOOTHNESS.minSustainedS && value(i) >= threshold;
    for (const [a, b] of runs(firstMoving + 1, lastMoving, samples, pred, SMOOTHNESS.mergeGapS)) {
      let peak = 0;
      for (let i = a; i <= b; i++) peak = Math.max(peak, value(i));
      out.push(makeEvent(p, kind, a, b, peak));
    }
  };

  detect('harsh_brake', (i) => -accel[i]!);
  detect('harsh_accel', (i) => accel[i]!);
  detect('hard_corner', (i) => (speed[i]! >= SMOOTHNESS.cornerMinSpeed ? lateral[i]! : 0));

  return out;
}

const KIND_MAP: Record<MotionEvent['kind'], MotionKind> = {
  brake: 'harsh_brake',
  accel: 'harsh_accel',
  corner: 'hard_corner',
};

/** Uses pre-detected accelerometer events, merging bursts within mergeGapS. */
function fromMotionEvents(p: PreparedTrip, motion: MotionEvent[]): TripEvent[] {
  const out: TripEvent[] = [];
  const sorted = [...motion].sort((a, b) => a.t - b.t);
  for (const kind of ['brake', 'accel', 'corner'] as const) {
    const mk = KIND_MAP[kind];
    let cur: { start: number; end: number; peak: number } | null = null;
    const flush = () => {
      if (!cur) return;
      if (severityFor(mk, cur.peak)) {
        const a = sampleIndexAt(p.samples, cur.start);
        const b = sampleIndexAt(p.samples, cur.end);
        out.push(makeEvent(p, mk, a, Math.max(a, b), cur.peak));
      }
      cur = null;
    };
    for (const m of sorted) {
      if (m.kind !== kind) continue;
      if (cur && (m.t - cur.end) / 1000 < SMOOTHNESS.mergeGapS) {
        cur.end = m.t;
        cur.peak = Math.max(cur.peak, m.peak);
      } else {
        flush();
        cur = { start: m.t, end: m.t, peak: m.peak };
      }
    }
    flush();
  }
  return out.sort((x, y) => x.startIdx - y.startIdx);
}

export function detectSmoothness(p: PreparedTrip): TripEvent[] {
  const motion = p.input.motionEvents;
  if (motion && motion.length > 0) return fromMotionEvents(p, motion);
  return fromGps(p);
}

export function isMotionKind(kind: EventKind): kind is MotionKind {
  return kind === 'harsh_brake' || kind === 'harsh_accel' || kind === 'hard_corner';
}

import { GPS_MAX_ACCURACY, MOVING_SPEED } from './constants';
import { bearing, haversine, headingDelta } from './geo';
import type { GpsSample, RoadSegment, TripInput } from './types';

/**
 * Per-sample derived values used by every detector. Computed once.
 */
export interface PreparedTrip {
  input: TripInput;
  samples: GpsSample[];
  /** Seconds between sample i-1 and i (0 for i = 0). */
  dt: number[];
  /** Median-filtered speed, m/s. Removes single-sample GPS spikes. */
  speed: number[];
  /** Longitudinal acceleration between i-1 and i, m/s² (positive = speeding up). */
  accel: number[];
  /** Heading in degrees, from the sample or derived from positions. NaN when unknown. */
  heading: number[];
  /** Lateral acceleration estimate, m/s² (speed × heading rate). 0 when unknown. */
  lateral: number[];
  /** Distance travelled between i-1 and i, m. */
  stepDistance: number[];
  /** Segment covering sample i, or undefined. */
  segmentAt: (RoadSegment | undefined)[];
  /** True when accuracy is good enough for speeding judgments. */
  goodFix: boolean[];
  /** Index bounds of the "moving" part of the trip (trims stationary start/end). */
  firstMoving: number;
  lastMoving: number;
}

function median3(a: number, b: number, c: number): number {
  return Math.max(Math.min(a, b), Math.min(Math.max(a, b), c));
}

export function prepare(input: TripInput): PreparedTrip {
  const samples = [...input.samples].sort((a, b) => a.t - b.t);
  const n = samples.length;

  const dt = new Array<number>(n).fill(0);
  const rawSpeed = samples.map((s) => Math.max(0, s.speed));
  const speed = new Array<number>(n).fill(0);
  const accel = new Array<number>(n).fill(0);
  const heading = new Array<number>(n).fill(NaN);
  const lateral = new Array<number>(n).fill(0);
  const stepDistance = new Array<number>(n).fill(0);
  const goodFix = samples.map((s) => s.accuracy <= GPS_MAX_ACCURACY);

  for (let i = 0; i < n; i++) {
    const prev = rawSpeed[i - 1] ?? rawSpeed[i] ?? 0;
    const cur = rawSpeed[i] ?? 0;
    const next = rawSpeed[i + 1] ?? cur;
    speed[i] = n >= 3 ? median3(prev, cur, next) : cur;
  }

  for (let i = 1; i < n; i++) {
    const a = samples[i - 1]!;
    const b = samples[i]!;
    const d = Math.max(0.001, (b.t - a.t) / 1000);
    dt[i] = d;
    stepDistance[i] = haversine(a.lat, a.lon, b.lat, b.lon);
    accel[i] = (speed[i]! - speed[i - 1]!) / d;
  }

  for (let i = 0; i < n; i++) {
    const s = samples[i]!;
    if (typeof s.heading === 'number' && Number.isFinite(s.heading)) {
      heading[i] = s.heading;
    } else if (i > 0 && stepDistance[i]! > 2) {
      const p = samples[i - 1]!;
      heading[i] = bearing(p.lat, p.lon, s.lat, s.lon);
    } else if (i > 0) {
      heading[i] = heading[i - 1]!;
    }
  }

  for (let i = 1; i < n; i++) {
    const h0 = heading[i - 1]!;
    const h1 = heading[i]!;
    if (Number.isNaN(h0) || Number.isNaN(h1)) continue;
    const rate = (headingDelta(h0, h1) * Math.PI) / 180 / dt[i]!; // rad/s
    lateral[i] = Math.abs(rate) * speed[i]!;
  }

  const segmentAt = new Array<RoadSegment | undefined>(n).fill(undefined);
  for (const seg of input.segments) {
    const from = Math.max(0, seg.fromIdx);
    const to = Math.min(n - 1, seg.toIdx);
    for (let i = from; i <= to; i++) segmentAt[i] = seg;
  }

  let firstMoving = 0;
  while (firstMoving < n && speed[firstMoving]! <= MOVING_SPEED) firstMoving++;
  let lastMoving = n - 1;
  while (lastMoving > firstMoving && speed[lastMoving]! <= MOVING_SPEED) lastMoving--;
  if (firstMoving >= n) {
    firstMoving = 0;
    lastMoving = Math.max(0, n - 1);
  }

  return {
    input,
    samples,
    dt,
    speed,
    accel,
    heading,
    lateral,
    stepDistance,
    segmentAt,
    goodFix,
    firstMoving,
    lastMoving,
  };
}

/** Index of the sample closest in time to `t` (binary search). */
export function sampleIndexAt(samples: GpsSample[], t: number): number {
  let lo = 0;
  let hi = samples.length - 1;
  while (lo < hi) {
    const mid = (lo + hi) >> 1;
    if (samples[mid]!.t < t) lo = mid + 1;
    else hi = mid;
  }
  if (lo > 0 && Math.abs(samples[lo - 1]!.t - t) < Math.abs(samples[lo]!.t - t)) return lo - 1;
  return lo;
}

/**
 * Group consecutive indices where `predicate(i)` holds into runs, merging runs separated
 * by a time gap smaller than `mergeGapS`. Returns [startIdx, endIdx] inclusive pairs.
 */
export function runs(
  from: number,
  to: number,
  samples: GpsSample[],
  predicate: (i: number) => boolean,
  mergeGapS: number,
): Array<[number, number]> {
  const out: Array<[number, number]> = [];
  let start = -1;
  for (let i = from; i <= to; i++) {
    const hit = predicate(i);
    if (hit && start === -1) start = i;
    if (!hit && start !== -1) {
      out.push([start, i - 1]);
      start = -1;
    }
  }
  if (start !== -1) out.push([start, to]);

  const merged: Array<[number, number]> = [];
  for (const r of out) {
    const last = merged[merged.length - 1];
    if (last && (samples[r[0]]!.t - samples[last[1]]!.t) / 1000 < mergeGapS) {
      last[1] = r[1];
    } else {
      merged.push([r[0], r[1]]);
    }
  }
  return merged;
}

export function durationS(samples: GpsSample[], startIdx: number, endIdx: number): number {
  const d = (samples[endIdx]!.t - samples[startIdx]!.t) / 1000;
  // A one-sample run still represents roughly one sampling interval.
  return Math.max(d, 1);
}

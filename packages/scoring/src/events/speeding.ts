import { SPEEDING, SPEEDING_MIN_CONFIDENCE } from '../constants';
import { durationS, runs, type PreparedTrip } from '../prepare';
import type { Severity, TripEvent } from '../types';

export interface SpeedingResult {
  /** Episodes on confident segments. These score. */
  events: TripEvent[];
  /** Episodes on low-confidence segments. Shown, never scored. */
  observations: TripEvent[];
  /** Sum of confident episode durations. */
  secondsOverLimit: number;
  secondsWithKnownLimit: number;
  timeSavedBySpeedingS: number;
}

function severityForOver(maxOver: number, maxSpeed: number): Severity {
  if (maxOver >= SPEEDING.thresholds.reckless || maxSpeed >= SPEEDING.recklessAbsolute) return 'reckless';
  if (maxOver >= SPEEDING.thresholds.major) return 'major';
  if (maxOver >= SPEEDING.thresholds.moderate) return 'moderate';
  return 'minor';
}

function buildEpisode(p: PreparedTrip, start: number, end: number, confident: boolean): TripEvent {
  const seg = p.segmentAt[start]!;
  const limit = seg.speedLimit!;
  let maxSpeed = 0;
  let maxOver = 0;
  let overSum = 0;
  let count = 0;
  let timeSaved = 0;
  for (let i = start; i <= end; i++) {
    const v = p.speed[i]!;
    const over = v - limit;
    if (v > maxSpeed) maxSpeed = v;
    if (over > maxOver) maxOver = over;
    if (over > 0) {
      overSum += over;
      count++;
      const d = p.stepDistance[i]!;
      // time at limit minus time actually taken
      timeSaved += d / limit - d / Math.max(v, 0.1);
    }
  }
  const s = p.samples[start]!;
  return {
    kind: 'speeding',
    severity: confident ? severityForOver(maxOver, maxSpeed) : 'minor',
    startT: s.t,
    endT: p.samples[end]!.t,
    durationS: durationS(p.samples, start, end),
    startIdx: start,
    endIdx: end,
    lat: s.lat,
    lon: s.lon,
    detail: {
      kind: 'speeding',
      limit,
      maxSpeed,
      avgOver: count ? overSum / count : 0,
      maxOver,
      roadName: seg.name,
      roadClass: seg.roadClass,
      timeSavedS: Math.max(0, timeSaved),
    },
  };
}

/**
 * Samples exempt from speeding judgment because the posted limit just dropped and the car is
 * still slowing down (a 65 → 25 exit ramp takes ~12 s at a comfortable 1.5 m/s²).
 *
 * The exemption lasts at most SPEEDING.limitDropGraceS after the drop, requires the car to be
 * decelerating after the first few seconds, and ends as soon as the driver accelerates or gets
 * under limit + minOver.
 */
function limitDropExemptions(p: PreparedTrip): boolean[] {
  const { samples, speed, segmentAt } = p;
  const n = samples.length;
  const exempt = new Array<boolean>(n).fill(false);
  let dropAt = -Infinity;
  let active = false;

  for (let i = 1; i < n; i++) {
    const prev = segmentAt[i - 1];
    const seg = segmentAt[i];
    if (
      seg &&
      prev &&
      seg !== prev &&
      seg.speedLimit !== null &&
      prev.speedLimit !== null &&
      seg.speedLimit < prev.speedLimit - 0.5
    ) {
      dropAt = samples[i]!.t;
      active = true;
    }
    if (!active || !seg || seg.speedLimit === null) continue;

    const elapsed = (samples[i]!.t - dropAt) / 1000;
    const decelerating = speed[i]! <= speed[i - 1]! - SPEEDING.graceMinDecel;
    const underThreshold = speed[i]! < seg.speedLimit + SPEEDING.minOver;

    if (underThreshold || elapsed > SPEEDING.limitDropGraceS || (elapsed > SPEEDING.graceFreeS && !decelerating)) {
      active = false;
      continue;
    }
    exempt[i] = true;
  }
  return exempt;
}

/**
 * Detects speeding episodes. An episode is a run of samples over the limit by at least
 * SPEEDING.minOver on a single segment-confidence class, merged across short gaps,
 * lasting at least SPEEDING.minDurationS.
 *
 * Also detects the absolute-reckless case (≥ 100 mph) on any road, limit known or not.
 */
export function detectSpeeding(p: PreparedTrip): SpeedingResult {
  const { samples, speed, segmentAt, goodFix, firstMoving, lastMoving } = p;
  const exempt = limitDropExemptions(p);

  const overBy = (i: number, confident: boolean): boolean => {
    const seg = segmentAt[i];
    if (!seg || seg.speedLimit === null || !goodFix[i] || exempt[i]) return false;
    const confOk = confident ? seg.confidence >= SPEEDING_MIN_CONFIDENCE : seg.confidence < SPEEDING_MIN_CONFIDENCE;
    return confOk && speed[i]! - seg.speedLimit >= SPEEDING.minOver;
  };

  const events: TripEvent[] = [];
  const observations: TripEvent[] = [];

  for (const [a, b] of runs(firstMoving, lastMoving, samples, (i) => overBy(i, true), SPEEDING.mergeGapS)) {
    if (durationS(samples, a, b) >= SPEEDING.minDurationS) events.push(buildEpisode(p, a, b, true));
  }
  for (const [a, b] of runs(firstMoving, lastMoving, samples, (i) => overBy(i, false), SPEEDING.mergeGapS)) {
    if (durationS(samples, a, b) >= SPEEDING.minDurationS) observations.push(buildEpisode(p, a, b, false));
  }

  // Absolute reckless speed, independent of limit knowledge.
  const absolute = (i: number): boolean => goodFix[i]! && speed[i]! >= SPEEDING.recklessAbsolute;
  for (const [a, b] of runs(firstMoving, lastMoving, samples, absolute, SPEEDING.mergeGapS)) {
    if (durationS(samples, a, b) < SPEEDING.recklessAbsoluteMinDurationS) continue;
    const overlapping = events.find((e) => e.startIdx <= b && e.endIdx >= a);
    if (overlapping) {
      overlapping.severity = 'reckless';
      continue;
    }
    const s = samples[a]!;
    const seg = segmentAt[a];
    let maxSpeed = 0;
    for (let i = a; i <= b; i++) maxSpeed = Math.max(maxSpeed, speed[i]!);
    const limit = seg?.speedLimit ?? NaN;
    events.push({
      kind: 'speeding',
      severity: 'reckless',
      startT: s.t,
      endT: samples[b]!.t,
      durationS: durationS(samples, a, b),
      startIdx: a,
      endIdx: b,
      lat: s.lat,
      lon: s.lon,
      detail: {
        kind: 'speeding',
        limit,
        maxSpeed,
        avgOver: Number.isNaN(limit) ? NaN : maxSpeed - limit,
        maxOver: Number.isNaN(limit) ? NaN : maxSpeed - limit,
        roadName: seg?.name,
        roadClass: seg?.roadClass ?? 'unknown',
        timeSavedS: 0,
      },
    });
  }

  events.sort((x, y) => x.startIdx - y.startIdx);

  let secondsWithKnownLimit = 0;
  for (let i = firstMoving + 1; i <= lastMoving; i++) {
    const seg = segmentAt[i];
    if (!seg || seg.speedLimit === null || seg.confidence < SPEEDING_MIN_CONFIDENCE) continue;
    secondsWithKnownLimit += p.dt[i]!;
  }

  const secondsOverLimit = events.reduce((acc, e) => acc + e.durationS, 0);
  const timeSavedBySpeedingS = events.reduce(
    (acc, e) => acc + (e.detail.kind === 'speeding' ? e.detail.timeSavedS : 0),
    0,
  );

  return { events, observations, secondsOverLimit, secondsWithKnownLimit, timeSavedBySpeedingS };
}

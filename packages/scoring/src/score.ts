import {
  ATTENTION,
  EFFICIENCY,
  MINIMUMS,
  MOVING_SPEED,
  RECKLESS,
  SMOOTHNESS,
  SPEEDING,
  XP,
} from './constants';
import { detectPhoneHandling } from './events/attention';
import { detectHighSpeedCruise, detectIdling } from './events/efficiency';
import { detectSmoothness, isMotionKind } from './events/smoothness';
import { detectSpeeding } from './events/speeding';
import { prepare, type PreparedTrip } from './prepare';
import { buildFeedback } from './roast';
import type {
  ComponentPenalties,
  Flag,
  ScoreOptions,
  TripEvent,
  TripInput,
  TripScore,
  TripSummary,
} from './types';

const clamp = (v: number, lo: number, hi: number): number => Math.min(hi, Math.max(lo, v));
const round1 = (v: number): number => Math.round(v * 10) / 10;

function summarise(p: PreparedTrip, speeding: ReturnType<typeof detectSpeeding>): TripSummary {
  const { samples, speed, dt, stepDistance, goodFix } = p;
  const n = samples.length;
  let distanceM = 0;
  let movingTimeS = 0;
  let maxSpeed = 0;
  let good = 0;
  for (let i = 0; i < n; i++) {
    if (goodFix[i]) good++;
    if (i === 0) continue;
    distanceM += stepDistance[i]!;
    if (speed[i]! > MOVING_SPEED) movingTimeS += dt[i]!;
    if (goodFix[i] && speed[i]! > maxSpeed) maxSpeed = speed[i]!;
  }
  const startT = samples[0]?.t ?? 0;
  const endT = samples[n - 1]?.t ?? startT;
  return {
    distanceM,
    movingTimeS,
    totalTimeS: (endT - startT) / 1000,
    maxSpeed,
    avgMovingSpeed: movingTimeS > 0 ? distanceM / movingTimeS : 0,
    secondsOverLimit: speeding.secondsOverLimit,
    secondsWithKnownLimit: speeding.secondsWithKnownLimit,
    timeSavedBySpeedingS: speeding.timeSavedBySpeedingS,
    startT,
    endT,
    nightFraction: p.input.context?.nightFraction ?? 0,
    gpsQuality: n > 0 ? good / n : 0,
  };
}

function speedPenalty(events: TripEvent[], summary: TripSummary): number {
  let total = 0;
  for (const e of events) {
    if (e.kind !== 'speeding') continue;
    const sev = e.severity as keyof typeof SPEEDING.weightPerMinute;
    const w = SPEEDING.weightPerMinute[sev] ?? SPEEDING.weightPerMinute.minor;
    total += (w * Math.min(e.durationS, SPEEDING.maxPenalisedDurationS)) / 60;
  }
  if (summary.movingTimeS > 0) {
    total += SPEEDING.proportionWeight * (summary.secondsOverLimit / summary.movingTimeS);
  }
  return clamp(total, 0, SPEEDING.cap);
}

function smoothnessPenalty(events: TripEvent[], summary: TripSummary): number {
  let raw = 0;
  for (const e of events) {
    if (!isMotionKind(e.kind)) continue;
    const table = SMOOTHNESS.weights[e.kind];
    raw += e.severity === 'severe' ? table.severe : table.moderate;
  }
  const norm = SMOOTHNESS.normaliseDistanceM / Math.max(summary.distanceM, SMOOTHNESS.minNormaliseDistanceM);
  return clamp(raw * norm, 0, SMOOTHNESS.cap);
}

function attentionPenalty(events: TripEvent[]): number {
  let total = 0;
  for (const e of events) {
    if (e.kind !== 'phone_handling') continue;
    const sev = e.severity as keyof typeof ATTENTION.weights;
    total += ATTENTION.weights[sev] ?? ATTENTION.weights.minor;
  }
  return clamp(total, 0, ATTENTION.cap);
}

function efficiencyPenalty(events: TripEvent[]): number {
  let idle = 0;
  let cruise = 0;
  let aggression = 0;
  for (const e of events) {
    if (e.kind === 'idling' && e.detail.kind === 'idling') {
      idle += (EFFICIENCY.idle.weightPerMinute * e.detail.excessS) / 60;
    } else if (e.kind === 'high_speed_cruise') {
      cruise += (EFFICIENCY.cruise.weightPerMinute * e.durationS) / 60;
    } else if (e.kind === 'harsh_accel') {
      aggression += EFFICIENCY.aggression.perHarshAccel;
    }
  }
  const total =
    clamp(idle, 0, EFFICIENCY.idle.cap) +
    clamp(cruise, 0, EFFICIENCY.cruise.cap) +
    clamp(aggression, 0, EFFICIENCY.aggression.cap);
  return clamp(total, 0, EFFICIENCY.cap);
}

function recklessFlags(events: TripEvent[]): Flag[] {
  const flags: Flag[] = [];
  if (events.some((e) => e.kind === 'speeding' && e.severity === 'reckless')) flags.push('reckless_speed');
  if (
    events.some(
      (e) =>
        e.kind === 'phone_handling' &&
        e.severity === 'major' &&
        e.detail.kind === 'phone_handling' &&
        e.detail.maxSpeed >= ATTENTION.majorSpeed &&
        e.durationS >= ATTENTION.recklessDurationS,
    )
  ) {
    flags.push('reckless_phone');
  }
  const severeMotion = events.filter((e) => isMotionKind(e.kind) && e.severity === 'severe').length;
  const majorSpeeding = events.some(
    (e) => e.kind === 'speeding' && (e.severity === 'major' || e.severity === 'reckless'),
  );
  if (severeMotion >= RECKLESS.patternSevereEvents && majorSpeeding) flags.push('reckless_pattern');
  return flags;
}

export function computeXp(
  score: number,
  distanceM: number,
  ctx: TripInput['context'] | undefined,
  reckless: boolean,
): number {
  if (reckless || score < XP.minScore) return 0;
  const baseline = XP.minXp + ((score - XP.minScore) / (100 - XP.minScore)) * (XP.maxXp - XP.minXp);

  const distanceKm = distanceM / 1000;
  const before = ctx?.dailyCreditedKmBefore ?? 0;
  const creditedKm = clamp(Math.min(distanceKm, XP.dailyCapKm - before), 0, XP.dailyCapKm);
  const distanceFactor =
    creditedKm <= 0 ? XP.distanceFloor : Math.min(1, XP.distanceFloor + (1 - XP.distanceFloor) * (creditedKm / XP.fullCreditKm));

  let bonus = 1;
  if (score >= XP.bonusMinScore) {
    if ((ctx?.nightFraction ?? 0) >= 0.5) bonus *= XP.nightBonus;
    if (ctx?.weather === 'rain' || ctx?.weather === 'snow') bonus *= XP.weatherBonus;
  }
  bonus = Math.min(bonus, XP.maxContextBonus);

  let xp = baseline * distanceFactor * bonus;

  const streak = ctx?.cleanStreak ?? 0;
  if (score >= XP.cleanTripScore) {
    if (streak >= XP.streak.tier2) xp += XP.streak.tier2Xp;
    else if (streak >= XP.streak.tier1) xp += XP.streak.tier1Xp;
  }
  return Math.round(xp);
}

const SEVERITY_RANK: Record<TripEvent['severity'], number> = {
  minor: 1,
  moderate: 2,
  major: 3,
  severe: 3,
  reckless: 4,
};

/** Sort events by severity (worst first), then by time. Used for feedback and display. */
export function sortBySeverity(events: TripEvent[]): TripEvent[] {
  return [...events].sort((a, b) => SEVERITY_RANK[b.severity] - SEVERITY_RANK[a.severity] || a.startT - b.startT);
}

function unscored(
  input: TripInput,
  summary: TripSummary,
  reason: 'too_short' | 'passenger',
  options: ScoreOptions,
): TripScore {
  const penalties: ComponentPenalties = { speed: 0, smoothness: 0, attention: 0, efficiency: 0 };
  const base: Omit<TripScore, 'feedback'> = {
    tripId: input.id,
    scored: false,
    unscoredReason: reason,
    score: 0,
    penalties,
    flags: [],
    reckless: false,
    xp: 0,
    events: [],
    observations: [],
    summary,
  };
  return { ...base, feedback: buildFeedback(base, options) };
}

/**
 * Score a trip. Pure function: same input, same output.
 */
export function scoreTrip(input: TripInput, options: ScoreOptions = {}): TripScore {
  const p = prepare(input);
  const speeding = detectSpeeding(p);
  const summary = summarise(p, speeding);

  if (input.context?.isPassenger) return unscored(input, summary, 'passenger', options);
  if (summary.distanceM < MINIMUMS.distanceM || summary.movingTimeS < MINIMUMS.movingTimeS) {
    return unscored(input, summary, 'too_short', options);
  }

  const events: TripEvent[] = [
    ...speeding.events,
    ...detectSmoothness(p),
    ...detectPhoneHandling(p),
    ...detectIdling(p),
    ...detectHighSpeedCruise(p),
  ].sort((a, b) => a.startT - b.startT);

  const penalties: ComponentPenalties = {
    speed: round1(speedPenalty(events, summary)),
    smoothness: round1(smoothnessPenalty(events, summary)),
    attention: round1(attentionPenalty(events)),
    efficiency: round1(efficiencyPenalty(events)),
  };

  const flags = recklessFlags(events);
  if (summary.gpsQuality < 0.7) flags.push('low_gps_quality');
  if (summary.movingTimeS > 0 && summary.secondsWithKnownLimit / summary.movingTimeS < 0.5) {
    flags.push('limits_unknown');
  }
  const reckless = flags.some((f) => f.startsWith('reckless_'));

  let score = Math.round(
    clamp(100 - penalties.speed - penalties.smoothness - penalties.attention - penalties.efficiency, 0, 100),
  );
  if (reckless) score = Math.min(score, RECKLESS.scoreCap);

  const xp = computeXp(score, summary.distanceM, input.context, reckless);

  const base: Omit<TripScore, 'feedback'> = {
    tripId: input.id,
    scored: true,
    score,
    penalties,
    flags,
    reckless,
    xp,
    events,
    observations: speeding.observations,
    summary,
  };
  return { ...base, feedback: buildFeedback(base, options) };
}

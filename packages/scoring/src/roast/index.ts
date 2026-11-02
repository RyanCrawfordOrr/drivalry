import { mpsToKmh, mpsToMph } from '../constants';
import { TEMPLATES, type TemplateKey } from './templates';
import type { FeedbackLine, Intensity, ScoreOptions, TripEvent, TripScore } from '../types';

type Base = Omit<TripScore, 'feedback'>;

/** FNV-1a 32-bit. Deterministic template choice per trip. */
export function hash(s: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h >>> 0;
}

export function formatDuration(seconds: number): string {
  const s = Math.round(seconds);
  if (s < 60) return `${s} seconds`;
  if (s < 120) return s % 60 < 10 ? 'a minute' : `${Math.floor(s / 60)} min ${s % 60} s`;
  const m = Math.round(s / 60);
  return `${m} minutes`;
}

export function formatSaved(seconds: number): string {
  const s = Math.round(seconds);
  if (s <= 0) return 'nothing';
  if (s < 60) return `${s} seconds`;
  return `${Math.round(s / 60)} minutes`;
}

function speedStr(mps: number, units: 'mph' | 'kmh'): string {
  const v = units === 'mph' ? mpsToMph(mps) : mpsToKmh(mps);
  return `${Math.round(v)}`;
}

function distanceStr(m: number, units: 'mph' | 'kmh'): string {
  if (units === 'mph') {
    const mi = m / 1609.344;
    return mi < 10 ? `${mi.toFixed(1)} miles` : `${Math.round(mi)} miles`;
  }
  const km = m / 1000;
  return km < 10 ? `${km.toFixed(1)} km` : `${Math.round(km)} km`;
}

function roadStr(e: TripEvent): string {
  const name = e.detail.kind === 'speeding' ? e.detail.roadName : undefined;
  if (name) return name;
  if (e.detail.kind === 'speeding') {
    switch (e.detail.roadClass) {
      case 'motorway':
      case 'trunk':
        return 'the highway';
      case 'residential':
        return 'a residential street';
      default:
        return 'that road';
    }
  }
  return 'that road';
}

function fill(template: string, slots: Record<string, string>): string {
  return template.replace(/\{(\w+)\}/g, (_, k: string) => slots[k] ?? `{${k}}`);
}

function pick(key: TemplateKey, intensity: Intensity, seed: string): string {
  const list = TEMPLATES[key][intensity];
  const idx = hash(seed) % list.length;
  return list[idx]!;
}

function templateKeyFor(e: TripEvent): TemplateKey | null {
  switch (e.kind) {
    case 'speeding':
      return `speeding.${e.severity as 'minor' | 'moderate' | 'major' | 'reckless'}`;
    case 'harsh_brake':
    case 'harsh_accel':
    case 'hard_corner':
      return `${e.kind}.${e.severity as 'moderate' | 'severe'}`;
    case 'phone_handling':
      return `phone_handling.${e.severity as 'minor' | 'moderate' | 'major'}`;
    case 'idling':
      return 'idling';
    case 'high_speed_cruise':
      return 'high_speed_cruise';
  }
}

function slotsFor(e: TripEvent, units: 'mph' | 'kmh'): Record<string, string> {
  const unit = units === 'mph' ? 'mph' : 'km/h';
  const slots: Record<string, string> = {
    unit,
    duration: formatDuration(e.durationS),
    road: roadStr(e),
  };
  switch (e.detail.kind) {
    case 'speeding': {
      const d = e.detail;
      slots.speed = speedStr(d.maxSpeed, units);
      slots.limit = Number.isNaN(d.limit) ? 'zone with no posted limit' : speedStr(d.limit, units);
      slots.over = Number.isNaN(d.maxOver) ? '?' : speedStr(d.maxOver, units);
      slots.saved = formatSaved(d.timeSavedS);
      break;
    }
    case 'harsh_brake':
    case 'harsh_accel':
    case 'hard_corner':
      slots.peak = e.detail.peak.toFixed(1);
      slots.speed = speedStr(e.detail.speedAtStart, units);
      break;
    case 'phone_handling':
      slots.speed = speedStr(e.detail.maxSpeed, units);
      slots.phoneSeconds = formatDuration(e.durationS);
      slots.count = `${e.detail.interactions}`;
      break;
    case 'idling':
      slots.idleMinutes = formatDuration(e.durationS);
      break;
    case 'high_speed_cruise':
      slots.cruiseMinutes = formatDuration(e.durationS);
      slots.speed = speedStr(e.detail.maxSpeed, units);
      break;
  }
  return slots;
}

const RANK: Record<TripEvent['severity'], number> = { minor: 1, moderate: 2, major: 3, severe: 3, reckless: 4 };

/** Roast line for one event. Exported for the UI's per-event detail view. */
export function roastEvent(e: TripEvent, tripId: string, index: number, options: ScoreOptions = {}): FeedbackLine | null {
  const key = templateKeyFor(e);
  if (!key) return null;
  const intensity = options.intensity ?? 'sassy';
  const units = options.units ?? 'mph';
  const text = fill(pick(key, intensity, `${tripId}:${key}:${index}`), slotsFor(e, units));
  return { tone: 'roast', text, eventIndex: index };
}

/**
 * Builds the headline and supporting lines for a scored trip.
 * Headline: reckless event > worst event > praise. Then up to two more roasts and one praise line.
 */
export function buildFeedback(base: Base, options: ScoreOptions = {}): TripScore['feedback'] {
  const intensity = options.intensity ?? 'sassy';
  const units = options.units ?? 'mph';
  const distance = distanceStr(base.summary.distanceM, units);
  const common = { distance, score: `${base.score}`, unit: units === 'mph' ? 'mph' : 'km/h' };

  if (!base.scored) {
    const key: TemplateKey = base.unscoredReason === 'passenger' ? 'unscored.passenger' : 'unscored.too_short';
    const headline: FeedbackLine = { tone: 'praise', text: fill(pick(key, intensity, base.tripId), common) };
    return { headline, lines: [] };
  }

  const ranked = base.events
    .map((e, i) => ({ e, i }))
    .filter(({ e }) => e.kind !== 'idling' || e.durationS > 180) // tiny idles are not worth a line
    .sort((a, b) => RANK[b.e.severity] - RANK[a.e.severity] || b.e.durationS - a.e.durationS);

  const roasts: FeedbackLine[] = [];
  for (const { e, i } of ranked) {
    const line = roastEvent(e, base.tripId, i, options);
    if (line) roasts.push(line);
    if (roasts.length >= 3) break;
  }

  const praise: FeedbackLine[] = [];
  const hasKind = (k: TripEvent['kind']) => base.events.some((e) => e.kind === k);
  const longEnough = base.summary.distanceM >= 5_000;
  if (base.events.length === 0) {
    const key: TemplateKey = base.summary.distanceM >= 20_000 ? 'praise.clean_long' : 'praise.perfect';
    praise.push({ tone: 'praise', text: fill(pick(key, intensity, base.tripId), common) });
  } else {
    if (!hasKind('phone_handling') && longEnough) {
      praise.push({ tone: 'praise', text: fill(pick('praise.phone_free', intensity, base.tripId + ':pf'), common) });
    } else if (!hasKind('harsh_brake') && !hasKind('harsh_accel') && !hasKind('hard_corner') && longEnough) {
      praise.push({ tone: 'praise', text: fill(pick('praise.smooth', intensity, base.tripId + ':sm'), common) });
    } else if (!hasKind('speeding') && base.summary.secondsWithKnownLimit > 120) {
      praise.push({ tone: 'praise', text: fill(pick('praise.limit_respect', intensity, base.tripId + ':lr'), common) });
    }
  }

  const worst = ranked[0]?.e;
  const worthLeadingWith = !!worst && RANK[worst.severity] >= RANK.moderate;
  let headline: FeedbackLine;
  if (roasts.length > 0 && (base.reckless || worthLeadingWith || base.score < 90)) {
    headline = roasts[0]!;
  } else if (praise.length > 0) {
    headline = praise[0]!;
  } else {
    headline = { tone: 'praise', text: fill(pick('praise.good', intensity, base.tripId), common) };
  }

  const lines = [...roasts, ...praise].filter((l) => l !== headline).slice(0, 3);
  return { headline, lines };
}

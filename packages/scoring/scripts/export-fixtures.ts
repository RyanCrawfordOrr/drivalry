/**
 * Fixture exporter.
 *
 * Runs the TypeScript scoring engine over a fixed set of trips and writes the complete
 * input and the complete output of every case to `packages/scoring/fixtures/` as JSON.
 * Ports of the engine (currently `packages/drivalry_scoring`, Dart) load these files and
 * assert that they produce the same output; the TypeScript package is the specification
 * and these files are the contract.
 *
 *   npm run fixtures            (from the repo root, or inside packages/scoring)
 *
 * Conventions (also documented in the generated fixtures/README.md):
 *  - JSON cannot carry NaN or ±Infinity. They are written as the strings "NaN",
 *    "Infinity" and "-Infinity".
 *  - `undefined` properties are omitted, exactly as JSON.stringify does. A port must treat
 *    a missing key and a null value as the same thing.
 */
import { mkdirSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  buildSyntheticTrip,
  cleanCommute,
  computeXp,
  formatDuration,
  formatSaved,
  messyCommute,
  roastEvent,
  scoreTrip,
  sortBySeverity,
  TEMPLATES,
  type FeedbackLine,
  type Intensity,
  type ScoreOptions,
  type SyntheticSpec,
  type TripContext,
  type TripInput,
  type TripScore,
} from '../src';
import { hash } from '../src/roast';

const here = dirname(fileURLToPath(import.meta.url));
const outDir = join(here, '..', 'fixtures');

// ---------------------------------------------------------------------------------------
// Case definitions
// ---------------------------------------------------------------------------------------

/** How the input was produced, so a port can also check its own synthetic builder. */
type Source =
  | { builder: 'buildSyntheticTrip'; spec: SyntheticSpec }
  | { builder: 'cleanCommute' | 'messyCommute'; id: string }
  | { builder: 'manual' };

interface TripCase {
  name: string;
  description: string;
  /** Which TS test (or doc section) this case mirrors. */
  mirrors: string;
  source: Source;
  options: ScoreOptions;
  input: TripInput;
}

const INTENSITIES: Intensity[] = ['gentle', 'sassy', 'savage'];
const UNITS: Array<'mph' | 'kmh'> = ['mph', 'kmh'];

function synthetic(
  name: string,
  description: string,
  mirrors: string,
  spec: SyntheticSpec,
  options: ScoreOptions = {},
  mutate?: (input: TripInput) => TripInput,
): TripCase {
  const built = buildSyntheticTrip(spec);
  const input = mutate ? mutate(built) : built;
  return { name, description, mirrors, source: { builder: 'buildSyntheticTrip', spec }, options, input };
}

function canned(
  name: string,
  description: string,
  mirrors: string,
  builder: 'cleanCommute' | 'messyCommute',
  id: string,
  options: ScoreOptions = {},
  mutate?: (input: TripInput) => TripInput,
): TripCase {
  const built = builder === 'cleanCommute' ? cleanCommute(id) : messyCommute(id);
  const input = mutate ? mutate(built) : built;
  return { name, description, mirrors, source: { builder, id }, options, input };
}

const withContext =
  (context: TripContext) =>
  (input: TripInput): TripInput => ({ ...input, context });

const CASES: TripCase[] = [
  // --- canned commutes ----------------------------------------------------------------
  canned(
    'clean-commute',
    'The canned 20-minute clean commute. Score 100, XP 100, praise headline.',
    'score.test.ts › end-to-end fixtures › scores the clean commute perfectly',
    'cleanCommute',
    'clean-commute',
  ),
  canned(
    'messy-commute',
    'The canned "one of everything" commute: speeding, harsh brake, phone, high-speed cruise. Default (sassy, mph) options.',
    'score.test.ts › end-to-end fixtures › scores the messy commute with one of everything',
    'messyCommute',
    'messy-commute',
  ),
  canned(
    'messy-commute-gentle',
    'Messy commute rendered with the gentle roast tone.',
    'roast.test.ts › fills every slot it uses (gentle)',
    'messyCommute',
    'slots-gentle',
    { intensity: 'gentle' },
  ),
  canned(
    'messy-commute-sassy',
    'Messy commute rendered with the sassy roast tone (explicit).',
    'roast.test.ts › fills every slot it uses (sassy)',
    'messyCommute',
    'slots-sassy',
    { intensity: 'sassy' },
  ),
  canned(
    'messy-commute-savage',
    'Messy commute rendered with the savage roast tone.',
    'roast.test.ts › fills every slot it uses (savage)',
    'messyCommute',
    'slots-savage',
    { intensity: 'savage' },
  ),
  canned(
    'messy-commute-kmh',
    'Messy commute with km/h feedback copy, savage tone.',
    'roast.test.ts › supports km/h output (applied to the messy commute)',
    'messyCommute',
    'metric-messy',
    { intensity: 'savage', units: 'kmh' },
  ),
  canned(
    'roast-seed-id-7',
    'Messy commute under a different trip id, so the FNV-1a seed picks different templates.',
    'roast.test.ts › is deterministic per trip id and varies across ids',
    'messyCommute',
    'id-7',
    { intensity: 'savage' },
  ),

  // --- speeding -------------------------------------------------------------------------
  synthetic(
    'speeding-clean',
    'Under the limit on two named roads. No events, score 100.',
    'speeding.test.ts › scores a clean trip at 100 with no events',
    {
      id: 'clean',
      legs: [
        { durationS: 300, speedMph: 28, limitMph: 30, name: 'Elm St' },
        { durationS: 600, speedMph: 63, limitMph: 65, name: 'I-40' },
      ],
    },
  ),
  synthetic(
    'speeding-moderate',
    '42 in a 30 on Route 9 for ~90 s: one moderate episode with time-saved maths.',
    'speeding.test.ts › detects a moderate episode with the right numbers',
    {
      id: 'moderate',
      legs: [
        { durationS: 120, speedMph: 30, limitMph: 30 },
        { durationS: 90, speedMph: 42, limitMph: 30, name: 'Route 9' },
        { durationS: 300, speedMph: 30, limitMph: 30 },
      ],
    },
  ),
  synthetic(
    'speeding-blip',
    'A 3 s burst over the limit is shorter than minDurationS and ignored.',
    'speeding.test.ts › ignores episodes shorter than 8 seconds',
    {
      id: 'blip',
      legs: [
        { durationS: 200, speedMph: 30, limitMph: 30 },
        { durationS: 3, speedMph: 40, limitMph: 30, rampAccel: 10 },
        { durationS: 200, speedMph: 30, limitMph: 30, rampAccel: 10 },
      ],
    },
  ),
  synthetic(
    'speeding-merge',
    'Two over-limit stretches separated by a 4 s dip merge into one episode.',
    'speeding.test.ts › merges episodes separated by a short dip',
    {
      id: 'merge',
      legs: [
        { durationS: 100, speedMph: 30, limitMph: 30 },
        { durationS: 40, speedMph: 42, limitMph: 30 },
        { durationS: 4, speedMph: 33, limitMph: 30, rampAccel: 4 },
        { durationS: 40, speedMph: 42, limitMph: 30, rampAccel: 4 },
        { durationS: 100, speedMph: 30, limitMph: 30 },
      ],
    },
  ),
  synthetic(
    'speeding-lowconf',
    'Speeding on a confidence-0.4 segment becomes an observation, never a penalty.',
    'speeding.test.ts › records speeding on low-confidence roads as observations, not penalties',
    {
      id: 'lowconf',
      legs: [
        { durationS: 200, speedMph: 30, limitMph: 30 },
        { durationS: 120, speedMph: 45, limitMph: 30, confidence: 0.4, name: 'Mystery Rd' },
        { durationS: 200, speedMph: 30, limitMph: 30 },
      ],
    },
  ),
  synthetic(
    'speeding-nolimit',
    'No limit anywhere: nothing is judged and limits_unknown is flagged.',
    'speeding.test.ts › does not judge roads with no limit at all',
    { id: 'nolimit', legs: [{ durationS: 600, speedMph: 55 }] },
  ),
  synthetic(
    'speeding-reckless',
    '58 in a 30 for 30 s: reckless severity, score capped at 25, XP 0.',
    'speeding.test.ts › flags reckless at 25+ over and zeroes XP',
    {
      id: 'reckless',
      legs: [
        { durationS: 200, speedMph: 30, limitMph: 30 },
        { durationS: 30, speedMph: 58, limitMph: 30, name: 'Elm St' },
        { durationS: 400, speedMph: 30, limitMph: 30 },
      ],
    },
  ),
  synthetic(
    'speeding-ton',
    '104 mph with no known limit: absolute reckless. The limit/over fields are NaN (serialised as "NaN").',
    'speeding.test.ts › flags 100+ mph as reckless even with an unknown limit',
    {
      id: 'ton',
      legs: [
        { durationS: 200, speedMph: 60 },
        { durationS: 15, speedMph: 104, rampAccel: 3 },
        { durationS: 200, speedMph: 60, rampAccel: 3 },
      ],
    },
  ),
  synthetic(
    'speeding-badgps',
    'Over the limit only while GPS accuracy is 120 m: samples above 50 m are ignored.',
    'speeding.test.ts › skips samples with bad GPS accuracy',
    {
      id: 'badgps',
      legs: [
        { durationS: 200, speedMph: 30, limitMph: 30 },
        { durationS: 60, speedMph: 45, limitMph: 30, accuracy: 120 },
        { durationS: 200, speedMph: 30, limitMph: 30 },
      ],
    },
  ),
  synthetic(
    'grace-exit-ramp',
    '65 → 25 limit drop while decelerating at 1.5 m/s²: grace period, no event, not reckless.',
    'speeding.test.ts › limit-drop grace › does not punish slowing down after the limit drops',
    {
      id: 'exit-ramp',
      legs: [
        { durationS: 300, speedMph: 63, limitMph: 65, name: 'I-40' },
        { durationS: 180, speedMph: 22, limitMph: 25, name: 'Maple Ave' },
      ],
    },
  ),
  synthetic(
    'grace-ignores-sign',
    'Keeps 63 mph for 40 s after the limit drops to 25: grace ends, reckless episode.',
    'speeding.test.ts › limit-drop grace › still catches a driver who keeps the speed after the limit drops',
    {
      id: 'ignores-sign',
      legs: [
        { durationS: 300, speedMph: 63, limitMph: 65, name: 'I-40' },
        { durationS: 40, speedMph: 63, limitMph: 25, name: 'Maple Ave' },
        { durationS: 180, speedMph: 22, limitMph: 25, name: 'Maple Ave' },
      ],
    },
  ),

  // --- smoothness -----------------------------------------------------------------------
  synthetic(
    'smooth-brake-moderate',
    'GPS-derived harsh brake at 4.2 m/s²: moderate.',
    'smoothness.test.ts › derives a harsh brake from a sudden speed drop',
    {
      id: 'brake',
      legs: [
        { durationS: 200, speedMph: 45, limitMph: 45 },
        { durationS: 6, speedMph: 5, limitMph: 45, rampAccel: 4.2 },
        { durationS: 200, speedMph: 45, limitMph: 45 },
      ],
    },
  ),
  synthetic(
    'smooth-brake-severe',
    'GPS-derived stop at 6 m/s²: severe.',
    'smoothness.test.ts › classifies a very hard stop as severe',
    {
      id: 'slam',
      legs: [
        { durationS: 200, speedMph: 45, limitMph: 45 },
        { durationS: 5, speedMph: 0, limitMph: 45, rampAccel: 6 },
        { durationS: 200, speedMph: 45, limitMph: 45 },
      ],
    },
  ),
  synthetic(
    'smooth-launch',
    'Harsh acceleration at 3.6 m/s²: smoothness event plus the efficiency aggression tax.',
    'smoothness.test.ts › derives harsh acceleration and taxes it in efficiency too',
    {
      id: 'launch',
      legs: [
        { durationS: 120, speedMph: 25, limitMph: 45 },
        { durationS: 60, speedMph: 45, limitMph: 45, rampAccel: 3.6 },
        { durationS: 300, speedMph: 45, limitMph: 45 },
      ],
    },
  ),
  synthetic(
    'smooth-corner',
    '22°/s heading change at 35 mph: severe hard corner from heading rate × speed.',
    'smoothness.test.ts › detects hard cornering from heading rate at speed',
    {
      id: 'corner',
      legs: [
        { durationS: 200, speedMph: 35, limitMph: 45 },
        { durationS: 4, speedMph: 35, limitMph: 45, turnRateDegS: 22 },
        { durationS: 200, speedMph: 35, limitMph: 45 },
      ],
    },
  ),
  synthetic(
    'smooth-short-brake',
    'One moderate brake on a ~2.4 km trip: normalised against the 3 km floor.',
    'smoothness.test.ts › normalises short trips so one brake is not catastrophic',
    {
      id: 'short-brake',
      legs: [
        { durationS: 90, speedMph: 30, limitMph: 30 },
        { durationS: 5, speedMph: 2, limitMph: 30, rampAccel: 4 },
        { durationS: 90, speedMph: 30, limitMph: 30 },
      ],
    },
  ),
  synthetic(
    'smooth-accelerometer',
    'Supplied motionEvents override GPS derivation: two brakes merge, a corner counts, a weak accel is ignored.',
    'smoothness.test.ts › prefers supplied accelerometer events over GPS derivation',
    { id: 'accelerometer', legs: [{ durationS: 600, speedMph: 40, limitMph: 45 }] },
    {},
    (input) => {
      const t0 = input.samples[0]!.t;
      return {
        ...input,
        motionEvents: [
          { t: t0 + 100_000, kind: 'brake', peak: 5.4 },
          { t: t0 + 101_000, kind: 'brake', peak: 4.1 },
          { t: t0 + 300_000, kind: 'corner', peak: 4.4 },
          { t: t0 + 400_000, kind: 'accel', peak: 2.0 },
        ],
      };
    },
  ),

  // --- attention ------------------------------------------------------------------------
  synthetic(
    'phone-stopped',
    'Phone events while stopped are ignored.',
    'attention.test.ts › ignores phone use while stopped or crawling',
    {
      id: 'stopped',
      legs: [
        { durationS: 200, speedMph: 30, limitMph: 30 },
        { durationS: 60, speedMph: 0, limitMph: 30 },
        { durationS: 200, speedMph: 30, limitMph: 30 },
      ],
      phoneEventsAt: [{ atS: 230 }, { atS: 240 }],
    },
  ),
  synthetic(
    'phone-taps',
    'Three taps within 20 s merge into a 25 s moderate episode; a lone tap is minor.',
    'attention.test.ts › merges taps within 20 s into one episode and grades by duration',
    {
      id: 'taps',
      legs: [{ durationS: 600, speedMph: 35, limitMph: 45 }],
      phoneEventsAt: [{ atS: 100 }, { atS: 110 }, { atS: 125 }, { atS: 400 }],
    },
  ),
  synthetic(
    'phone-highway',
    'A single unlock at 68 mph is major but too short to be reckless.',
    'attention.test.ts › treats any handling at highway speed as major',
    {
      id: 'highway-phone',
      legs: [{ durationS: 600, speedMph: 68, limitMph: 70 }],
      phoneEventsAt: [{ atS: 300, kind: 'unlock' }],
    },
  ),
  synthetic(
    'phone-highway-scroll',
    '75 s of phone handling at 68 mph: reckless_phone, score ≤ 25, XP 0.',
    'attention.test.ts › flags a long highway phone session as reckless',
    {
      id: 'highway-scroll',
      legs: [{ durationS: 600, speedMph: 68, limitMph: 70 }],
      phoneEventsAt: [{ atS: 200 }, { atS: 215 }, { atS: 230 }, { atS: 245 }, { atS: 262 }, { atS: 275 }],
    },
  ),
  synthetic(
    'phone-addict',
    'Twelve separate taps: attention penalty hits the 30-point cap.',
    'attention.test.ts › caps the attention penalty',
    {
      id: 'phone-addict',
      legs: [{ durationS: 900, speedMph: 35, limitMph: 45 }],
      phoneEventsAt: Array.from({ length: 12 }, (_, i) => ({ atS: 60 + i * 60 })),
    },
  ),

  // --- minimums / unscored ------------------------------------------------------------
  synthetic(
    'trip-too-short',
    'One minute at 20 mph is under 1 km and under 120 s moving: logged, not scored.',
    'score.test.ts › trip minimums › does not score trips under 1 km',
    { id: 'tiny', legs: [{ durationS: 60, speedMph: 20, limitMph: 25 }] },
  ),
  canned(
    'trip-passenger',
    'Clean commute marked as a passenger trip: not scored, passenger copy.',
    'score.test.ts › trip minimums › does not score passenger trips',
    'cleanCommute',
    'pax',
    {},
    withContext({ isPassenger: true }),
  ),

  // --- efficiency -----------------------------------------------------------------------
  synthetic(
    'efficiency-cruise',
    '79 mph under an 80 limit for 10 min: no speeding, one high_speed_cruise, efficiency 5–6.',
    'score.test.ts › efficiency › penalises sustained cruising above 75 mph even under the limit',
    { id: 'cruise', legs: [{ durationS: 600, speedMph: 79, limitMph: 80, roadClass: 'motorway' }] },
  ),
  synthetic(
    'efficiency-idle',
    'A 400 s mid-trip stop: idling event, light efficiency penalty.',
    'score.test.ts › efficiency › penalises long mid-trip idling lightly',
    {
      id: 'idle',
      legs: [
        { durationS: 200, speedMph: 30, limitMph: 30 },
        { durationS: 400, speedMph: 0, limitMph: 30 },
        { durationS: 200, speedMph: 30, limitMph: 30 },
      ],
    },
  ),

  // --- roast copy -----------------------------------------------------------------------
  synthetic(
    'roast-roadname',
    'Savage speeding roast must name Elm St and quote the numbers.',
    'roast.test.ts › puts the speed and the road in a speeding roast',
    {
      id: 'roadname',
      legs: [
        { durationS: 200, speedMph: 30, limitMph: 30 },
        { durationS: 120, speedMph: 42, limitMph: 30, name: 'Elm St' },
        { durationS: 200, speedMph: 30, limitMph: 30 },
      ],
    },
    { intensity: 'savage' },
  ),
  synthetic(
    'roast-metric',
    'Gentle tone with km/h units.',
    'roast.test.ts › supports km/h output',
    {
      id: 'metric',
      legs: [
        { durationS: 200, speedMph: 30, limitMph: 30 },
        { durationS: 120, speedMph: 42, limitMph: 30, name: 'Elm St' },
        { durationS: 200, speedMph: 30, limitMph: 30 },
      ],
    },
    { intensity: 'gentle', units: 'kmh' },
  ),
  synthetic(
    'roast-perfect',
    'A perfect 15-minute trip gets a praise headline mentioning miles.',
    'roast.test.ts › praises a perfect trip',
    { id: 'perfect', legs: [{ durationS: 900, speedMph: 40, limitMph: 45 }] },
    { intensity: 'sassy' },
  ),

  // --- context: XP multipliers, streaks, daily cap --------------------------------------
  canned(
    'context-night-rain-streak',
    'Clean commute at night in the rain on a 7-trip streak: ×1.1 × 1.1 context bonus plus the tier-1 streak bonus.',
    'docs/02-game-design.md §5 (XP context bonus + streak), computeXp',
    'cleanCommute',
    'night-rain-streak',
    {},
    withContext({ nightFraction: 0.8, weather: 'rain', cleanStreak: 7, dailyCreditedKmBefore: 10 }),
  ),
  canned(
    'context-daily-cap',
    'Clean commute after 100 km already credited today: distance factor floors at 0.4 → 40 XP.',
    'score.test.ts › XP › applies the daily distance cap (end-to-end)',
    'cleanCommute',
    'daily-cap',
    {},
    withContext({ dailyCreditedKmBefore: 100 }),
  ),
  canned(
    'context-streak-tier2',
    'Clean commute on a 25-trip streak in snow at 40 % night: +10 streak XP, weather bonus only (night < 0.5).',
    'score.test.ts › XP › adds streak bonuses for clean trips (end-to-end)',
    'cleanCommute',
    'streak-25',
    {},
    withContext({ cleanStreak: 25, weather: 'snow', nightFraction: 0.4 }),
  ),
  {
    name: 'context-reckless-night',
    description:
      'messyCommute("reckless-night") with its phone events replaced by a long highway phone session, at night in the rain on a 30-trip streak: reckless, so no context bonus can rescue XP (0).',
    mirrors: 'docs/02-game-design.md §4.5 (Reckless flag zeroes XP regardless of context)',
    // The phone events are replaced, not added, so the builder does not reproduce the input.
    source: { builder: 'manual' },
    options: {},
    input: (() => {
      const trip = messyCommute('reckless-night');
      const t0 = trip.samples[0]!.t;
      // Six taps 15 s apart while on the 78 mph I-40 leg (starts ~425 s in).
      const phoneEvents = [430, 445, 460, 475, 490, 505].map((s) => ({ t: t0 + s * 1000, kind: 'interaction' as const }));
      return { ...trip, phoneEvents, context: { nightFraction: 1, weather: 'rain', cleanStreak: 30 } };
    })(),
  },

  // --- edge cases -----------------------------------------------------------------------
  {
    name: 'edge-empty-trip',
    description: 'No samples at all: unscored (too_short) with an all-zero summary.',
    mirrors: 'prepare.ts / score.ts degenerate-input handling',
    source: { builder: 'manual' },
    options: {},
    input: { id: 'empty', samples: [], segments: [] },
  },
  {
    name: 'edge-unsorted-samples',
    description: 'Clean commute with the sample array reversed: prepare() sorts by time, so the result equals clean-commute under this id.',
    mirrors: 'prepare.ts (samples sorted by t)',
    source: { builder: 'manual' },
    options: {},
    input: (() => {
      const trip = cleanCommute('unsorted');
      return { ...trip, samples: [...trip.samples].reverse() };
    })(),
  },
];

// ---------------------------------------------------------------------------------------
// Expected output
// ---------------------------------------------------------------------------------------

interface EventLine {
  index: number;
  durationText: string;
  savedText?: string;
  roast: FeedbackLine | null;
}

interface FeedbackVariant {
  intensity: Intensity;
  units: 'mph' | 'kmh';
  headline: FeedbackLine;
  lines: FeedbackLine[];
}

interface TripFixture {
  kind: 'trip';
  name: string;
  description: string;
  mirrors: string;
  source: Source;
  options: ScoreOptions;
  input: TripInput;
  expected: TripScore & {
    /** formatDuration / formatSaved / roastEvent for every scored event, under `options`. */
    eventLines: EventLine[];
    /** Indices into `events` in sortBySeverity() order. */
    severityOrder: number[];
    /** buildFeedback for every intensity × units combination. */
    feedbackVariants: FeedbackVariant[];
  };
}

function expectedFor(input: TripInput, options: ScoreOptions): TripFixture['expected'] {
  const r = scoreTrip(input, options);
  const eventLines: EventLine[] = r.events.map((e, index) => ({
    index,
    durationText: formatDuration(e.durationS),
    savedText: e.detail.kind === 'speeding' ? formatSaved(e.detail.timeSavedS) : undefined,
    roast: roastEvent(e, r.tripId, index, options),
  }));
  const severityOrder = sortBySeverity(r.events).map((e) => r.events.indexOf(e));
  const feedbackVariants: FeedbackVariant[] = [];
  for (const intensity of INTENSITIES) {
    for (const units of UNITS) {
      const v = scoreTrip(input, { intensity, units });
      feedbackVariants.push({ intensity, units, headline: v.feedback.headline, lines: v.feedback.lines });
    }
  }
  return { ...r, eventLines, severityOrder, feedbackVariants };
}

// ---------------------------------------------------------------------------------------
// Vector fixtures (pure functions)
// ---------------------------------------------------------------------------------------

const HASH_SEEDS = [
  '',
  'a',
  'messy-commute',
  'messy-commute:speeding.major:0',
  'messy-commute:harsh_brake.severe:1',
  'messy-commute:phone_handling.moderate:2',
  'clean-commute:pf',
  'clean-commute:sm',
  'clean-commute:lr',
  'id-0',
  'id-11',
  'The quick brown fox jumps over the lazy dog',
  'héllo wörld',
  'naïve café ☕',
  '🚗💨',
  '日本語のトリップ',
];

const FORMAT_DURATION_INPUTS = [
  0, 0.4, 0.5, 1, 1.5, 2.5, 8, 44.5, 45, 59.4, 59.5, 60, 65, 69.5, 70, 89.5, 90, 95, 109.49, 109.5, 119.4, 119.5, 120,
  149.5, 150, 150.5, 180, 190, 300, 299.5, 3600, -0.5, -3.7,
];
const FORMAT_SAVED_INPUTS = [-5, -0.4, 0, 0.3, 0.5, 1, 38, 59.5, 60, 89.5, 90, 130, 150, 3599.5];

interface XpVector {
  score: number;
  distanceM: number;
  context?: TripContext;
  reckless: boolean;
  expected: number;
}

const XP_ARGS: Array<Omit<XpVector, 'expected'>> = [
  { score: 100, distanceM: 15_000, reckless: false },
  { score: 49, distanceM: 15_000, reckless: false },
  { score: 50, distanceM: 15_000, reckless: false },
  { score: 100, distanceM: 15_000, reckless: true },
  { score: 100, distanceM: 3_000, reckless: false },
  { score: 100, distanceM: 300, reckless: false },
  { score: 100, distanceM: 0, reckless: false },
  { score: 70, distanceM: 15_000, reckless: false },
  { score: 85, distanceM: 15_000, reckless: false },
  { score: 100, distanceM: 30_000, context: { dailyCreditedKmBefore: 100 }, reckless: false },
  { score: 100, distanceM: 30_000, context: { dailyCreditedKmBefore: 95 }, reckless: false },
  { score: 100, distanceM: 30_000, context: { dailyCreditedKmBefore: 120 }, reckless: false },
  { score: 90, distanceM: 20_000, context: { nightFraction: 1 }, reckless: false },
  { score: 90, distanceM: 20_000, context: { nightFraction: 0.49 }, reckless: false },
  { score: 90, distanceM: 20_000, context: { nightFraction: 0.5 }, reckless: false },
  { score: 90, distanceM: 20_000, context: { nightFraction: 1, weather: 'rain' }, reckless: false },
  { score: 90, distanceM: 20_000, context: { weather: 'snow' }, reckless: false },
  { score: 90, distanceM: 20_000, context: { weather: 'clear' }, reckless: false },
  { score: 84, distanceM: 20_000, context: { nightFraction: 1, weather: 'rain' }, reckless: false },
  { score: 70, distanceM: 20_000, context: { nightFraction: 1, weather: 'rain' }, reckless: false },
  { score: 100, distanceM: 20_000, context: { cleanStreak: 4 }, reckless: false },
  { score: 100, distanceM: 20_000, context: { cleanStreak: 5 }, reckless: false },
  { score: 100, distanceM: 20_000, context: { cleanStreak: 19 }, reckless: false },
  { score: 100, distanceM: 20_000, context: { cleanStreak: 20 }, reckless: false },
  { score: 100, distanceM: 20_000, context: { cleanStreak: 25 }, reckless: false },
  { score: 80, distanceM: 20_000, context: { cleanStreak: 25 }, reckless: false },
  { score: 79, distanceM: 20_000, context: { cleanStreak: 25 }, reckless: false },
  { score: 70, distanceM: 20_000, context: { cleanStreak: 25 }, reckless: false },
  { score: 95, distanceM: 7_500, context: { nightFraction: 0.9, weather: 'snow', cleanStreak: 21, dailyCreditedKmBefore: 97 }, reckless: false },
  { score: 25, distanceM: 20_000, context: { cleanStreak: 25 }, reckless: true },
];

// ---------------------------------------------------------------------------------------
// Serialisation
// ---------------------------------------------------------------------------------------

/** JSON.stringify replacer: NaN / ±Infinity become strings so they survive the round trip. */
function replacer(_key: string, value: unknown): unknown {
  if (typeof value === 'number' && !Number.isFinite(value)) {
    if (Number.isNaN(value)) return 'NaN';
    return value > 0 ? 'Infinity' : '-Infinity';
  }
  return value;
}

function writeJson(name: string, data: unknown): void {
  writeFileSync(join(outDir, name), JSON.stringify(data, replacer, 2) + '\n', 'utf8');
}

function readme(cases: TripCase[]): string {
  const rows = cases
    .map((c) => `| \`${c.name}.json\` | ${c.description.replace(/\|/g, '\\|')} | ${c.mirrors.replace(/\|/g, '\\|')} |`)
    .join('\n');
  return `# Scoring fixtures

**Generated. Do not edit by hand.** Regenerate with \`npm run fixtures\` from the repo root
(\`packages/scoring/scripts/export-fixtures.ts\`).

\`@drivalry/scoring\` (TypeScript) is the specification of the Drivalry scoring engine. These
files are its contract: every port must reproduce them. Today the consumer is
\`packages/drivalry_scoring\` (Dart), whose \`test/fixtures_test.dart\` loads every \`*.json\` in
this directory.

## Conventions

- All quantities are SI (metres, seconds, m/s, m/s²); timestamps are epoch milliseconds.
- JSON cannot carry \`NaN\` or \`±Infinity\`. They are written as the strings \`"NaN"\`,
  \`"Infinity"\` and \`"-Infinity"\`. A port must compare them as the corresponding doubles.
- Properties that were \`undefined\` in TypeScript are **omitted** (that is what
  \`JSON.stringify\` does). Treat a missing key and \`null\` as the same thing.
- Comparison rule used by the Dart suite: exact for integers, strings, enums and booleans;
  absolute tolerance 1e-6 for doubles.

Every file has a top-level \`"kind"\`: \`"trip"\`, \`"hash"\`, \`"format"\`, \`"computeXp"\` or \`"templates"\`.

## \`kind: "trip"\` (one file per case)

| Field | Meaning |
| --- | --- |
| \`name\`, \`description\`, \`mirrors\` | Case identity, what it demonstrates, which TS test or doc section it mirrors. |
| \`source\` | How \`input\` was built. \`{ builder: "buildSyntheticTrip", spec }\`, \`{ builder: "cleanCommute" \\| "messyCommute", id }\` or \`{ builder: "manual" }\`. When a builder is named, calling the same builder in a port must reproduce \`input.samples\`, \`input.segments\` and \`input.phoneEvents\` (\`context\` and \`motionEvents\` may have been added afterwards). |
| \`options\` | The \`ScoreOptions\` passed to \`scoreTrip\` (\`intensity\`: gentle \\| sassy \\| savage, default sassy; \`units\`: mph \\| kmh, default mph). |
| \`input\` | The complete \`TripInput\`: \`id\`, \`samples[]\` (\`t, lat, lon, speed, accuracy, heading?, altitude?\`), \`segments[]\` (\`fromIdx, toIdx, speedLimit\` m/s or null, \`confidence\` 0–1, \`roadClass\`, \`name?\`, \`wayId?\`), \`phoneEvents?[]\` (\`t, kind\`), \`motionEvents?[]\` (\`t, kind, peak\`), \`context?\` (\`nightFraction?, weather?, vehicleId?, isPassenger?, dailyCreditedKmBefore?, cleanStreak?\`). |
| \`expected\` | The complete \`TripScore\` returned by \`scoreTrip(input, options)\`: \`tripId, scored, unscoredReason?, score, penalties{speed,smoothness,attention,efficiency}, flags[], reckless, xp, events[], observations[], summary{...}, feedback{headline, lines[]}\`. Each event: \`kind, severity, startT, endT, durationS, startIdx, endIdx, lat, lon, detail\` where \`detail.kind\` selects the shape (speeding: \`limit, maxSpeed, avgOver, maxOver, roadName?, roadClass, timeSavedS\`; harsh_brake/harsh_accel/hard_corner: \`peak, speedAtStart\`; phone_handling: \`interactions, maxSpeed, kinds[]\`; idling: \`excessS\`; high_speed_cruise: \`maxSpeed\`). Each feedback line: \`tone\` (roast \\| praise), \`text\`, \`eventIndex?\`. |
| \`expected.eventLines[]\` | For every scored event \`i\`: \`formatDuration(events[i].durationS)\`, \`formatSaved(detail.timeSavedS)\` (speeding only) and \`roastEvent(events[i], tripId, i, options)\`. |
| \`expected.severityOrder[]\` | Indices into \`expected.events\` in \`sortBySeverity()\` order (worst first, then by start time). |
| \`expected.feedbackVariants[]\` | \`buildFeedback\` output (\`headline\`, \`lines\`) for every \`intensity\` × \`units\` combination, independent of \`options\`. Pins the FNV-1a template selection and every slot formatter. |

## \`kind: "hash"\` — \`vectors-hash.json\`

\`vectors[]\` of \`{ seed, hash }\`: FNV-1a 32-bit over the UTF-16 code units of \`seed\`
(\`String.prototype.charCodeAt\`), unsigned result. Template choice is \`hash(seed) % list.length\`.

## \`kind: "format"\` — \`vectors-format.json\`

\`formatDuration[]\` and \`formatSaved[]\` of \`{ input, expected }\` (seconds in, display string out).
Inputs include .5 ties and negatives to pin JavaScript \`Math.round\` semantics (ties round toward +∞).

## \`kind: "computeXp"\` — \`vectors-xp.json\`

\`vectors[]\` of \`{ score, distanceM, context?, reckless, expected }\` for \`computeXp\`.

## \`kind: "templates"\` — \`vectors-templates.json\`

\`templates\`: the complete \`TEMPLATES\` library (\`templateKey → intensity → string[]\`). A port must
carry exactly these strings in exactly this order, because selection is by index.

## Cases

| File | What it shows | Mirrors |
| --- | --- | --- |
${rows}
`;
}

// ---------------------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------------------

function main(): void {
  mkdirSync(outDir, { recursive: true });
  for (const f of readdirSync(outDir)) {
    if (f.endsWith('.json') || f === 'README.md') rmSync(join(outDir, f));
  }

  const names = new Set<string>();
  for (const c of CASES) {
    if (names.has(c.name)) throw new Error(`duplicate fixture name ${c.name}`);
    names.add(c.name);
    const fixture: TripFixture = {
      kind: 'trip',
      name: c.name,
      description: c.description,
      mirrors: c.mirrors,
      source: c.source,
      options: c.options,
      input: c.input,
      expected: expectedFor(c.input, c.options),
    };
    writeJson(`${c.name}.json`, fixture);
  }

  writeJson('vectors-hash.json', {
    kind: 'hash',
    description: 'FNV-1a 32-bit over UTF-16 code units; the template selection seed.',
    vectors: HASH_SEEDS.map((seed) => ({ seed, hash: hash(seed) })),
  });

  writeJson('vectors-format.json', {
    kind: 'format',
    description: 'formatDuration / formatSaved display strings, including rounding ties and negatives.',
    formatDuration: FORMAT_DURATION_INPUTS.map((input) => ({ input, expected: formatDuration(input) })),
    formatSaved: FORMAT_SAVED_INPUTS.map((input) => ({ input, expected: formatSaved(input) })),
  });

  writeJson('vectors-xp.json', {
    kind: 'computeXp',
    description: 'computeXp(score, distanceM, context, reckless) vectors.',
    vectors: XP_ARGS.map(
      (a): XpVector => ({ ...a, expected: computeXp(a.score, a.distanceM, a.context, a.reckless) }),
    ),
  });

  writeJson('vectors-templates.json', {
    kind: 'templates',
    description: 'The complete roast/praise template library, keyed by template key then intensity.',
    templates: TEMPLATES,
  });

  writeFileSync(join(outDir, 'README.md'), readme(CASES), 'utf8');

  // eslint-disable-next-line no-console
  console.log(`wrote ${CASES.length} trip fixtures + 4 vector files to ${outDir}`);
}

main();

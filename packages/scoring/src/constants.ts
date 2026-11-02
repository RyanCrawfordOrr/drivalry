/** Unit helpers. */
export const MPH = 0.44704; // 1 mph in m/s
export const KMH = 1 / 3.6; // 1 km/h in m/s

export const mphToMps = (mph: number): number => mph * MPH;
export const mpsToMph = (mps: number): number => mps / MPH;
export const mpsToKmh = (mps: number): number => mps / KMH;

/** Below this the car is considered stopped. */
export const MOVING_SPEED = 1.0; // m/s

/** Samples with worse horizontal accuracy are excluded from speeding detection. */
export const GPS_MAX_ACCURACY = 50; // m

/** Segments below this confidence can produce observations, never penalties. */
export const SPEEDING_MIN_CONFIDENCE = 0.7;

export const SPEEDING = {
  /** An episode must exceed the limit by at least this much. */
  minOver: mphToMps(5),
  /** Episodes shorter than this are ignored. */
  minDurationS: 8,
  /** Episodes separated by less than this gap are merged. */
  mergeGapS: 10,
  /** Per-episode duration cap for penalty purposes. */
  maxPenalisedDurationS: 300,
  thresholds: {
    moderate: mphToMps(10),
    major: mphToMps(15),
    reckless: mphToMps(25),
  },
  /** Any speed at or above this is reckless regardless of the limit. */
  recklessAbsolute: mphToMps(100),
  recklessAbsoluteMinDurationS: 3,
  /**
   * After the posted limit drops, the car gets this long to slow down before over-limit
   * samples count, provided it is actually decelerating (65 → 25 at 1.5 m/s² takes ~12 s).
   */
  limitDropGraceS: 15,
  /** First seconds after a drop are exempt unconditionally (reaction time). */
  graceFreeS: 3,
  /** Minimum per-second speed drop to count as "decelerating" during grace. */
  graceMinDecel: 0.15,
  /** Penalty weights per minute by severity. */
  weightPerMinute: { minor: 1.0, moderate: 2.5, major: 6.0, reckless: 12.0 },
  /** Proportion term: 15 × (seconds over / moving seconds). */
  proportionWeight: 15,
  cap: 40,
} as const;

export const SMOOTHNESS = {
  brake: { moderate: 3.5, severe: 5.0 },
  accel: { moderate: 3.0, severe: 4.5 },
  corner: { moderate: 4.0, severe: 6.0 },
  /** Minimum sustained duration when deriving from GPS. */
  minSustainedS: 0.7,
  mergeGapS: 3,
  /** Cornering is only evaluated above this speed (GPS heading is noise below it). */
  cornerMinSpeed: 5.0,
  weights: {
    harsh_brake: { moderate: 2.0, severe: 4.0 },
    harsh_accel: { moderate: 1.5, severe: 3.0 },
    hard_corner: { moderate: 1.5, severe: 3.0 },
  },
  /** Penalties are normalised to this distance. */
  normaliseDistanceM: 10_000,
  /** Trips shorter than this are normalised as if this long. */
  minNormaliseDistanceM: 3_000,
  cap: 30,
} as const;

export const ATTENTION = {
  /** Phone events only count above this speed. */
  minSpeed: 5.0, // m/s ≈ 11 mph
  mergeGapS: 20,
  /** A single tap still "costs" this many seconds of attention. */
  minEpisodeS: 3,
  thresholds: { moderateS: 10, majorS: 45 },
  /** Any handling at or above this speed is Major. */
  majorSpeed: mphToMps(60),
  weights: { minor: 3, moderate: 7, major: 12 },
  /** Reckless: Major episode at highway speed lasting this long. */
  recklessDurationS: 60,
  cap: 30,
} as const;

export const EFFICIENCY = {
  idle: { freeS: 120, weightPerMinute: 0.5, cap: 4 },
  cruise: { speed: mphToMps(75), weightPerMinute: 1.0, cap: 6, minEventS: 10 },
  aggression: { perHarshAccel: 0.5, cap: 5 },
  cap: 15,
} as const;

export const RECKLESS = {
  scoreCap: 25,
  /** "Driving like you're being chased": this many severe motion events plus a major speeding episode. */
  patternSevereEvents: 3,
} as const;

export const MINIMUMS = {
  distanceM: 1_000,
  movingTimeS: 120,
} as const;

export const XP = {
  minScore: 50,
  minXp: 10,
  maxXp: 100,
  distanceFloor: 0.4,
  fullCreditKm: 15,
  dailyCapKm: 100,
  nightBonus: 1.1,
  weatherBonus: 1.1,
  maxContextBonus: 1.2,
  bonusMinScore: 85,
  streak: { tier1: 5, tier1Xp: 5, tier2: 20, tier2Xp: 10 },
  /** A trip keeps a clean streak alive when it scores at least this. */
  cleanTripScore: 80,
} as const;

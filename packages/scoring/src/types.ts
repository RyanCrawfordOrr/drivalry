/**
 * Drivalry scoring engine — shared types.
 *
 * All quantities are SI: metres, seconds, m/s, m/s². The UI converts.
 * See docs/02-game-design.md for the rules these types encode.
 */

/** One GPS fix. `t` is epoch milliseconds. */
export interface GpsSample {
  t: number;
  lat: number;
  lon: number;
  /** Ground speed in m/s as reported by the OS (already Doppler-smoothed on most devices). */
  speed: number;
  /** Horizontal accuracy radius in metres. Samples above 50 m are ignored for speeding. */
  accuracy: number;
  /** Course over ground in degrees, 0 = north, clockwise. Optional; derived from positions when absent. */
  heading?: number;
  altitude?: number;
}

export type RoadClass =
  | 'motorway'
  | 'trunk'
  | 'primary'
  | 'secondary'
  | 'tertiary'
  | 'residential'
  | 'service'
  | 'unclassified'
  | 'unknown';

/**
 * A map-matched stretch of road covering samples [fromIdx, toIdx] inclusive.
 * Produced on the phone by the pack matcher (plus shared corrections). Segments must not overlap.
 */
export interface RoadSegment {
  fromIdx: number;
  toIdx: number;
  /** Posted limit in m/s, or null when unknown. */
  speedLimit: number | null;
  /** 0–1. Below SPEEDING_MIN_CONFIDENCE the segment can produce observations but never penalties. */
  confidence: number;
  roadClass: RoadClass;
  name?: string;
  /** OSM way id, used for the "limit is wrong here" correction loop. */
  wayId?: string;
}

export type PhoneEventKind = 'unlock' | 'interaction' | 'call_handheld';

export interface PhoneEvent {
  t: number;
  kind: PhoneEventKind;
}

export type MotionEventKind = 'brake' | 'accel' | 'corner';

/** Optional pre-detected motion events from the accelerometer pipeline. Peak is m/s². */
export interface MotionEvent {
  t: number;
  kind: MotionEventKind;
  peak: number;
}

export type Weather = 'clear' | 'rain' | 'snow';

export interface TripContext {
  /** Fraction of the trip (by time) after civil dusk / before civil dawn. 0–1. */
  nightFraction?: number;
  weather?: Weather;
  vehicleId?: string;
  /** Marked as passenger by the user or by heuristics. Passenger trips are not scored. */
  isPassenger?: boolean;
  /** Kilometres already credited toward XP today, before this trip. Enforces the daily cap. */
  dailyCreditedKmBefore?: number;
  /** Current clean-trip streak length before this trip. */
  cleanStreak?: number;
}

export interface TripInput {
  id: string;
  samples: GpsSample[];
  segments: RoadSegment[];
  phoneEvents?: PhoneEvent[];
  motionEvents?: MotionEvent[];
  context?: TripContext;
}

export type EventKind =
  | 'speeding'
  | 'harsh_brake'
  | 'harsh_accel'
  | 'hard_corner'
  | 'phone_handling'
  | 'idling'
  | 'high_speed_cruise';

/**
 * Severity ladder. Each event kind uses a subset:
 *  speeding:       minor | moderate | major | reckless
 *  brake/accel/corner: moderate | severe
 *  phone_handling: minor | moderate | major
 *  idling, high_speed_cruise: minor (informational)
 */
export type Severity = 'minor' | 'moderate' | 'major' | 'severe' | 'reckless';

export interface SpeedingDetail {
  /** Posted limit, m/s. */
  limit: number;
  /** Peak (median-filtered) speed in the episode, m/s. */
  maxSpeed: number;
  /** Mean amount over the limit during the episode, m/s. */
  avgOver: number;
  /** Peak amount over the limit, m/s. */
  maxOver: number;
  roadName?: string;
  roadClass: RoadClass;
  /** Estimated seconds the driver saved vs driving at the limit over this episode. */
  timeSavedS: number;
}

export interface MotionDetail {
  /** Peak longitudinal or lateral acceleration, m/s². */
  peak: number;
  /** Speed at the start of the event, m/s. */
  speedAtStart: number;
}

export interface PhoneDetail {
  /** Number of raw OS events merged into this episode. */
  interactions: number;
  /** Peak speed during the episode, m/s. */
  maxSpeed: number;
  kinds: PhoneEventKind[];
}

export interface IdleDetail {
  /** Seconds beyond the free threshold. */
  excessS: number;
}

export interface CruiseDetail {
  maxSpeed: number;
}

export type EventDetail =
  | ({ kind: 'speeding' } & SpeedingDetail)
  | ({ kind: 'harsh_brake' | 'harsh_accel' | 'hard_corner' } & MotionDetail)
  | ({ kind: 'phone_handling' } & PhoneDetail)
  | ({ kind: 'idling' } & IdleDetail)
  | ({ kind: 'high_speed_cruise' } & CruiseDetail);

export interface TripEvent {
  kind: EventKind;
  severity: Severity;
  /** Epoch ms. */
  startT: number;
  endT: number;
  durationS: number;
  /** Sample indices, inclusive. */
  startIdx: number;
  endIdx: number;
  /** Where to pin it on the map (sample at startIdx). */
  lat: number;
  lon: number;
  detail: EventDetail;
}

export type Flag =
  | 'reckless_speed'
  | 'reckless_phone'
  | 'reckless_pattern'
  | 'low_gps_quality'
  | 'limits_unknown';

export interface TripSummary {
  distanceM: number;
  /** Seconds with speed > MOVING_SPEED. */
  movingTimeS: number;
  totalTimeS: number;
  maxSpeed: number;
  /** Distance / moving time. */
  avgMovingSpeed: number;
  /** Seconds over the limit on confident segments. */
  secondsOverLimit: number;
  /** Seconds driven on segments with a confident limit (denominator for coverage). */
  secondsWithKnownLimit: number;
  /** Total seconds saved by all speeding in this trip. The roast material. */
  timeSavedBySpeedingS: number;
  startT: number;
  endT: number;
  nightFraction: number;
  /** Fraction of samples with accuracy <= GPS_MAX_ACCURACY. */
  gpsQuality: number;
}

export interface ComponentPenalties {
  speed: number;
  smoothness: number;
  attention: number;
  efficiency: number;
}

export type Intensity = 'gentle' | 'sassy' | 'savage';

export interface FeedbackLine {
  /** 'roast' lines are negative; 'praise' positive. */
  tone: 'roast' | 'praise';
  text: string;
  /** Which event this line is about, if any (index into events). */
  eventIndex?: number;
}

export interface TripScore {
  tripId: string;
  /** False when the trip was too short or a passenger trip. */
  scored: boolean;
  unscoredReason?: 'too_short' | 'passenger';
  /** 0–100. 0 when unscored. */
  score: number;
  penalties: ComponentPenalties;
  flags: Flag[];
  reckless: boolean;
  xp: number;
  /** Events that counted toward the score. */
  events: TripEvent[];
  /** Speeding seen on low-confidence segments: shown, never scored. */
  observations: TripEvent[];
  summary: TripSummary;
  feedback: {
    headline: FeedbackLine;
    lines: FeedbackLine[];
  };
}

export interface ScoreOptions {
  intensity?: Intensity;
  /** Display units for feedback copy. Default 'mph'. */
  units?: 'mph' | 'kmh';
}

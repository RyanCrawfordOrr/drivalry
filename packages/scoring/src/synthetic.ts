/**
 * Synthetic trip builder. Used by tests and by the mobile app's mock tracking provider.
 * Produces 1 Hz GPS samples along a bearing with gentle ramps between legs unless told otherwise.
 */
import { mphToMps } from './constants';
import { destination } from './geo';
import type { GpsSample, PhoneEvent, PhoneEventKind, RoadClass, RoadSegment, TripContext, TripInput } from './types';

export interface LegSpec {
  durationS: number;
  speedMph: number;
  /** Posted limit in mph. Omit or null for "unknown". */
  limitMph?: number | null;
  /** Segment confidence. Defaults to 0.9 when a limit is given, 0 otherwise. */
  confidence?: number;
  roadClass?: RoadClass;
  name?: string;
  /** Max |accel| used to reach this leg's speed from the previous one. Default 1.5 m/s² (gentle). */
  rampAccel?: number;
  /** Degrees per second of heading change applied throughout the leg (for cornering tests). */
  turnRateDegS?: number;
  /** Override GPS accuracy for this leg (metres). */
  accuracy?: number;
}

export interface SyntheticSpec {
  id?: string;
  startT?: number;
  start?: { lat: number; lon: number };
  headingDeg?: number;
  legs: LegSpec[];
  /** Phone events at offsets (seconds from trip start). */
  phoneEventsAt?: Array<{ atS: number; kind?: PhoneEventKind }>;
  accuracy?: number;
  context?: TripContext;
}

export function buildSyntheticTrip(spec: SyntheticSpec): TripInput {
  const startT = spec.startT ?? Date.UTC(2026, 10, 1, 17, 30, 0);
  let lat = spec.start?.lat ?? 36.1627;
  let lon = spec.start?.lon ?? -86.7816;
  let heading = spec.headingDeg ?? 90;
  let v = 0;
  let t = startT;
  let idx = 0;

  const samples: GpsSample[] = [];
  const segments: RoadSegment[] = [];

  const push = (accuracy: number) => {
    samples.push({ t, lat, lon, speed: v, accuracy, heading });
    idx++;
  };

  push(spec.accuracy ?? 5);

  for (const leg of spec.legs) {
    const target = mphToMps(leg.speedMph);
    const ramp = leg.rampAccel ?? 1.5;
    const from = idx;
    for (let s = 0; s < leg.durationS; s++) {
      const dv = Math.max(-ramp, Math.min(ramp, target - v));
      v = Math.max(0, v + dv);
      if (leg.turnRateDegS) heading = (heading + leg.turnRateDegS + 360) % 360;
      const next = destination(lat, lon, heading, v);
      lat = next.lat;
      lon = next.lon;
      t += 1000;
      push(leg.accuracy ?? spec.accuracy ?? 5);
    }
    const to = idx - 1;
    const hasLimit = typeof leg.limitMph === 'number';
    segments.push({
      fromIdx: from,
      toIdx: to,
      speedLimit: hasLimit ? mphToMps(leg.limitMph as number) : null,
      confidence: leg.confidence ?? (hasLimit ? 0.9 : 0),
      roadClass: leg.roadClass ?? (hasLimit && (leg.limitMph as number) >= 55 ? 'motorway' : 'residential'),
      name: leg.name,
    });
  }

  const phoneEvents: PhoneEvent[] | undefined = spec.phoneEventsAt?.map((p) => ({
    t: startT + p.atS * 1000,
    kind: p.kind ?? 'interaction',
  }));

  return {
    id: spec.id ?? `synthetic-${startT}`,
    samples,
    segments,
    phoneEvents,
    context: spec.context,
  };
}

/** A clean 20-minute mixed trip. Handy default for mocks. */
export function cleanCommute(id = 'clean-commute'): TripInput {
  return buildSyntheticTrip({
    id,
    legs: [
      { durationS: 180, speedMph: 28, limitMph: 30, name: 'Elm St', roadClass: 'residential' },
      { durationS: 420, speedMph: 42, limitMph: 45, name: 'Route 9', roadClass: 'primary' },
      { durationS: 480, speedMph: 63, limitMph: 65, name: 'I-40', roadClass: 'motorway' },
      { durationS: 120, speedMph: 22, limitMph: 25, name: 'Maple Ave', roadClass: 'residential' },
    ],
  });
}

/** A trip with one of everything. Handy for UI mocks. */
export function messyCommute(id = 'messy-commute'): TripInput {
  return buildSyntheticTrip({
    id,
    legs: [
      { durationS: 120, speedMph: 38, limitMph: 25, name: 'Elm St', roadClass: 'residential' },
      { durationS: 300, speedMph: 44, limitMph: 45, name: 'Route 9', roadClass: 'primary' },
      { durationS: 5, speedMph: 10, limitMph: 45, name: 'Route 9', roadClass: 'primary', rampAccel: 5.5 },
      { durationS: 240, speedMph: 78, limitMph: 65, name: 'I-40', roadClass: 'motorway' },
      { durationS: 300, speedMph: 64, limitMph: 65, name: 'I-40', roadClass: 'motorway' },
      { durationS: 120, speedMph: 24, limitMph: 25, name: 'Maple Ave', roadClass: 'residential' },
    ],
    phoneEventsAt: [{ atS: 500 }, { atS: 512 }, { atS: 530 }],
  });
}

import { EFFICIENCY, MOVING_SPEED } from '../constants';
import { durationS, runs, type PreparedTrip } from '../prepare';
import type { TripEvent } from '../types';

/** Mid-trip stops longer than the free threshold. Trip start/end are already trimmed. */
export function detectIdling(p: PreparedTrip): TripEvent[] {
  const { samples, speed, firstMoving, lastMoving } = p;
  const out: TripEvent[] = [];
  for (const [a, b] of runs(firstMoving, lastMoving, samples, (i) => speed[i]! < 0.5 || speed[i]! <= MOVING_SPEED * 0.5, 5)) {
    const dur = durationS(samples, a, b);
    if (dur <= EFFICIENCY.idle.freeS) continue;
    const s = samples[a]!;
    out.push({
      kind: 'idling',
      severity: 'minor',
      startT: s.t,
      endT: samples[b]!.t,
      durationS: dur,
      startIdx: a,
      endIdx: b,
      lat: s.lat,
      lon: s.lon,
      detail: { kind: 'idling', excessS: dur - EFFICIENCY.idle.freeS },
    });
  }
  return out;
}

/** Sustained driving at or above the fuel-cliff speed, regardless of the limit. */
export function detectHighSpeedCruise(p: PreparedTrip): TripEvent[] {
  const { samples, speed, goodFix, firstMoving, lastMoving } = p;
  const out: TripEvent[] = [];
  for (const [a, b] of runs(firstMoving, lastMoving, samples, (i) => goodFix[i]! && speed[i]! >= EFFICIENCY.cruise.speed, 10)) {
    const dur = durationS(samples, a, b);
    if (dur < EFFICIENCY.cruise.minEventS) continue;
    let maxSpeed = 0;
    for (let i = a; i <= b; i++) maxSpeed = Math.max(maxSpeed, speed[i]!);
    const s = samples[a]!;
    out.push({
      kind: 'high_speed_cruise',
      severity: 'minor',
      startT: s.t,
      endT: samples[b]!.t,
      durationS: dur,
      startIdx: a,
      endIdx: b,
      lat: s.lat,
      lon: s.lon,
      detail: { kind: 'high_speed_cruise', maxSpeed },
    });
  }
  return out;
}

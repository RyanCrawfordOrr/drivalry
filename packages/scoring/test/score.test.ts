import { buildSyntheticTrip, cleanCommute, computeXp, messyCommute, scoreTrip } from '../src';

describe('trip minimums', () => {
  it('does not score trips under 1 km', () => {
    const trip = buildSyntheticTrip({ id: 'tiny', legs: [{ durationS: 60, speedMph: 20, limitMph: 25 }] });
    const r = scoreTrip(trip);
    expect(r.scored).toBe(false);
    expect(r.unscoredReason).toBe('too_short');
    expect(r.score).toBe(0);
    expect(r.xp).toBe(0);
    expect(r.feedback.headline.text).toMatch(/short|scored/i);
  });

  it('does not score passenger trips', () => {
    const trip = cleanCommute('pax');
    trip.context = { isPassenger: true };
    const r = scoreTrip(trip);
    expect(r.scored).toBe(false);
    expect(r.unscoredReason).toBe('passenger');
  });
});

describe('efficiency', () => {
  it('penalises sustained cruising above 75 mph even under the limit', () => {
    const trip = buildSyntheticTrip({
      id: 'cruise',
      legs: [{ durationS: 600, speedMph: 79, limitMph: 80, roadClass: 'motorway' }],
    });
    const r = scoreTrip(trip);
    expect(r.events.filter((e) => e.kind === 'speeding')).toHaveLength(0);
    expect(r.events.filter((e) => e.kind === 'high_speed_cruise')).toHaveLength(1);
    expect(r.penalties.efficiency).toBeGreaterThan(5);
    expect(r.penalties.efficiency).toBeLessThanOrEqual(6);
  });

  it('penalises long mid-trip idling lightly', () => {
    const trip = buildSyntheticTrip({
      id: 'idle',
      legs: [
        { durationS: 200, speedMph: 30, limitMph: 30 },
        { durationS: 400, speedMph: 0, limitMph: 30 },
        { durationS: 200, speedMph: 30, limitMph: 30 },
      ],
    });
    const r = scoreTrip(trip);
    const idle = r.events.find((e) => e.kind === 'idling');
    expect(idle).toBeDefined();
    expect(r.penalties.efficiency).toBeGreaterThan(1.5);
    expect(r.penalties.efficiency).toBeLessThanOrEqual(4);
  });
});

describe('XP', () => {
  it('gives 100 XP for a perfect 15 km trip and 0 below a score of 50', () => {
    expect(computeXp(100, 15_000, undefined, false)).toBe(100);
    expect(computeXp(49, 15_000, undefined, false)).toBe(0);
    expect(computeXp(100, 15_000, undefined, true)).toBe(0);
  });

  it('scales short trips down but never below the floor', () => {
    expect(computeXp(100, 3_000, undefined, false)).toBe(52);
    expect(computeXp(100, 300, undefined, false)).toBe(41);
  });

  it('applies the daily distance cap', () => {
    expect(computeXp(100, 30_000, { dailyCreditedKmBefore: 100 }, false)).toBe(40);
    expect(computeXp(100, 30_000, { dailyCreditedKmBefore: 95 }, false)).toBe(60);
  });

  it('adds context bonuses only for strong scores', () => {
    expect(computeXp(90, 20_000, { nightFraction: 1 }, false)).toBe(Math.round(82 * 1.1));
    expect(computeXp(90, 20_000, { nightFraction: 1, weather: 'rain' }, false)).toBe(Math.round(82 * 1.2));
    expect(computeXp(70, 20_000, { nightFraction: 1, weather: 'rain' }, false)).toBe(46);
  });

  it('adds streak bonuses for clean trips', () => {
    expect(computeXp(100, 20_000, { cleanStreak: 5 }, false)).toBe(105);
    expect(computeXp(100, 20_000, { cleanStreak: 25 }, false)).toBe(110);
    expect(computeXp(70, 20_000, { cleanStreak: 25 }, false)).toBe(46);
  });
});

describe('end-to-end fixtures', () => {
  it('scores the clean commute perfectly', () => {
    const r = scoreTrip(cleanCommute());
    expect(r.score).toBe(100);
    expect(r.xp).toBe(100);
    expect(r.feedback.headline.tone).toBe('praise');
  });

  it('scores the messy commute with one of everything', () => {
    const r = scoreTrip(messyCommute());
    const kinds = new Set(r.events.map((e) => e.kind));
    expect(kinds.has('speeding')).toBe(true);
    expect(kinds.has('harsh_brake')).toBe(true);
    expect(kinds.has('phone_handling')).toBe(true);
    expect(kinds.has('high_speed_cruise')).toBe(true);
    expect(r.reckless).toBe(false);
    expect(r.score).toBeGreaterThan(30);
    expect(r.score).toBeLessThan(80);
    expect(r.feedback.headline.tone).toBe('roast');
    expect(r.feedback.lines.length).toBeGreaterThan(0);
  });

  it('is deterministic', () => {
    const a = scoreTrip(messyCommute());
    const b = scoreTrip(messyCommute());
    expect(a).toEqual(b);
  });
});

import { buildSyntheticTrip, scoreTrip } from '../src';

describe('smoothness detection from GPS', () => {
  it('derives a harsh brake from a sudden speed drop', () => {
    const trip = buildSyntheticTrip({
      id: 'brake',
      legs: [
        { durationS: 200, speedMph: 45, limitMph: 45 },
        { durationS: 6, speedMph: 5, limitMph: 45, rampAccel: 4.2 },
        { durationS: 200, speedMph: 45, limitMph: 45 },
      ],
    });
    const r = scoreTrip(trip);
    const brakes = r.events.filter((e) => e.kind === 'harsh_brake');
    expect(brakes).toHaveLength(1);
    expect(brakes[0]!.severity).toBe('moderate');
    expect(r.penalties.smoothness).toBeGreaterThan(0);
  });

  it('classifies a very hard stop as severe', () => {
    const trip = buildSyntheticTrip({
      id: 'slam',
      legs: [
        { durationS: 200, speedMph: 45, limitMph: 45 },
        { durationS: 5, speedMph: 0, limitMph: 45, rampAccel: 6 },
        { durationS: 200, speedMph: 45, limitMph: 45 },
      ],
    });
    const r = scoreTrip(trip);
    const brakes = r.events.filter((e) => e.kind === 'harsh_brake');
    expect(brakes).toHaveLength(1);
    expect(brakes[0]!.severity).toBe('severe');
  });

  it('derives harsh acceleration and taxes it in efficiency too', () => {
    const trip = buildSyntheticTrip({
      id: 'launch',
      legs: [
        { durationS: 120, speedMph: 25, limitMph: 45 },
        { durationS: 60, speedMph: 45, limitMph: 45, rampAccel: 3.6 },
        { durationS: 300, speedMph: 45, limitMph: 45 },
      ],
    });
    const r = scoreTrip(trip);
    expect(r.events.filter((e) => e.kind === 'harsh_accel')).toHaveLength(1);
    expect(r.penalties.efficiency).toBeGreaterThanOrEqual(0.5);
  });

  it('detects hard cornering from heading rate at speed', () => {
    const trip = buildSyntheticTrip({
      id: 'corner',
      legs: [
        { durationS: 200, speedMph: 35, limitMph: 45 },
        { durationS: 4, speedMph: 35, limitMph: 45, turnRateDegS: 22 },
        { durationS: 200, speedMph: 35, limitMph: 45 },
      ],
    });
    const r = scoreTrip(trip);
    const corners = r.events.filter((e) => e.kind === 'hard_corner');
    expect(corners).toHaveLength(1);
    expect(corners[0]!.severity).toBe('severe');
  });

  it('normalises short trips so one brake is not catastrophic', () => {
    const short = buildSyntheticTrip({
      id: 'short-brake',
      legs: [
        { durationS: 90, speedMph: 30, limitMph: 30 },
        { durationS: 5, speedMph: 2, limitMph: 30, rampAccel: 4 },
        { durationS: 90, speedMph: 30, limitMph: 30 },
      ],
    });
    const r = scoreTrip(short);
    expect(r.scored).toBe(true);
    // One moderate brake = 2.0 raw, normalised by 10 km / 3 km floor ≈ 6.7
    expect(r.penalties.smoothness).toBeLessThan(8);
    expect(r.penalties.smoothness).toBeGreaterThan(5);
  });

  it('prefers supplied accelerometer events over GPS derivation', () => {
    const trip = buildSyntheticTrip({
      id: 'accelerometer',
      legs: [{ durationS: 600, speedMph: 40, limitMph: 45 }],
    });
    const t0 = trip.samples[0]!.t;
    trip.motionEvents = [
      { t: t0 + 100_000, kind: 'brake', peak: 5.4 },
      { t: t0 + 101_000, kind: 'brake', peak: 4.1 }, // merged into the first
      { t: t0 + 300_000, kind: 'corner', peak: 4.4 },
      { t: t0 + 400_000, kind: 'accel', peak: 2.0 }, // below threshold, ignored
    ];
    const r = scoreTrip(trip);
    expect(r.events.filter((e) => e.kind === 'harsh_brake')).toHaveLength(1);
    expect(r.events.find((e) => e.kind === 'harsh_brake')!.severity).toBe('severe');
    expect(r.events.filter((e) => e.kind === 'hard_corner')).toHaveLength(1);
    expect(r.events.filter((e) => e.kind === 'harsh_accel')).toHaveLength(0);
  });
});

import { buildSyntheticTrip, mphToMps, scoreTrip } from '../src';

describe('speeding detection', () => {
  it('scores a clean trip at 100 with no events', () => {
    const trip = buildSyntheticTrip({
      id: 'clean',
      legs: [
        { durationS: 300, speedMph: 28, limitMph: 30, name: 'Elm St' },
        { durationS: 600, speedMph: 63, limitMph: 65, name: 'I-40' },
      ],
    });
    const r = scoreTrip(trip);
    expect(r.scored).toBe(true);
    expect(r.events).toHaveLength(0);
    expect(r.score).toBe(100);
    expect(r.penalties).toEqual({ speed: 0, smoothness: 0, attention: 0, efficiency: 0 });
    expect(r.reckless).toBe(false);
    expect(r.summary.secondsOverLimit).toBe(0);
  });

  it('detects a moderate episode with the right numbers', () => {
    const trip = buildSyntheticTrip({
      id: 'moderate',
      legs: [
        { durationS: 120, speedMph: 30, limitMph: 30 },
        { durationS: 90, speedMph: 42, limitMph: 30, name: 'Route 9' },
        { durationS: 300, speedMph: 30, limitMph: 30 },
      ],
    });
    const r = scoreTrip(trip);
    const sp = r.events.filter((e) => e.kind === 'speeding');
    expect(sp).toHaveLength(1);
    const e = sp[0]!;
    expect(e.severity).toBe('moderate');
    expect(e.detail.kind).toBe('speeding');
    if (e.detail.kind === 'speeding') {
      expect(e.detail.roadName).toBe('Route 9');
      expect(e.detail.maxOver).toBeCloseTo(mphToMps(12), 1);
      expect(e.detail.timeSavedS).toBeGreaterThan(15);
      expect(e.detail.timeSavedS).toBeLessThan(40);
    }
    // ~90 s includes the ramp down, so allow a little slack.
    expect(e.durationS).toBeGreaterThanOrEqual(85);
    expect(e.durationS).toBeLessThanOrEqual(100);
    expect(r.penalties.speed).toBeGreaterThan(3);
    expect(r.score).toBeLessThan(100);
  });

  it('ignores episodes shorter than 8 seconds', () => {
    const trip = buildSyntheticTrip({
      id: 'blip',
      legs: [
        { durationS: 200, speedMph: 30, limitMph: 30 },
        { durationS: 3, speedMph: 40, limitMph: 30, rampAccel: 10 },
        { durationS: 200, speedMph: 30, limitMph: 30, rampAccel: 10 },
      ],
    });
    const r = scoreTrip(trip);
    expect(r.events.filter((e) => e.kind === 'speeding')).toHaveLength(0);
  });

  it('merges episodes separated by a short dip', () => {
    const trip = buildSyntheticTrip({
      id: 'merge',
      legs: [
        { durationS: 100, speedMph: 30, limitMph: 30 },
        { durationS: 40, speedMph: 42, limitMph: 30 },
        { durationS: 4, speedMph: 33, limitMph: 30, rampAccel: 4 },
        { durationS: 40, speedMph: 42, limitMph: 30, rampAccel: 4 },
        { durationS: 100, speedMph: 30, limitMph: 30 },
      ],
    });
    const r = scoreTrip(trip);
    expect(r.events.filter((e) => e.kind === 'speeding')).toHaveLength(1);
  });

  it('records speeding on low-confidence roads as observations, not penalties', () => {
    const trip = buildSyntheticTrip({
      id: 'lowconf',
      legs: [
        { durationS: 200, speedMph: 30, limitMph: 30 },
        { durationS: 120, speedMph: 45, limitMph: 30, confidence: 0.4, name: 'Mystery Rd' },
        { durationS: 200, speedMph: 30, limitMph: 30 },
      ],
    });
    const r = scoreTrip(trip);
    expect(r.events.filter((e) => e.kind === 'speeding')).toHaveLength(0);
    expect(r.observations).toHaveLength(1);
    expect(r.penalties.speed).toBe(0);
    expect(r.score).toBe(100);
  });

  it('does not judge roads with no limit at all', () => {
    const trip = buildSyntheticTrip({
      id: 'nolimit',
      legs: [{ durationS: 600, speedMph: 55 }],
    });
    const r = scoreTrip(trip);
    expect(r.events).toHaveLength(0);
    expect(r.flags).toContain('limits_unknown');
  });

  it('flags reckless at 25+ over and zeroes XP', () => {
    const trip = buildSyntheticTrip({
      id: 'reckless',
      legs: [
        { durationS: 200, speedMph: 30, limitMph: 30 },
        { durationS: 30, speedMph: 58, limitMph: 30, name: 'Elm St' },
        { durationS: 400, speedMph: 30, limitMph: 30 },
      ],
    });
    const r = scoreTrip(trip);
    expect(r.reckless).toBe(true);
    expect(r.flags).toContain('reckless_speed');
    expect(r.score).toBeLessThanOrEqual(25);
    expect(r.xp).toBe(0);
    expect(r.feedback.headline.tone).toBe('roast');
  });

  it('flags 100+ mph as reckless even with an unknown limit', () => {
    const trip = buildSyntheticTrip({
      id: 'ton',
      legs: [
        { durationS: 200, speedMph: 60 },
        { durationS: 15, speedMph: 104, rampAccel: 3 },
        { durationS: 200, speedMph: 60, rampAccel: 3 },
      ],
    });
    const r = scoreTrip(trip);
    expect(r.reckless).toBe(true);
    const e = r.events.find((x) => x.kind === 'speeding');
    expect(e?.severity).toBe('reckless');
  });

  it('skips samples with bad GPS accuracy', () => {
    const trip = buildSyntheticTrip({
      id: 'badgps',
      legs: [
        { durationS: 200, speedMph: 30, limitMph: 30 },
        { durationS: 60, speedMph: 45, limitMph: 30, accuracy: 120 },
        { durationS: 200, speedMph: 30, limitMph: 30 },
      ],
    });
    const r = scoreTrip(trip);
    expect(r.events.filter((e) => e.kind === 'speeding')).toHaveLength(0);
  });
});

describe('limit-drop grace', () => {
  it('does not punish slowing down after the limit drops', () => {
    // 65 mph highway straight into a 25 mph street, decelerating at a gentle 1.5 m/s².
    const trip = buildSyntheticTrip({
      id: 'exit-ramp',
      legs: [
        { durationS: 300, speedMph: 63, limitMph: 65, name: 'I-40' },
        { durationS: 180, speedMph: 22, limitMph: 25, name: 'Maple Ave' },
      ],
    });
    const r = scoreTrip(trip);
    expect(r.events.filter((e) => e.kind === 'speeding')).toHaveLength(0);
    expect(r.reckless).toBe(false);
    expect(r.score).toBe(100);
  });

  it('still catches a driver who keeps the speed after the limit drops', () => {
    const trip = buildSyntheticTrip({
      id: 'ignores-sign',
      legs: [
        { durationS: 300, speedMph: 63, limitMph: 65, name: 'I-40' },
        { durationS: 40, speedMph: 63, limitMph: 25, name: 'Maple Ave' },
        { durationS: 180, speedMph: 22, limitMph: 25, name: 'Maple Ave' },
      ],
    });
    const r = scoreTrip(trip);
    const sp = r.events.filter((e) => e.kind === 'speeding');
    expect(sp).toHaveLength(1);
    expect(sp[0]!.severity).toBe('reckless');
    // Only the first few seconds are forgiven.
    expect(sp[0]!.durationS).toBeGreaterThanOrEqual(30);
  });
});

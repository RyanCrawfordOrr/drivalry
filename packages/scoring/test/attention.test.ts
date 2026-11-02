import { buildSyntheticTrip, scoreTrip } from '../src';

describe('phone handling', () => {
  it('ignores phone use while stopped or crawling', () => {
    const trip = buildSyntheticTrip({
      id: 'stopped',
      legs: [
        { durationS: 200, speedMph: 30, limitMph: 30 },
        { durationS: 60, speedMph: 0, limitMph: 30 },
        { durationS: 200, speedMph: 30, limitMph: 30 },
      ],
      phoneEventsAt: [{ atS: 230 }, { atS: 240 }],
    });
    const r = scoreTrip(trip);
    expect(r.events.filter((e) => e.kind === 'phone_handling')).toHaveLength(0);
  });

  it('merges taps within 20 s into one episode and grades by duration', () => {
    const trip = buildSyntheticTrip({
      id: 'taps',
      legs: [{ durationS: 600, speedMph: 35, limitMph: 45 }],
      phoneEventsAt: [{ atS: 100 }, { atS: 110 }, { atS: 125 }, { atS: 400 }],
    });
    const r = scoreTrip(trip);
    const eps = r.events.filter((e) => e.kind === 'phone_handling');
    expect(eps).toHaveLength(2);
    expect(eps[0]!.severity).toBe('moderate'); // 25 s
    expect(eps[1]!.severity).toBe('minor'); // single tap
    expect(r.penalties.attention).toBe(10);
  });

  it('treats any handling at highway speed as major', () => {
    const trip = buildSyntheticTrip({
      id: 'highway-phone',
      legs: [{ durationS: 600, speedMph: 68, limitMph: 70 }],
      phoneEventsAt: [{ atS: 300, kind: 'unlock' }],
    });
    const r = scoreTrip(trip);
    const e = r.events.find((x) => x.kind === 'phone_handling');
    expect(e?.severity).toBe('major');
    expect(r.penalties.attention).toBe(12);
    expect(r.reckless).toBe(false); // short, so not reckless
  });

  it('flags a long highway phone session as reckless', () => {
    const trip = buildSyntheticTrip({
      id: 'highway-scroll',
      legs: [{ durationS: 600, speedMph: 68, limitMph: 70 }],
      phoneEventsAt: [{ atS: 200 }, { atS: 215 }, { atS: 230 }, { atS: 245 }, { atS: 262 }, { atS: 275 }],
    });
    const r = scoreTrip(trip);
    expect(r.flags).toContain('reckless_phone');
    expect(r.reckless).toBe(true);
    expect(r.xp).toBe(0);
  });

  it('caps the attention penalty', () => {
    const trip = buildSyntheticTrip({
      id: 'phone-addict',
      legs: [{ durationS: 900, speedMph: 35, limitMph: 45 }],
      phoneEventsAt: Array.from({ length: 12 }, (_, i) => ({ atS: 60 + i * 60 })),
    });
    const r = scoreTrip(trip);
    expect(r.penalties.attention).toBe(30);
  });
});

import { TEMPLATES, buildSyntheticTrip, formatDuration, formatSaved, messyCommute, scoreTrip } from '../src';

/** Words that must never appear in a roast. The floor from docs/02-game-design.md §9.1. */
const BANNED = [
  /crash/i,
  /wreck/i,
  /\bdie\b/i,
  /\bdead\b/i,
  /death/i,
  /\bkill/i,
  /injur/i,
  /hospital/i,
  /drunk/i,
  /\bbeer\b/i,
  /\bidiot\b/i,
  /\bstupid\b/i,
  /\bmoron\b/i,
  /\bfat\b/i,
  /\bugly\b/i,
  /\bbet you can/i,
  /\bfaster\b/i,
];

describe('roast templates', () => {
  it('never cross the hard floor', () => {
    for (const [key, byIntensity] of Object.entries(TEMPLATES)) {
      for (const [intensity, list] of Object.entries(byIntensity)) {
        expect(list.length, `${key}.${intensity} has templates`).toBeGreaterThan(0);
        for (const t of list) {
          for (const re of BANNED) {
            expect(t, `${key}.${intensity}: "${t}" matches ${re}`).not.toMatch(re);
          }
        }
      }
    }
  });

  it('fills every slot it uses', () => {
    for (const intensity of ['gentle', 'sassy', 'savage'] as const) {
      const r = scoreTrip(messyCommute(`slots-${intensity}`), { intensity });
      for (const line of [r.feedback.headline, ...r.feedback.lines]) {
        expect(line.text).not.toMatch(/\{\w+\}/);
      }
    }
  });

  it('is deterministic per trip id and varies across ids', () => {
    const a = scoreTrip(messyCommute('same'), { intensity: 'savage' });
    const b = scoreTrip(messyCommute('same'), { intensity: 'savage' });
    expect(a.feedback).toEqual(b.feedback);

    const seen = new Set<string>();
    for (let i = 0; i < 12; i++) seen.add(scoreTrip(messyCommute(`id-${i}`), { intensity: 'savage' }).feedback.headline.text);
    expect(seen.size).toBeGreaterThan(1);
  });

  it('puts the speed and the road in a speeding roast', () => {
    const trip = buildSyntheticTrip({
      id: 'roadname',
      legs: [
        { durationS: 200, speedMph: 30, limitMph: 30 },
        { durationS: 120, speedMph: 42, limitMph: 30, name: 'Elm St' },
        { durationS: 200, speedMph: 30, limitMph: 30 },
      ],
    });
    const r = scoreTrip(trip, { intensity: 'savage' });
    expect(r.feedback.headline.tone).toBe('roast');
    expect(r.feedback.headline.text).toContain('Elm St');
    expect(r.feedback.headline.text).toMatch(/\b(42|12|30)\b/);
  });

  it('supports km/h output', () => {
    const trip = buildSyntheticTrip({
      id: 'metric',
      legs: [
        { durationS: 200, speedMph: 30, limitMph: 30 },
        { durationS: 120, speedMph: 42, limitMph: 30, name: 'Elm St' },
        { durationS: 200, speedMph: 30, limitMph: 30 },
      ],
    });
    const r = scoreTrip(trip, { intensity: 'gentle', units: 'kmh' });
    expect(r.feedback.headline.text).toMatch(/km\/h|\b(68|19|48)\b/);
  });

  it('praises a perfect trip', () => {
    const trip = buildSyntheticTrip({
      id: 'perfect',
      legs: [{ durationS: 900, speedMph: 40, limitMph: 45 }],
    });
    const r = scoreTrip(trip, { intensity: 'sassy' });
    expect(r.feedback.headline.tone).toBe('praise');
    expect(r.feedback.headline.text).toMatch(/miles/);
  });

  it('formats durations and savings in plain words', () => {
    expect(formatDuration(45)).toBe('45 seconds');
    expect(formatDuration(65)).toBe('a minute');
    expect(formatDuration(95)).toBe('1 min 35 s');
    expect(formatDuration(190)).toBe('3 minutes');
    expect(formatSaved(0)).toBe('nothing');
    expect(formatSaved(38)).toBe('38 seconds');
    expect(formatSaved(130)).toBe('2 minutes');
  });
});

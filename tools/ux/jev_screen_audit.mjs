// Screen heuristics with Jev (TypeSafe System One).
//
//   node tools/ux/jev_screen_audit.mjs tools/ux/screens_before.json
//   node tools/ux/jev_screen_audit.mjs tools/ux/screens_after.json
//
// Each entry describes one screen state as a person would see it (what is
// above the fold, in what order and size, the primary action, the copy).
// Jev scores four dimensions per screen; the report compares runs so a pass
// can prove it moved the needle. Needs TYPESAFE_API_KEY.
import { readFileSync, writeFileSync } from 'node:fs';
import { basename } from 'node:path';

const key = process.env.TYPESAFE_API_KEY;
if (!key) {
  console.error('TYPESAFE_API_KEY is not set');
  process.exit(2);
}
const input = process.argv[2];
if (!input) {
  console.error('usage: node jev_screen_audit.mjs <screens.json>');
  process.exit(2);
}
const screens = JSON.parse(readFileSync(input, 'utf8'));

const CONTEXT =
  'Drivalry is a consumer driving app used on a phone, sometimes glanced at in a car. ' +
  'The target feel is a blend of Waze (map-first home, big friendly targets, one obvious ' +
  'action, playful celebratory moments) and the Kith shopping app (editorial calm: generous ' +
  'space, strong type hierarchy, restrained palette, few borders). Each `screen` field is a ' +
  'faithful description of one screen state: what is visible, in what order and size, the ' +
  'actions offered, and the exact copy.';

const DIMENSIONS = {
  hierarchy: {
    instructions: 'How clear is the visual hierarchy of the screen in `screen`: does one thing read first, then a second, with the rest supporting?',
    criteria: [
      'Everything competes; no clear first read',
      'A first read exists but several elements fight for second place',
      'Clear first and second read; supporting content recedes',
      'Exemplary: a person knows where to look and what to do within a second',
    ],
  },
  load: {
    instructions: 'How much cognitive load does `screen` put on a person who opened it with one goal?',
    criteria: [
      'Overwhelming: many sections, many actions, dense text',
      'Busy: several sections and actions to scan before the goal is found',
      'Manageable: a few sections, the goal is found quickly',
      'Light: the goal is immediately available and nothing else demands attention',
    ],
  },
  waze: {
    instructions: 'How close is `screen` to the Waze feel: map or live state as the stage, big friendly touch targets, one obvious action, playful warmth, a sense of a moment worth celebrating?',
    criteria: [
      'Nothing of it: a plain settings-like list',
      'Hints of it: some big numbers or a map, but buried among ordinary widgets',
      'Mostly there: live state or map leads, targets are generous, the tone is friendly',
      'Fully there: it feels alive, glanceable and fun, like a screen designed for the car',
    ],
  },
  kith: {
    instructions: 'How close is `screen` to the Kith feel: editorial calm, generous whitespace, strong typographic hierarchy, few borders and boxes, restrained and premium?',
    criteria: [
      'The opposite: boxes inside boxes, borders, small dense text, utility styling',
      'Some calm, but cards and chips still dominate and spacing is tight',
      'Mostly calm: space and type do the work, few borders, a premium feel',
      'Fully there: it could be a page in a well-set magazine',
    ],
  },
  driving: {
    instructions: 'If a person glanced at `screen` for one second while stopped at a light, how well would it serve them? Consider text size, number of elements and whether the main action is a large target.',
    criteria: [
      'Unusable at a glance: small text, many elements, small targets',
      'Partly: one big element helps, the rest is too small or too much',
      'Good: the key number or state is big and the one action is a large target',
      'Built for it: nothing on the screen is small or ambiguous',
    ],
  },
};

async function judge(entry) {
  const questions = {};
  for (const [k, d] of Object.entries(DIMENSIONS)) {
    questions[k] = { type: 'score', instructions: d.instructions, criteria: d.criteria };
  }
  const body = JSON.stringify({
    model: 'jev-latest',
    state: { context: CONTEXT, screen: entry.description },
    questions,
  });
  for (let attempt = 0; attempt < 5; attempt++) {
    const res = await fetch('https://api.typesafe.ai/v1/systemone', {
      method: 'POST',
      headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
      body,
    });
    if (res.ok) return (await res.json()).answers;
    if (res.status === 429 || res.status >= 500) {
      await new Promise((r) => setTimeout(r, 1500 * 2 ** attempt));
      continue;
    }
    throw new Error(`${res.status} ${await res.text()}`);
  }
  throw new Error('gave up');
}

const results = [];
for (const entry of screens) {
  const answers = await judge(entry);
  const scores = Object.fromEntries(
    Object.keys(DIMENSIONS).map((k) => [k, Number(answers[k].score.toFixed(2))]),
  );
  results.push({ id: entry.id, ...scores });
  console.error(entry.id, scores);
}
const stem = basename(input, '.json');
const outDir = new URL('./out/', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
writeFileSync(`${outDir}${stem}_scores.json`, JSON.stringify(results, null, 1));

const dims = Object.keys(DIMENSIONS);
let md = `# Screen audit (Jev): ${stem}\n\nScores 0–3 per dimension (3 is best).\n\n| Screen | ${dims.join(' | ')} | mean |\n| --- |${dims.map(() => ' --- |').join('')} --- |\n`;
const totals = Object.fromEntries(dims.map((d) => [d, 0]));
for (const r of results) {
  const mean = dims.reduce((a, d) => a + r[d], 0) / dims.length;
  for (const d of dims) totals[d] += r[d];
  md += `| ${r.id} | ${dims.map((d) => r[d].toFixed(2)).join(' | ')} | ${mean.toFixed(2)} |\n`;
}
md += `| **all** | ${dims.map((d) => (totals[d] / results.length).toFixed(2)).join(' | ')} | ${(dims.reduce((a, d) => a + totals[d], 0) / dims.length / results.length).toFixed(2)} |\n`;
writeFileSync(`${outDir}${stem}_scores.md`, md);
console.error(`report at ${outDir}${stem}_scores.md`);

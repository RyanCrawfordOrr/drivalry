// Copy audit with Jev (TypeSafe System One).
//
//   node tools/ux/extract_strings.mjs > tools/ux/out/strings.json
//   node tools/ux/jev_copy_audit.mjs            # needs TYPESAFE_API_KEY in the environment
//
// For every user-facing string the app shows, Jev answers two questions:
// the main problem with it as copy for an everyday driver (or "fine"), and
// how close its voice is to a warm consumer app. Results are cached by text in
// tools/ux/out/copy_cache.json so a re-run after rewriting only asks about
// changed strings. Writes copy_audit.json and copy_audit.md next to it.
import { readFileSync, writeFileSync, existsSync } from 'node:fs';

const key = process.env.TYPESAFE_API_KEY;
if (!key) {
  console.error('TYPESAFE_API_KEY is not set');
  process.exit(2);
}
const here = new URL('./', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const outDir = `${here}out/`;
const strings = JSON.parse(readFileSync(`${outDir}strings.json`, 'utf8'));
const cachePath = `${outDir}copy_cache.json`;
const cache = existsSync(cachePath) ? JSON.parse(readFileSync(cachePath, 'utf8')) : {};

// Only what a person sees in the app. Repos, sync and native bridges hold
// keys, log lines and wire formats.
const include = [
  'features/',
  'widgets/',
  'data/badges/',
  'car/ongoing_notification.dart',
  'data/crash/',
];
const items = [];
const seen = new Set();
for (const s of strings) {
  if (!include.some((p) => s.file.startsWith(p))) continue;
  if (seen.has(s.text)) continue;
  seen.add(s.text);
  items.push(s);
}
console.error(`${items.length} distinct strings to judge (${Object.keys(cache).length} cached)`);

const PROBLEM = {
  fine: 'Clear, short and friendly for an everyday driver',
  technical: 'Developer or system jargon an everyday user would not understand (build flags, provider or database names, error codes, ids)',
  too_long: 'Too many words for a phone screen; a driver could not take it in at a glance',
  unclear: 'Meaning or the next step is unclear to someone new to the app',
  tone: 'Tone is cold, scolding, bureaucratic or inconsistent with a friendly, witty app',
};
const VOICE = [
  'Reads like a system log, a form label or an error code',
  'Plain and neutral, correct but without personality',
  'Friendly and human',
  'Warm, playful and human; the kind of line people screenshot',
];

const CONTEXT =
  'Drivalry is a friendly, witty driving app: the phone scores each drive 0 to 100, friends ' +
  'compete in weekly leagues, bad drives get roasted, convoys share a map and a radio. The app ' +
  'is read on a phone, sometimes at a glance in a car. Each `s*` field is one string the app ' +
  'shows (button, title, body, notice). `$name` or `${expr}` inside a string is a value filled ' +
  'in at runtime, not a problem by itself.';

async function judge(batch) {
  const state = { context: CONTEXT };
  const questions = {};
  batch.forEach((it, i) => {
    const k = `s${i + 1}`;
    state[k] = it.text;
    questions[`${k}_problem`] = {
      type: 'choice',
      instructions: `What is the main problem with the app text in \`${k}\` as copy for an everyday driver? Answer "fine" when there is none.`,
      criteria: PROBLEM,
    };
    questions[`${k}_voice`] = {
      type: 'score',
      instructions: `How close is the voice of the app text in \`${k}\` to a warm, playful consumer app such as Waze?`,
      criteria: VOICE,
    };
  });
  const body = JSON.stringify({ model: 'jev-latest', state, questions });
  for (let attempt = 0; attempt < 5; attempt++) {
    const res = await fetch('https://api.typesafe.ai/v1/systemone', {
      method: 'POST',
      headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
      body,
    });
    if (res.ok) return (await res.json()).answers;
    const text = await res.text();
    if (res.status === 429 || res.status >= 500) {
      await new Promise((r) => setTimeout(r, 1500 * 2 ** attempt));
      continue;
    }
    throw new Error(`${res.status} ${text}`);
  }
  throw new Error('gave up after retries');
}

const pending = items.filter((it) => !cache[it.text]);
const BATCH = 12;
const batches = [];
for (let i = 0; i < pending.length; i += BATCH) batches.push(pending.slice(i, i + BATCH));
let done = 0;
async function worker() {
  while (batches.length) {
    const batch = batches.shift();
    const answers = await judge(batch);
    batch.forEach((it, i) => {
      const k = `s${i + 1}`;
      const p = answers[`${k}_problem`];
      const v = answers[`${k}_voice`];
      cache[it.text] = {
        problem: p.choice,
        problemConfidence: p.confidence,
        problems: p.probabilities,
        voice: v.score,
        voiceConfidence: v.confidence,
      };
    });
    done += batch.length;
    writeFileSync(cachePath, JSON.stringify(cache, null, 1));
    console.error(`${done}/${pending.length}`);
  }
}
await Promise.all([worker(), worker(), worker()]);

const rows = items.map((it) => ({ ...it, ...cache[it.text] }));
writeFileSync(`${outDir}copy_audit.json`, JSON.stringify(rows, null, 1));

const flagged = rows.filter((r) => r.problem !== 'fine' && r.problemConfidence >= 0.6);
const byProblem = {};
for (const r of flagged) (byProblem[r.problem] ??= []).push(r);
const avgVoice = (rows.reduce((a, r) => a + r.voice, 0) / rows.length).toFixed(2);
const byDir = {};
for (const r of rows) {
  const d = r.file.split('/').slice(0, 2).join('/');
  const b = (byDir[d] ??= { n: 0, flagged: 0, voice: 0 });
  b.n++;
  b.voice += r.voice;
  if (r.problem !== 'fine' && r.problemConfidence >= 0.6) b.flagged++;
}
let md = `# Copy audit (Jev)\n\n${rows.length} distinct strings judged. Flagged with confidence >= 0.6: ${flagged.length}. Average voice score ${avgVoice} / 3 (0 = system log, 3 = warm and playful).\n\n`;
md += '| Area | Strings | Flagged | Avg voice |\n| --- | --- | --- | --- |\n';
for (const [d, b] of Object.entries(byDir).sort((a, b) => b[1].flagged - a[1].flagged)) {
  md += `| ${d} | ${b.n} | ${b.flagged} | ${(b.voice / b.n).toFixed(2)} |\n`;
}
for (const [problem, list] of Object.entries(byProblem).sort((a, b) => b[1].length - a[1].length)) {
  md += `\n## ${problem} (${list.length})\n\n${PROBLEM[problem]}\n\n| Text | Where | p | voice |\n| --- | --- | --- | --- |\n`;
  for (const r of list.sort((a, b) => b.problemConfidence - a.problemConfidence)) {
    const t = r.text.replace(/\|/g, '\\|').replace(/\n/g, ' ');
    md += `| ${t} | ${r.file}:${r.line} | ${r.problemConfidence.toFixed(2)} | ${r.voice.toFixed(1)} |\n`;
  }
}
md += `\n## Lowest voice (bottom 40 of the strings judged fine)\n\n| Text | Where | voice |\n| --- | --- | --- |\n`;
for (const r of rows.filter((r) => r.problem === 'fine').sort((a, b) => a.voice - b.voice).slice(0, 40)) {
  md += `| ${r.text.replace(/\|/g, '\\|')} | ${r.file}:${r.line} | ${r.voice.toFixed(1)} |\n`;
}
writeFileSync(`${outDir}copy_audit.md`, md);
console.error(`flagged ${flagged.length}; report at ${outDir}copy_audit.md`);

// Collects user-facing string literals from app/lib for the Jev copy audit.
//
//   node tools/ux/extract_strings.mjs > tools/ux/out/strings.json
//
// Heuristic: single- or double-quoted Dart literals of two or more words that
// contain a letter, excluding imports, asset paths, URLs, keys and identifiers.
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

const root = new URL('../../app/lib/', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');

function* walk(dir) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) yield* walk(p);
    else if (p.endsWith('.dart') && !p.endsWith('.g.dart')) yield p;
  }
}

const literal = /(['"])((?:\\.|(?!\1)[^\\\n])*)\1/g;
const out = [];
for (const file of walk(root)) {
  const lines = readFileSync(file, 'utf8').split(/\r?\n/);
  // Dart joins adjacent literals ('a '\n'b'), so a sentence often spans
  // lines. Join a literal that starts a line onto the previous line's literal
  // when that literal was the last thing on its line.
  let open = null; // {entry, line}
  lines.forEach((line, i) => {
    const trimmed = line.trim();
    if (/^(import|export|part)\b/.test(trimmed)) return;
    if (/^\/\//.test(trimmed)) return; // comments
    if (/debugPrint|assert\(/.test(line)) return;
    const matches = [...line.matchAll(literal)];
    matches.forEach((m, j) => {
      const text = m[2].replace(/\\'/g, "'").replace(/\\"/g, '"');
      const startsLine = j === 0 && line.slice(0, m.index).trim() === '';
      const endsLine =
        j === matches.length - 1 && line.slice(m.index + m[0].length).trim() === '';
      if (open && startsLine && open.line === i - 1) {
        open.entry.text += text;
        open = endsLine ? { entry: open.entry, line: i } : null;
        return;
      }
      const entry = { file: relative(root, file).replace(/\\/g, '/'), line: i + 1, text };
      out.push(entry);
      open = endsLine ? { entry, line: i } : null;
    });
    if (matches.length === 0) open = null;
  });
}
// Keep what reads as copy: two words with letters, not a path, URL or key.
for (let i = out.length - 1; i >= 0; i--) {
  const { text } = out[i];
  const drop =
    !/[A-Za-z]{2,}\s+[A-Za-z]/.test(text) ||
    (/[/\\]|https?:|\.dart|\$\{?[a-z_]+/.test(text) && !/ /.test(text)) ||
    /^[a-z_]+(:[a-z_]+)+$/.test(text);
  if (drop) out.splice(i, 1);
}
console.log(JSON.stringify(out, null, 1));
console.error(`${out.length} strings from ${root}`);

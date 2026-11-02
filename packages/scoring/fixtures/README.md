# Scoring fixtures

**Generated. Do not edit by hand.** Regenerate with `npm run fixtures` from the repo root
(`packages/scoring/scripts/export-fixtures.ts`).

`@drivalry/scoring` (TypeScript) is the specification of the Drivalry scoring engine. These
files are its contract: every port must reproduce them. Today the consumer is
`packages/drivalry_scoring` (Dart), whose `test/fixtures_test.dart` loads every `*.json` in
this directory.

## Conventions

- All quantities are SI (metres, seconds, m/s, m/s²); timestamps are epoch milliseconds.
- JSON cannot carry `NaN` or `±Infinity`. They are written as the strings `"NaN"`,
  `"Infinity"` and `"-Infinity"`. A port must compare them as the corresponding doubles.
- Properties that were `undefined` in TypeScript are **omitted** (that is what
  `JSON.stringify` does). Treat a missing key and `null` as the same thing.
- Comparison rule used by the Dart suite: exact for integers, strings, enums and booleans;
  absolute tolerance 1e-6 for doubles.

Every file has a top-level `"kind"`: `"trip"`, `"hash"`, `"format"`, `"computeXp"` or `"templates"`.

## `kind: "trip"` (one file per case)

| Field | Meaning |
| --- | --- |
| `name`, `description`, `mirrors` | Case identity, what it demonstrates, which TS test or doc section it mirrors. |
| `source` | How `input` was built. `{ builder: "buildSyntheticTrip", spec }`, `{ builder: "cleanCommute" \| "messyCommute", id }` or `{ builder: "manual" }`. When a builder is named, calling the same builder in a port must reproduce `input.samples`, `input.segments` and `input.phoneEvents` (`context` and `motionEvents` may have been added afterwards). |
| `options` | The `ScoreOptions` passed to `scoreTrip` (`intensity`: gentle \| sassy \| savage, default sassy; `units`: mph \| kmh, default mph). |
| `input` | The complete `TripInput`: `id`, `samples[]` (`t, lat, lon, speed, accuracy, heading?, altitude?`), `segments[]` (`fromIdx, toIdx, speedLimit` m/s or null, `confidence` 0–1, `roadClass`, `name?`, `wayId?`), `phoneEvents?[]` (`t, kind`), `motionEvents?[]` (`t, kind, peak`), `context?` (`nightFraction?, weather?, vehicleId?, isPassenger?, dailyCreditedKmBefore?, cleanStreak?`). |
| `expected` | The complete `TripScore` returned by `scoreTrip(input, options)`: `tripId, scored, unscoredReason?, score, penalties{speed,smoothness,attention,efficiency}, flags[], reckless, xp, events[], observations[], summary{...}, feedback{headline, lines[]}`. Each event: `kind, severity, startT, endT, durationS, startIdx, endIdx, lat, lon, detail` where `detail.kind` selects the shape (speeding: `limit, maxSpeed, avgOver, maxOver, roadName?, roadClass, timeSavedS`; harsh_brake/harsh_accel/hard_corner: `peak, speedAtStart`; phone_handling: `interactions, maxSpeed, kinds[]`; idling: `excessS`; high_speed_cruise: `maxSpeed`). Each feedback line: `tone` (roast \| praise), `text`, `eventIndex?`. |
| `expected.eventLines[]` | For every scored event `i`: `formatDuration(events[i].durationS)`, `formatSaved(detail.timeSavedS)` (speeding only) and `roastEvent(events[i], tripId, i, options)`. |
| `expected.severityOrder[]` | Indices into `expected.events` in `sortBySeverity()` order (worst first, then by start time). |
| `expected.feedbackVariants[]` | `buildFeedback` output (`headline`, `lines`) for every `intensity` × `units` combination, independent of `options`. Pins the FNV-1a template selection and every slot formatter. |

## `kind: "hash"` — `vectors-hash.json`

`vectors[]` of `{ seed, hash }`: FNV-1a 32-bit over the UTF-16 code units of `seed`
(`String.prototype.charCodeAt`), unsigned result. Template choice is `hash(seed) % list.length`.

## `kind: "format"` — `vectors-format.json`

`formatDuration[]` and `formatSaved[]` of `{ input, expected }` (seconds in, display string out).
Inputs include .5 ties and negatives to pin JavaScript `Math.round` semantics (ties round toward +∞).

## `kind: "computeXp"` — `vectors-xp.json`

`vectors[]` of `{ score, distanceM, context?, reckless, expected }` for `computeXp`.

## `kind: "templates"` — `vectors-templates.json`

`templates`: the complete `TEMPLATES` library (`templateKey → intensity → string[]`). A port must
carry exactly these strings in exactly this order, because selection is by index.

## Cases

| File | What it shows | Mirrors |
| --- | --- | --- |
| `clean-commute.json` | The canned 20-minute clean commute. Score 100, XP 100, praise headline. | score.test.ts › end-to-end fixtures › scores the clean commute perfectly |
| `messy-commute.json` | The canned "one of everything" commute: speeding, harsh brake, phone, high-speed cruise. Default (sassy, mph) options. | score.test.ts › end-to-end fixtures › scores the messy commute with one of everything |
| `messy-commute-gentle.json` | Messy commute rendered with the gentle roast tone. | roast.test.ts › fills every slot it uses (gentle) |
| `messy-commute-sassy.json` | Messy commute rendered with the sassy roast tone (explicit). | roast.test.ts › fills every slot it uses (sassy) |
| `messy-commute-savage.json` | Messy commute rendered with the savage roast tone. | roast.test.ts › fills every slot it uses (savage) |
| `messy-commute-kmh.json` | Messy commute with km/h feedback copy, savage tone. | roast.test.ts › supports km/h output (applied to the messy commute) |
| `roast-seed-id-7.json` | Messy commute under a different trip id, so the FNV-1a seed picks different templates. | roast.test.ts › is deterministic per trip id and varies across ids |
| `speeding-clean.json` | Under the limit on two named roads. No events, score 100. | speeding.test.ts › scores a clean trip at 100 with no events |
| `speeding-moderate.json` | 42 in a 30 on Route 9 for ~90 s: one moderate episode with time-saved maths. | speeding.test.ts › detects a moderate episode with the right numbers |
| `speeding-blip.json` | A 3 s burst over the limit is shorter than minDurationS and ignored. | speeding.test.ts › ignores episodes shorter than 8 seconds |
| `speeding-merge.json` | Two over-limit stretches separated by a 4 s dip merge into one episode. | speeding.test.ts › merges episodes separated by a short dip |
| `speeding-lowconf.json` | Speeding on a confidence-0.4 segment becomes an observation, never a penalty. | speeding.test.ts › records speeding on low-confidence roads as observations, not penalties |
| `speeding-nolimit.json` | No limit anywhere: nothing is judged and limits_unknown is flagged. | speeding.test.ts › does not judge roads with no limit at all |
| `speeding-reckless.json` | 58 in a 30 for 30 s: reckless severity, score capped at 25, XP 0. | speeding.test.ts › flags reckless at 25+ over and zeroes XP |
| `speeding-ton.json` | 104 mph with no known limit: absolute reckless. The limit/over fields are NaN (serialised as "NaN"). | speeding.test.ts › flags 100+ mph as reckless even with an unknown limit |
| `speeding-badgps.json` | Over the limit only while GPS accuracy is 120 m: samples above 50 m are ignored. | speeding.test.ts › skips samples with bad GPS accuracy |
| `grace-exit-ramp.json` | 65 → 25 limit drop while decelerating at 1.5 m/s²: grace period, no event, not reckless. | speeding.test.ts › limit-drop grace › does not punish slowing down after the limit drops |
| `grace-ignores-sign.json` | Keeps 63 mph for 40 s after the limit drops to 25: grace ends, reckless episode. | speeding.test.ts › limit-drop grace › still catches a driver who keeps the speed after the limit drops |
| `smooth-brake-moderate.json` | GPS-derived harsh brake at 4.2 m/s²: moderate. | smoothness.test.ts › derives a harsh brake from a sudden speed drop |
| `smooth-brake-severe.json` | GPS-derived stop at 6 m/s²: severe. | smoothness.test.ts › classifies a very hard stop as severe |
| `smooth-launch.json` | Harsh acceleration at 3.6 m/s²: smoothness event plus the efficiency aggression tax. | smoothness.test.ts › derives harsh acceleration and taxes it in efficiency too |
| `smooth-corner.json` | 22°/s heading change at 35 mph: severe hard corner from heading rate × speed. | smoothness.test.ts › detects hard cornering from heading rate at speed |
| `smooth-short-brake.json` | One moderate brake on a ~2.4 km trip: normalised against the 3 km floor. | smoothness.test.ts › normalises short trips so one brake is not catastrophic |
| `smooth-accelerometer.json` | Supplied motionEvents override GPS derivation: two brakes merge, a corner counts, a weak accel is ignored. | smoothness.test.ts › prefers supplied accelerometer events over GPS derivation |
| `phone-stopped.json` | Phone events while stopped are ignored. | attention.test.ts › ignores phone use while stopped or crawling |
| `phone-taps.json` | Three taps within 20 s merge into a 25 s moderate episode; a lone tap is minor. | attention.test.ts › merges taps within 20 s into one episode and grades by duration |
| `phone-highway.json` | A single unlock at 68 mph is major but too short to be reckless. | attention.test.ts › treats any handling at highway speed as major |
| `phone-highway-scroll.json` | 75 s of phone handling at 68 mph: reckless_phone, score ≤ 25, XP 0. | attention.test.ts › flags a long highway phone session as reckless |
| `phone-addict.json` | Twelve separate taps: attention penalty hits the 30-point cap. | attention.test.ts › caps the attention penalty |
| `trip-too-short.json` | One minute at 20 mph is under 1 km and under 120 s moving: logged, not scored. | score.test.ts › trip minimums › does not score trips under 1 km |
| `trip-passenger.json` | Clean commute marked as a passenger trip: not scored, passenger copy. | score.test.ts › trip minimums › does not score passenger trips |
| `efficiency-cruise.json` | 79 mph under an 80 limit for 10 min: no speeding, one high_speed_cruise, efficiency 5–6. | score.test.ts › efficiency › penalises sustained cruising above 75 mph even under the limit |
| `efficiency-idle.json` | A 400 s mid-trip stop: idling event, light efficiency penalty. | score.test.ts › efficiency › penalises long mid-trip idling lightly |
| `roast-roadname.json` | Savage speeding roast must name Elm St and quote the numbers. | roast.test.ts › puts the speed and the road in a speeding roast |
| `roast-metric.json` | Gentle tone with km/h units. | roast.test.ts › supports km/h output |
| `roast-perfect.json` | A perfect 15-minute trip gets a praise headline mentioning miles. | roast.test.ts › praises a perfect trip |
| `context-night-rain-streak.json` | Clean commute at night in the rain on a 7-trip streak: ×1.1 × 1.1 context bonus plus the tier-1 streak bonus. | docs/02-game-design.md §5 (XP context bonus + streak), computeXp |
| `context-daily-cap.json` | Clean commute after 100 km already credited today: distance factor floors at 0.4 → 40 XP. | score.test.ts › XP › applies the daily distance cap (end-to-end) |
| `context-streak-tier2.json` | Clean commute on a 25-trip streak in snow at 40 % night: +10 streak XP, weather bonus only (night < 0.5). | score.test.ts › XP › adds streak bonuses for clean trips (end-to-end) |
| `context-reckless-night.json` | messyCommute("reckless-night") with its phone events replaced by a long highway phone session, at night in the rain on a 30-trip streak: reckless, so no context bonus can rescue XP (0). | docs/02-game-design.md §4.5 (Reckless flag zeroes XP regardless of context) |
| `edge-empty-trip.json` | No samples at all: unscored (too_short) with an all-zero summary. | prepare.ts / score.ts degenerate-input handling |
| `edge-unsorted-samples.json` | Clean commute with the sample array reversed: prepare() sorts by time, so the result equals clean-commute under this id. | prepare.ts (samples sorted by t) |

# drivalry_scoring

Dart port of the Drivalry scoring engine. GPS samples and map-matched road segments in;
Drive Score (0–100), events, XP, flags and roast/praise copy out. Pure Dart, no Flutter
dependency, so it runs on-device in the app and anywhere else Dart runs.

```dart
import 'package:drivalry_scoring/drivalry_scoring.dart';

final result = scoreTrip(messyCommute(), const ScoreOptions(intensity: Intensity.savage));
print('${result.score}/100, ${result.xp} XP, ${result.events.length} events');
print(result.feedback.headline.text);
```

## The TypeScript package is the spec

`packages/scoring` (`@drivalry/scoring`) is the reference implementation and the place where
the rules change. This package is a module-for-module port of it:

| TypeScript                     | Dart                                     |
| ------------------------------ | ---------------------------------------- |
| `src/types.ts`                 | `lib/src/types.dart`                     |
| `src/constants.ts`             | `lib/src/constants.dart`                 |
| `src/geo.ts`                   | `lib/src/geo.dart`                       |
| `src/prepare.ts`               | `lib/src/prepare.dart`                   |
| `src/events/*.ts`              | `lib/src/events/*.dart`                  |
| `src/score.ts`                 | `lib/src/score.dart`                     |
| `src/roast/templates.ts`       | `lib/src/roast/templates.dart`           |
| `src/roast/index.ts`           | `lib/src/roast/roast.dart`               |
| `src/synthetic.ts`             | `lib/src/synthetic.dart`                 |
| —                              | `lib/src/js_compat.dart` (JS number semantics) |

The public API (`lib/drivalry_scoring.dart`) mirrors `src/index.ts`: `scoreTrip`, `computeXp`,
`sortBySeverity`, `buildFeedback`, `roastEvent`, `formatDuration`, `formatSaved`, `templates`,
`buildSyntheticTrip`, `cleanCommute`, `messyCommute`, the geo helpers, the constants and every
type. Names are the TypeScript names in Dart case (`SPEEDING.minOver` → `Speeding.minOver`,
`TEMPLATES` → `templates`, `'harsh_brake'` → `EventKind.harshBrake` with `.wire == 'harsh_brake'`).

Do not change a rule or a number here first. Change it in TypeScript, regenerate the fixtures,
then make this package pass again.

## The fixtures are the contract

`packages/scoring/fixtures/` holds the complete input and the complete expected output of
42 trips plus vector files for `hash`, `formatDuration`/`formatSaved`, `computeXp` and the
template library. They are written by the TypeScript engine; `test/fixtures_test.dart` loads
every one of them (resolving the path from this package's own location) and asserts that the
Dart engine produces the same output: exact for integers, strings, enums and booleans, 1e-6
absolute tolerance for doubles. `fixtures/README.md` documents the schema.

### Regenerate the fixtures

From the repo root (Node 20+):

```sh
npm install
npm run fixtures        # runs packages/scoring/scripts/export-fixtures.ts with tsx
```

### Run both suites

```sh
# TypeScript (the spec)
npm test                # vitest, from the repo root

# Dart (the port)
cd packages/drivalry_scoring
dart pub get
dart analyze
dart test
```

The Dart suite also contains line-by-line ports of the five TypeScript test files
(`speeding_test.dart`, `smoothness_test.dart`, `attention_test.dart`, `score_test.dart`,
`roast_test.dart`) so the behaviour is described in Dart too, plus `js_compat_test.dart` and
`synthetic_test.dart`.

## Where Dart and JavaScript differ (and what the port does about it)

All of these live in `lib/src/js_compat.dart` or are called out in a comment at the use site.

- **`Math.round`** rounds ties toward +∞; Dart's `round()` rounds ties away from zero.
  `jsRound` reproduces JS (used for penalties, score, XP and all speed/duration copy).
- **Integer-valued doubles in strings**: JS prints `45`, Dart would print `45.0`.
  `jsIntegerString` renders them the JS way (including `NaN` / `Infinity`).
- **`%` on doubles**: JS keeps the dividend's sign; Dart's `%` is Euclidean. The port uses
  `remainder()` wherever the TypeScript uses `%` (bearings, headings, duration formatting).
- **`Array.prototype.sort` is stable**; Dart's `List.sort` is not guaranteed to be. Every sort
  goes through `stableSorted`, because event order (and therefore `eventIndex` in the feedback)
  depends on ties keeping insertion order.
- **FNV-1a hash**: `Math.imul(h, 0x01000193) >>> 0` becomes a 32-bit-masked multiply, split so
  no intermediate exceeds 2^53 (also exact if ever compiled to JavaScript). Hashes run over
  UTF-16 code units (`charCodeAt` ↔ `codeUnitAt`).
- **`toFixed(1)`** ↔ `toStringAsFixed(1)`: both follow the ECMAScript rounding rules.
- **`x ** 2`** in the haversine is written as `x * x` with the TypeScript operand association
  preserved, so results agree to the last bit wherever `sin`/`cos`/`atan2` do.
- **`NaN` limits**: the absolute-reckless event on a road with no known limit carries
  `limit = NaN` in both engines; fixtures spell it `"NaN"`.
- **Timestamps** are `int` epoch milliseconds in Dart (`number` in TypeScript); all other
  quantities are `double`. `LegSpec.durationS` and `PhoneEventAt.atS` are whole seconds.
- **`roastEvent`** always returns a line in Dart; the TypeScript `| null` branch is unreachable.

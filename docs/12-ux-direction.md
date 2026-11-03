# Drivalry: UX direction (Waze × Kith)

> The feel we are building toward, and the rules every screen follows. Waze supplies the home: a map you live on, big friendly targets, one obvious action, live state you can read in a glance, and moments that celebrate you. Kith supplies everything else: editorial calm, generous space, strong type hierarchy, few borders, nothing shouting. A rebrand (palette, type, mark) is arriving separately; everything here references tokens, so the rebrand is a swap, not a rewrite.

Companion documents: `02-game-design.md` (what the numbers mean), `05-privacy-safety-legal.md` (what we may show), `12-ux-audit.md` (what the app looked like before this pass) and `tools/ux/` (the Jev copy and screen audits that score the work).

## 1. Principles

1. **Glanceable first.** Anything a driver might see gets one number, one word, one action. Text a driver reads is at most seven words; body copy anywhere is at most two lines.
2. **One obvious action.** Each screen state has at most one primary button. Secondary actions are text buttons or live in the overflow.
3. **Live state floats, history scrolls.** The map and the live card are a stage; everything historical scrolls in a sheet or a list under it.
4. **Space does the work of lines.** Hierarchy comes from type size, weight and spacing. Dividers and outlined cards are the exception.
5. **Numbers are the heroes.** Score, speed, XP, rank: large, tabular, with a small kicker above. Decorations never compete with the number.
6. **Celebrate the drive, roast the drive.** Scoring a trip is a moment with motion and haptics. Roasts stay witty and about the trip, never the person (docs/02 §9).
7. **Never show the plumbing.** No build flags, provider names, ids, error codes or "offline build" in a user-facing string. Problems are described as what the person can do next.
8. **Dark is home.** The app is used in cars at night; dark is designed first and light must look as deliberate, not inverted.

## 2. Layout grammar

| Token | Value | Use |
| --- | --- | --- |
| Gutter | 20 | Screen edge padding on every list and sheet |
| Space scale | 4, 8, 12, 16, 24, 32, 48 | Only these; no 10, 14, 18 |
| Section gap | 32 | Between editorial sections |
| Card radius | 20 | Tonal surfaces, no border |
| Sheet radius | 28 | Bottom sheets and the Drive sheet |
| Pill radius | full | Chips, status capsules, filters |
| Touch target | 48 min, 64 in driving contexts | Buttons, list rows, map controls |
| Primary button | 56 tall, full width, radius 16 | One per screen state |

Surfaces: `surface` for the page, `surfaceContainerLow` for resting cards, `surfaceContainerHigh` for the sheet and anything that floats over the map, `primaryContainer` only for the live/recording card and the primary button. Elevation is expressed by tone, not shadow, except for things floating over the map (soft shadow, 24 blur, 12 % black).

## 3. Type roles

Roles, not sizes, so the rebrand can change the family and the scale in one place (`DrivalryType` in `lib/app/ui/typography.dart`).

| Role | Default | Use |
| --- | --- | --- |
| `display` | 64 / w800 / tabular, letter-spacing −2 | The live speed, the score on the trip screen, Wrapped numbers |
| `headline` | 28 / w700, −0.5 | Screen titles in editorial screens, verdicts |
| `title` | 20 / w600 | Card titles, names |
| `body` | 16 / w400, height 1.35 | Everything readable |
| `label` | 14 / w600 | Buttons, chips, table figures |
| `kicker` | 12 / w700 / uppercase / +1.2 | The small label above a number or a section ("LAST TRIP", "THIS WEEK") |
| `caption` | 13 / w400, onSurfaceVariant | Timestamps, units, helper text |

Numbers always use tabular figures. Units sit in `label` next to a `display` number, baseline-aligned, never inside the big figure.

## 4. Components (`lib/app/ui/`)

| Component | What it is | Replaces |
| --- | --- | --- |
| `Kicker` | Uppercase small label | Ad-hoc `titleSmall` section labels |
| `EditorialSection` | Kicker + optional action + child, 32 gap | Padding + Text pairs in every list |
| `Tile` | Tonal rounded surface with 20 padding; `onTap` gives ripple and a light haptic | `Card` with inconsistent margins |
| `HeroNumber` | Kicker, display number, unit, caption | Hand-built Columns around big numbers |
| `StatTile` | Small number + label, for 2–3 column grids | The trip-detail and stats grids |
| `PrimaryButton` / `SecondaryButton` | 56 tall, full width; secondary is tonal | Mixed `FilledButton` / `OutlinedButton` sizes |
| `Pill` | Status capsule, optional dot and icon | Chips used as status |
| `Avatar` | Initials or photo, three sizes, ring for "you" | Three different avatar widgets |
| `ScoreRing` | Existing ring, now with `size` presets and an animated reveal | Same widget, more consistent use |
| `EmptyState` | Kicker + headline + one line + one action | Icon + grey text blocks |
| `DrivalrySheet` | Modal bottom sheet with handle, title, 28 radius | Dialogs for anything that is not destructive |
| `Celebration` | Full-screen reveal: ring animates in, verdict, XP counts up, badges slide in; confetti above 90, a playful "stamp" below 40 | Nothing today |
| `Haptics` | `tap`, `select`, `success`, `warning` wrappers over `HapticFeedback` | Scattered or missing |
| `Motion` | Durations 120/200/280/400 and the Material 3 emphasized curves | Defaults |

Rules: no `Card` with `shape: Border`, no `Divider` inside tiles, no icon-only buttons without a tooltip, no snackbars for things the person must act on (use a sheet), destructive confirmations stay dialogs.

## 5. Motion and feedback

- **Durations.** 120 ms state changes, 200 ms reveals, 280 ms screen transitions, 400 ms the celebration curve. Emphasized decelerate for entering, emphasized accelerate for leaving.
- **Hero.** The score ring flies from the list to the trip screen (`Hero` tag `trip-ring-<id>`).
- **Sheet physics.** The Drive sheet snaps to three stops: peek (live card only), half, full. Dragging the map collapses it to peek.
- **Haptics.** Light on taps that change state, medium when a trip scores, heavy when a badge or promotion lands, warning pattern when the crash countdown starts.
- **Celebrations.** Trip scored (always), badge earned, league promotion, duel won, season closed. Each is one full-screen moment with a single "Nice" / "Share" / "Fair" dismissal and never blocks a driving screen (queued until the car is parked).
- **Loading.** Skeleton tiles in the sheet and lists; never a bare spinner in the middle of a screen. Pull to refresh on every synced list.

## 6. Voice

- Second person, present tense, short. "Scored when you park." not "Trips are scored upon completion."
- Titles are at most seven words; bodies two lines; buttons one or two words that name the outcome ("Allow", "End drive", "Join").
- Warm by default, witty in roasts, plain in safety. The crash flow is the one place with no jokes.
- No jargon: not "sync", "provider", "cache", "build", "configured", "dart-define", "Supabase", "RLS", "UUID". Say what it means for the person: "Needs a connection", "Ask Ryan to turn this on", "Not available in this version".
- Numbers carry units in the unit the person chose; never m/s or metres in copy.
- Jev checks every string (`tools/ux/jev_copy_audit.mjs`): the target is zero strings flagged `technical`, under ten flagged anything, and an average voice score above 2.0.

## 7. Blueprints

### Drive (home)

Map full-bleed under a transparent status bar. Floating at the top: a status capsule (idle: "Ready. Drives start on their own." · recording: speed `display` with the limit beside it · paused: "Paused until 7 pm"), and the friend-request and settings buttons as round tonal targets. Friends are avatars on the map; tapping one opens a sheet with their last drive. A `DraggableScrollableSheet` holds, in order: the live card when recording (speed, limit and road, distance, time, one "End drive" button); the passenger question when pending; the last trip as a hero (ring, verdict, three stats) that opens the trip; recents as compact rows. Crash, parking and vehicle prompts appear as single tiles at the top of the sheet only when they apply. The overflow menu keeps Simulate, Packs, Units and Diagnostics.

### Trip

Hero: the ring (`display`) with XP under it and the verdict beside it as `headline`. Then a breakdown as four thin bars with labels, a `StatTile` grid of six, "What happened" as a timeline of events each with an icon, a plain one-line description and the time. Share is the only app-bar action besides the overflow. The route map, when present, sits above the hero at 40 % height and fades under the sheet of content.

### Friends

Three tabs stay (Feed, Friends, Circles). Feed cards: avatar, name and time, a kicker (WALL OF FAME / WALL OF SHAME) only when the post is one, ring and verdict, reaction pills in one row that scrolls, comments count. No borders between cards; 24 between them. Empty feed: "Nothing yet. Add a friend and the roasts start." with one Add friend button.

### Leagues

Top: the league as a hero (name, week countdown, your rank and XP as `HeroNumber`). Standings as rows with rank, avatar, name, XP, tier pill, movement arrow; your row tinted. Promotion and relegation zones are kickers in green and red, not boxes. Challenges and duels are tiles above the table, one line each.

### Convoy

A hub with the active convoy as a hero (name, destination, ETA, members as stacked avatars) and five large tiles: Map, Radio, Stops, Chat, Music; Games and Album and Expenses and Recap under "More". Radio and Stops are driving screens: 64 targets, `display` state words, nothing smaller than `label`.

### Garage, Profile, Stats, Wrapped, Settings

Editorial lists: sections with kickers, tiles without borders, `HeroNumber` for totals. Settings grouped under kickers (Drives, Friends, Safety, Car, About) with one-line descriptions. Sign-in: the mark, one line of what the app does, two buttons, one privacy sentence. First run: three screens (what it does, why it needs location all the time, done), each with one button.

## 8. Jev in the loop

Jev (TypeSafe System One) is used at design time, from this repo, never from the app: `tools/ux/jev_copy_audit.mjs` judges every string; `tools/ux/jev_screen_audit.mjs` scores each screen description on hierarchy, cognitive load, Waze warmth and Kith calm before and after a pass. The key stays in the owner's environment. Putting Jev inside the app would need a paid API on a phone, which the zero-cost rule forbids (docs/00 ADR-002); if a free tier ever covers it, the first in-app use would be ranking convoy stop suggestions by how well they fit the group.

## 8a. Baseline (2026-11-03, before the pass)

Jev scored eleven screen states as described in `12-ux-audit.md` (0–3 per dimension, `tools/ux/out/screens_before_scores.md`):

| Dimension | Mean | Worst |
| --- | --- | --- |
| Hierarchy | 1.70 | first run 1.34 |
| Cognitive load | 1.49 | convoy detail 0.98 |
| Waze feel | 1.22 | settings 0.00, badges 0.62 |
| Kith feel | 0.94 | first run 0.41, league 0.52 |
| One-second glanceability | 0.69 | settings 0.01, badges 0.24 |

Copy: 1,018 distinct strings, 140 flagged (38 technical, 99 unclear, 2 tone, 1 too long), average voice 1.06.

Targets for the pass: screen mean above 2.2, Kith at or above 2.0 everywhere, glanceability at or above 2.0 on Drive recording, convoy detail, radio and stops; zero technical strings, under ten flagged, voice above 2.0.

## 9. Rebrand hand-off

The rebrand changes `DrivalryTheme` (seed colours, surfaces), `DrivalryType` (families and scale), the mark painter and the store art. It does not touch layout, components, motion or copy. Checklist for whoever lands it: update `lib/app/theme.dart`, `lib/app/ui/typography.dart`, bundle fonts in `pubspec.yaml`, redraw `lib/app/brand/drivalry_mark.dart`, run `DRIVALRY_ART=1 flutter test test/art` to regenerate icons and screenshots, and re-run the Jev screen audit.

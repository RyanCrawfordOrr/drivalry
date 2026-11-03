# Drivalry: Game Design

> The scoring rules here are implemented twice: `packages/scoring` (TypeScript, the executable spec) and `packages/drivalry_scoring` (Dart, what the app runs on the phone). Both must pass the JSON fixtures in `packages/scoring/fixtures/`. If this doc and the fixtures disagree, the fixtures win and this doc needs updating. The numbers below are first guesses. They get tuned after two weeks of real trips, and the doc, the fixtures and both ports change together.

## 1. Design goals

1. A better driver must beat a worse driver who drives more.
2. Nothing in the system should feel better when you go faster.
3. Feedback has to be *specific* ("43 in a 30 for 2 min on Elm St") or it is noise.
4. The mean stuff has to be funny to the person receiving it on a good day, and sting on a bad one. Never cruel.
5. Simple enough that a user can explain the score to a friend in one sentence: *"It's 100 minus points for speeding, slamming the pedals, touching your phone, and wasting gas."*

## 2. Units and inputs

Everything internal is SI (m, s, m/s, m/s²). UI converts to the user's locale.

Per trip the engine receives:

- `samples[]`: `{ t, lat, lon, speed, accuracy, heading? }` at ~1 Hz while moving.
- `segments[]`: map-matched road segments `{ fromIdx, toIdx, speedLimit | null, confidence 0–1, roadClass, name?, wayId? }` produced on the phone after the trip by matching the trace against the regional speed-limit pack (see architecture).
- `phoneEvents[]`: `{ t, kind: 'unlock' | 'interaction' | 'call_handheld' }` from the OS while a trip is active.
- `motionEvents[]` (optional, from the accelerometer pipeline): `{ t, kind: 'brake' | 'accel' | 'corner', peak }`. If absent, the engine derives brake/accel events from GPS speed deltas and cornering from heading change × speed.
- `context`: `{ nightFraction, weather?: 'rain' | 'snow' | 'clear', vehicleId }`.

Everything above lives on the phone. The engine's output (score, components, events with road names, XP, roast) is what gets uploaded.

## 3. Events

Events are what the user sees pinned on the map and what roasts are built from.

| Event | Detection | Severity levels |
| --- | --- | --- |
| **Speeding** | Speed exceeds limit by margin for ≥ 8 s continuous on segments with confidence ≥ 0.7. Episodes merge if gap < 10 s. | Minor: +5–9 mph over · Moderate: +10–14 · Major: +15–24 · Reckless: +25 or ≥ 100 mph anywhere |
| **Harsh brake** | Decel ≥ 3.5 m/s² sustained ≥ 0.7 s (or motion-event peak ≥ 3.5) | Moderate ≥ 3.5 · Severe ≥ 5.0 |
| **Harsh accel** | Accel ≥ 3.0 m/s² sustained ≥ 0.7 s | Moderate ≥ 3.0 · Severe ≥ 4.5 |
| **Hard corner** | Lateral accel (speed × heading-rate) ≥ 4.0 m/s² | Moderate ≥ 4.0 · Severe ≥ 6.0 |
| **Phone handling** | Unlock or interaction while speed > 5 m/s (11 mph). Interactions within 20 s merge into one episode. Hands-free calls, CarPlay/AA, and mounted-navigation taps are *not* counted (OS tells us the screen is projecting). | Minor: < 10 s · Moderate: 10–45 s · Major: > 45 s or at ≥ 60 mph |
| **Idling** | Speed < 0.5 m/s for > 120 s mid-trip (trip start/end excluded). We cannot see the ignition, so this is scored lightly. | n/a |
| **High-speed cruise** | Speed ≥ 75 mph (33.5 m/s) regardless of limit. Fuel burn climbs steeply here. Efficiency only, no roast if under the limit. | n/a |

Speeding on a low-confidence segment (no limit in the pack, or a limit the pack is unsure of) is recorded as an *observation* in the trip detail but never scores or roasts. The user can tap "limit is wrong here" to submit a correction.

## 4. Drive Score (0–100)

```
score = 100 − speedPenalty − smoothnessPenalty − attentionPenalty − efficiencyPenalty
```

Each component is capped so one bad category can't zero the trip by itself, except the Reckless flag.

### 4.1 Speed Discipline (cap 40)

Penalty per episode = `weight(severity) × min(duration, 300 s) / 60`:

| Severity | weight / minute |
| --- | --- |
| Minor | 1.0 |
| Moderate | 2.5 |
| Major | 6.0 |
| Reckless | triggers flag (below) and 12.0 |

Plus a *proportion* term so one long cruise at +8 over is still visible: `+ 15 × (seconds over limit / moving seconds)`.

### 4.2 Smoothness (cap 30)

Per 10 km of driving (normalized so a long highway trip isn't punished for having more opportunities):

- Harsh brake: moderate 2.0, severe 4.0
- Harsh accel: moderate 1.5, severe 3.0
- Hard corner: moderate 1.5, severe 3.0

`penalty = Σ(event weights) × (10 km / max(distance, 3 km))`. Trips under 3 km are normalized as if 3 km so a single stop-sign slam on a short hop isn't a 30-point hit.

### 4.3 Attention (cap 30)

Phone handling: minor 3, moderate 7, major 12 per episode. Any episode at ≥ 60 mph (26.8 m/s) is automatically Major.

### 4.4 Efficiency (cap 15)

- Idling: 0.5 per minute (pro-rated) over the 2-minute threshold, cap 4.
- High-speed cruise: 1.0 per minute ≥ 75 mph, cap 6.
- Aggression tax: 0.5 per harsh accel (already counted in smoothness, but it costs fuel too), cap 5.

### 4.5 The Reckless flag

Any of:

- A Reckless-severity speeding episode (+25 over for ≥ 8 s, or ≥ 100 mph for ≥ 3 s on any road).
- Phone-handling Major episode while ≥ 60 mph for ≥ 60 s.
- Three or more Severe brake/corner events in one trip combined with a Major speeding episode (the "driving like you're being chased" pattern).

Effects: score is capped at 25, XP is 0, clean-trip and phone-free streaks reset, the trip card gets the stamp, and a Wall of Shame post goes to every group the driver belongs to (unless the driver is hiding in that group).

### 4.6 Minimums

Trips under 1 km or under 2 minutes of moving time are logged but not scored ("too short to judge").

## 5. XP

```
xp = baseline(score) × distanceFactor × contextBonus
```

- `baseline(score)`: 0 below 50; linear 50→100 maps to 10→100 XP. A perfect trip is 100 XP; a mediocre 70 is 46 XP.
- `distanceFactor`: `min(1.0, 0.4 + 0.6 × creditedKm / 15)`. A 15 km trip gets full credit; a 3 km hop gets ~52%. **Daily credited distance is capped at 100 km.** Beyond that, trips still count for stats and streaks but XP uses `distanceFactor` of 0.4. This is the quality-over-quantity rule.
- `contextBonus`: ×1.10 if night fraction ≥ 0.5 and score ≥ 85 (safe night driving is harder); ×1.10 for rain/snow and score ≥ 85. Max ×1.2.

Streak bonuses are separate: +5 XP per trip while on a ≥ 5-trip clean streak, +10 while ≥ 20.

## 6. Driver Rating

Rolling 30-day average of trip scores weighted by `creditedKm`, displayed on the profile with a tier color. A user needs 5 scored trips to have a rating. Rating is what global leagues use for matchmaking.

## 7. Leagues

- Monday 00:00 local → Sunday 23:59 local. XP accumulates; ties broken by Driver Rating.
- Up to 30 members. Friend leagues are invite-based and never shuffle. Global leagues are matchmade weekly by tier and rating.
- Tiers: Learner → Bronze → Silver → Gold → Platinum → Diamond → Chauffeur. Top 5 promote, bottom 5 demote (bottom 3 in Learner can't demote; Chauffeur has no promotion, just a crown and a weekly "Chauffeur of the Week").
- A member with zero scored trips in a week auto-demotes (and sees "Didn't drive? That's fine. The league didn't wait.").
- **Duels**: 1v1 for a week on XP, Drive Score average, or phone-free trips. Loser wears a 7-day badge chosen by the winner from a fixed list ("Sunday Driver", "Lead Foot", "Butterfingers").
- The weekly rollover is a Postgres function that any member's phone can trigger after the week ends. It is idempotent, so it does not matter who calls it first.

## 8. Badges

Badges are permanent; some have tiers (bronze/silver/gold by count).

**Driving quality**
- *Smooth Operator*: 10/50/200 trips with zero smoothness events
- *Zen Master*: 25 consecutive trips scoring ≥ 90
- *Phone Down*: 7/30/100 days with zero phone-handling events
- *Grandma Mode*: a trip ≥ 20 km with zero events of any kind
- *Rain Dancer*: 10 trips in rain scoring ≥ 85
- *Night Shift*: 10 night trips scoring ≥ 85
- *Reformed*: Driver Rating improved by 15+ points over 30 days
- *Hypermiler*: 10 trips with zero efficiency penalty over 30 km

**Exploration (never speed or time-based)**
- *State Collector*: 5/15/30 states or provinces
- *County Line*: 25/100/500 counties
- *Century Club*: a single trip ≥ 100 miles (scored ≥ 70)
- *Summit*: a trip reaching ≥ 2,000 m / 3,000 m / 4,000 m altitude
- *Far From Home*: 500 / 1,500 / 3,000 km from home
- *Groundhog*: the same route 50 times

**Social**
- *Convoy Captain*: lead 3/10/25 convoys
- *Road Trip Legend*: a convoy ≥ 500 miles
- *Wingman*: ride passenger on 10 friends' trips
- *Clean Crew*: your circle completes a group challenge
- *Snitch*: report 10 wrong speed limits that get confirmed by a second flag (positive framing: you fixed the map)

**Dishonorable (shown on the profile for 7 days, then archived to a private "History" tab)**
- *Lead Foot*: a Reckless trip
- *Butterfingers*: 5 phone-handling episodes in a week
- *Whack-a-Mole*: 10 harsh brakes in one trip
- *Sunday Driver*: duel loser's default

Exploration badges are evaluated on the phone, because only the phone knows where you went. The phone uploads the badge, not the places.

## 9. Roasts and praise

### 9.1 Principles

- Target the drive, not the driver. "That lane change" not "you idiot".
- Be specific: include the number, the road, the duration. Specificity is what makes it land.
- Include the *cost*: seconds saved, ticket risk, fuel burned. The joke is that it wasn't worth it.
- Hard floor: never reference crashes, death, injury, alcohol, other road users getting hurt, or anything that could read as a dare. Never roast a trip flagged as a possible crash. Never roast a passenger trip.
- Praise is as specific as roasts. "Butter smooth. 23 miles, zero events, 71 seconds of total phone time: zero."
- Fixed library only. No generated text, ever. If the library has no line for a situation, the card shows the facts and no roast.

### 9.2 Tone

The library holds three tones per `(eventKind, severity, context)` key. Tone is **not** a user setting.

| Tone | Used for | Example for +12 over for 3 min |
| --- | --- | --- |
| **Gentle** | The factual line under each event in the trip timeline, and the wording of spoken cues | "You were 12 over on Route 9 for about 3 minutes. That saved roughly 40 seconds." |
| **Sassy** | Kept in the library; not shown anywhere today | "12 over on Route 9 for 3 minutes. You saved 40 seconds. Hope the 40 seconds were incredible." |
| **Savage** | The public roast: feed post, trip card headline, notification | "Route 9, 3 minutes, 12 over, to save 40 seconds. A whole league of your friends can see this. They're not impressed, they're just looking." |

Templates are human-written and keyed on `(eventKind, severity, context)` with slot-fill for numbers and road names. They are selected deterministically from a seed (trip id) so a trip card always shows the same roast. The TypeScript library lives in `packages/scoring/src/roast/templates.ts`; the Dart port carries the same templates with the same ids. The uploaded summary carries the rendered line plus `{ templateId, slots }`. Copywriting is an ongoing content job.

### 9.3 Public roasts (every group)

- The roast line is posted to the feed of every league and circle the driver belongs to, together with the trip card. Friends can react and comment.
- Reckless trips go on the week's **Wall of Shame** (feed post, pinned until Sunday).
- Members get a *Snitch* reaction they can drop on a speeding event.
- There is no group-level switch. Every group is mean. The only opt-out is the per-member **hiding** toggle, set per group. While hiding, your trips post score only, and the group sees a "hiding" marker next to your name.

### 9.4 Spoken cues (opt-in, off by default)

Short, non-judgmental while driving (safety first): "Limit's 35." / "Easy on the brakes." / "Smooth." The roast waits until the trip ends. Cues are rate-limited to one per 60 s and spoken by the phone's own TTS. They need the speed limit during the trip, which the on-device pack provides without any network.

## 10. Convoy awards

Computed per convoy from members' trip summaries over the convoy window, on each member's phone, and posted to the convoy recap:

- *Smoothest*: highest smoothness component average
- *Navigator*: fewest deviations from the convoy route (each phone measures its own)
- *DJ*: most queued tracks that weren't skipped (Convoy DJ only)
- *Pit Boss*: most stop proposals that won a vote
- *Lead Foot* (dishonorable): most speeding minutes. Shown, not celebrated: the card says "Lead Foot (not a compliment)".

## 11. Anti-gaming

- Passenger mode is honor-system for friends but *passenger trips cannot raise your rating*, only be excluded, so marking a bad trip as passenger is the only exploit and it simply removes the trip. Groups see the count of passenger-marked trips per member.
- Low-accuracy GPS stretches (accuracy > 50 m) are excluded from speeding detection in both directions.
- The daily distance cap stops "drive more to win".
- Deleting a trip removes its XP.
- Reckless-flag thresholds are intentionally high so false positives are rare. A flagged trip can be re-scored once per month with a stricter second pass on the phone. The raw trace never leaves the device, so there is no human review.
- Scores are computed on the driver's own phone, so a modified client could upload a fake summary. We accept this. It is a game among friends, and a friend with a suspiciously perfect month will be asked about it in the comments. We do not build anti-cheat.

## 12. League depth: duels, group challenges, seasons, global leagues

All four are computed from the summaries phones already upload (`trip_summaries`, `trip_events`), live in `supabase/migrations/0007_duels_challenges_seasons.sql`, and rank by XP, Drive Score, phone-free trips or participation. Never by speed, never by distance.

### 12.1 Duels

- A friend challenges a friend on one metric: **XP** (sum over scored driver trips), **Drive Score** (average; fewer than three trips forfeits with 0), or **phone-free trips** (scored trips with no `phone_handling` event).
- The week starts when the opponent accepts and runs seven days. Unanswered challenges expire after seven days. One open duel per pair.
- Either phone settles a finished duel (`finalize_duel`, idempotent); the daily cron is the backstop. A tie has no winner.
- The winner picks the loser's badge from the fixed list (Sunday Driver, Lead Foot, Butterfingers); it is written to `user_badges` with a seven-day `expires_at` by `pick_duel_badge`. A winner who has not picked within three days gets Sunday Driver chosen for them.
- Duels are visible only to the two participants. Phones compute the live scoreboard themselves from both drivers' summaries, exactly as the server function does.

### 12.2 Group challenges

- One league, one goal, one or two weeks; one running challenge per league at a time. Goals: **clean trips** (80+, the clean-trip score, not reckless, league total), **phone-free trips** (league total), **average score** (over every member trip), **everyone drives** (every member logs at least N scored trips).
- Progress is computed on the phone from members' summaries (`computeChallengeProgress`), and by `finalize_group_challenge` on the server when the window closes. Success gives every current member the goal's badge: Clean Sweep, Hands Off Together, Class Act, Full House.
- The creator can call a running challenge off; nobody gets a badge.

### 12.3 Seasons

- A season is a calendar quarter (seeded 2026-Q4 to 2027-Q4). The Leagues tab shows the running season, days left and this phone's numbers; Season Wrapped is built from the phone's own trips.
- When a season ends, the phone writes one `season_results` row per account (trips, XP, average score, clean and phone-free counts, best score, best tier, duels won and lost, a one-line headline). Counts only, no places. A season with no scored trip on the phone (before the driver had the app) writes no row and is listed as "Before you joined". `season_1` is awarded for at least one scored trip in the first season.

### 12.4 Global leagues

- `join_global_league()` puts you in the pool and seats you at once in this week's open global league at your tier with room (else a new one). Every Monday 06:10 UTC, after the rollover, `matchmake_global_leagues()` carries the new tiers to the pool, drops players with no scored trips in four weeks, marks last week's tables closed (`leagues.closed_at`) and builds fresh ones per tier in even groups of at most 30 ordered by Driver Rating. Closed tables keep their members and their `league_weeks` row, so the week badges (`league_week`, `promoted`) are awarded from `league_weeks` directly whenever the phone next opens the Leagues tab, league listed or not; closed tables are pruned after 60 days once no active group challenge references them.
- Same week rules as a friend league (XP ranks, rating breaks ties, top five up, bottom five down, no-drive demotes). Hiding works the same. Global leagues have no owner and no usable invite code; `leave_global_league()` leaves the pool and the tier is kept for a later rejoin.
- Group challenges run in friend leagues only (the insert policy checks `kind = 'friend'`); a global table is replaced weekly and would not outlive a 14-day goal. Joining shows your weekly XP and scored-trip posts to that week's league-mates, as any league does.


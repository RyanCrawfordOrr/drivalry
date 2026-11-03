# Drivalry: Roadmap

An ordered build plan for one person and Claude Code. The owner chose to build all the features, in this order, with no stage gates. Each stage ends with something installable on the seven test phones (5 iPhones, 2 Android) through TestFlight and Play internal testing. The tracking quality bar in Stage 1 is a bar we measure against, not a gate that blocks later stages.

## Stage 0: Foundations (now)

- [x] Product spec, game design, architecture, platform constraints, privacy lines, decision log (`docs/`)
- [x] Scoring engine with tests (`packages/scoring`)
- [x] Flutter app skeleton (`app/`), bundle id `app.drivalry`
- [x] Supabase project created; Google Cloud project `drivalry` with Maps SDK, Places (New) and Routes enabled, hard daily quotas set, key in `.env`
- [x] Delete the old Expo app and update the README to match these docs
- [x] `packages/scoring` emits JSON fixtures into `packages/scoring/fixtures/` (`npm run fixtures`)
- [x] `packages/drivalry_scoring` Dart port passes every fixture
- [x] `tools/packs`: pyosmium builder produces one pack (the owner's home state) under 60 MB
- [x] GitHub Actions workflows: `ci.yml` (TypeScript spec, Dart port, Flutter analyze and test) and `supabase-keepalive.yml` (daily ping that reads the one-row `heartbeat` table; needs `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` as repo secrets)
- [x] GitHub Actions: `packs-monthly.yml` builds every US state and publishes a release with `index.json` (first release `packs-2026.11`: 52 packs, 1.1 GB; TX and CA over the 60 MB target)
- [x] Supabase schema rewritten for summaries only (no `trip_samples`, `trip_segments`, `convoy_positions`, `share_level`); RLS; `finalize_league_week` function
- [ ] Request the CarPlay Driving Task entitlement (and Voice Conversation) for `app.drivalry`
- [ ] First Mac build: hello-world Flutter app signed and uploaded to TestFlight, Android build to Play internal testing
- [ ] Attribution screen stub listing OpenStreetMap, Google, Open-Meteo, Nominatim

## Stage 1: Tracking and scoring ("It scores my drives")

Goal: trips on the owner's phones start and stop with no taps, get matched against the pack, scored on the phone, and show the right roads with the right roast.

Milestones:

1. **M1.1 Native tracking plugins.** _Built 2026-11-02 (Kotlin compiled; Swift unverified until the Mac build)._ Swift (CoreMotion, CoreLocation) and Kotlin (ActivityRecognition receiver, `location` foreground service, FusedLocationProvider with batched delivery). Trip state machine runs natively (ADR-017): idle, tentative, active, ended; Dart mirrors it and drains the spool. Works from a terminated app on both platforms.
2. **M1.2 Recorder.** _Built 2026-11-02._ drift schema for trips, samples, motion events, phone events. 20 Hz sensor batches turned into brake/accel/corner events on-device. 90-day TTL on samples. Weather from Open-Meteo at trip start.
3. **M1.3 Pack download and matcher.** _Built 2026-11-02; the ten-route check is still to do on real drives._ Pack manager (Wi-Fi only, hash check, atomic swap). Nearest-road-with-heading matcher in an isolate. Correct road names on ten known routes around the owner's home.
4. **M1.4 Scoring on the phone.** _Built 2026-11-02; "never track" vehicles wait for the Garage._ Dart engine wired to matcher output. Trip card: map, score ring, components, event timeline with pins, limit coverage, roast line. "Were you the passenger?" interstitial with hints. Delete trip. Pause tracking. "Never track" vehicles.
5. **M1.5 Diagnostics.** _First version built 2026-11-02 (plugin state, counters, errors, packs, DB counts); battery per hour/day measurement still to add._ Settings > Diagnostics shows battery per hour driving, battery per day parked, missed starts, false starts, late ends, and limit coverage. All measured on the phone.
6. **M1.6 Seven phones.** TestFlight and Play internal builds on all test devices. Two weeks of real trips.
7. **M1.7 Tune.** After the two weeks, adjust the numbers in `02-game-design.md`, regenerate fixtures, update both engines together.

**Tracking quality bar** (measured, not gated):

- Drives start and stop with no taps. Target > 95% starts, > 98% ends.
- Under 6% battery per hour while driving.
- Under 1% battery per day parked.
- Every trip scored on-device against the pack, with no network.
- The trip card names the right roads and shows the right roast on the ten known routes.

## Stage 2: Friends, leagues and public roasts ("The league")

1. **M2.1 Auth and profiles.** _Built 2026-11-03 (native Apple + Google id-token flows; owner must configure providers per docs/09)._ Sign in with Apple and Google. Handles, avatars (≤ 100 KB in Storage). Account deletion and export.
2. **M2.2 Summary upload.** _Built 2026-11-03 (outbox worker, hash-based re-upload)._ Outbox worker. `trip_summaries` and `trip_events` rows. Profile shows Driver Rating and headline stats.
3. **M2.3 Friends and leagues.** _Built 2026-11-03 (friends by handle/link/QR; leagues create/join/standings/rollover call)._ Friend requests by handle, link, QR. Friend leagues up to 30, Monday to Sunday, tiers, promotion and demotion via `finalize_league_week`. Standings screen.
4. **M2.4 Public feed.** _Built 2026-11-03 (feed, reactions incl. Snitch, comments, Fame/Shame filters, per-league hiding)._ Trip cards with the roast line posted to every league and circle feed. Reactions, comments, Snitch reaction. Wall of Fame and Wall of Shame. Per-group hiding toggle, visible to the group. Passenger-marked count on the profile.
5. **M2.5 Badges and streaks.** _Built 2026-11-03 (20 badges, on-phone engine, streaks provider)._ First 20 badges, clean and phone-free streaks. Exploration badges computed on the phone.
6. **M2.6 Push.** _Built 2026-11-03 (FCM via programmatic Firebase options, local notifications, quiet hours; Edge Function `supabase/functions/push` unverified until deployed)._ `push_tokens`, database webhooks, one Edge Function sending through APNs and FCM. Trip scored, league events, quiet hours.
7. **M2.7 Shareable trip card image** (no route map). _Built 2026-11-03._
8. **M2.8 Speed-limit corrections.** _Built 2026-11-03 (flags sync, daily override pull applied at match time; Snitch badge awarded on confirmation still to wire)._ "Limit is wrong here" flags; trigger that creates overrides on two agreeing flags; daily override pull; Snitch badge.

## Stage 3: Circles ("The Life360 part")

1. **M3.1 Presence.** _Pulled into Stage 2 by ADR-018 and built 2026-11-03 (30 s while driving, parkedFix while parked, app-open refresh)._ Upsert every 30 s driving, significant change parked, nothing while hiding. RLS honours `hiding`.
2. **M3.2 Live circle map** on Google Maps: _Built 2026-11-03 as the friends map at the top of the Drive tab (friends + circle members); circles themselves still to build._ positions, driving-now, battery, last seen. Subscribed only while on screen.
3. **M3.3 Places and alerts.** Saved places on the phone; arrive/leave alerts computed from presence on the viewer's phone; quiet hours. Check-ins. Driving status and OS driving-mode auto-reply where available.
4. **M3.4 Crash detection.** Accelerometer spike plus stop plus no movement; 30 s countdown; push to emergency contacts who use Drivalry; pre-filled SMS for the rest; never an automatic call. Candidate crash trips excluded from scoring.
5. **M3.5 Parking memory** with photo and walking route back.
6. **M3.6 Garage.** Vehicles by Bluetooth name, per-vehicle stats, fuel log and true MPG, maintenance reminders, local encrypted documents.

## Stage 4: Convoys ("Road trip mode")

1. **M4.1 Create and join.** 2–6 cars, invite by link, QR or circle, shared destination and stops. Realtime `convoy:{id}` channel.
2. **M4.2 Radio.** flutter_webrtc full mesh, signaling over the convoy channel, STUN and TURN from Metered Open Relay. PTT button, iOS `PushToTalk` framework, Android foreground service. Siri and Assistant shortcuts.
3. **M4.3 Convoy map.** Positions every 3–5 s over the data channel with a 15 s Realtime fallback. Leader, gaps, ETAs from Routes (300/day cap, straight-line past the cap). Regroup pin. Lost-sheep alert.
4. **M4.4 Stops.** Propose, vote, Places suggestions along the route (150/day cap, manual pins past the cap).
5. **M4.5 Music.** Spotify Jam and Apple Music SharePlay deep links. Convoy DJ over the data channel with allowlisted Spotify users.
6. **M4.6 Chat, games, cost split, album.** Voice-note chat read aloud to drivers. Passenger games. Expense log with settle-up deep links. Small photos, per-convoy cap, 30-day TTL.
7. **M4.7 Recap.** Built on each phone from received positions, the planned route and members' summaries. Awards. Shareable video.

## Stage 5: In the car

1. **M5.1 Without entitlements.** iOS Live Activity and Dynamic Island (Swift, WidgetKit). Android ongoing notification. Spoken cues via on-device TTS, off by default, live matching every 5 s against the pack.
2. **M5.2 CarPlay** with `flutter_carplay` once the Driving Task entitlement arrives: Drive, Convoy, Talk, Stops tabs. If Apple refuses, M5.1 is the iOS in-car experience and we stop here on iOS.
3. **M5.3 Android Auto.** Kotlin `CarAppService` in the POI category: Convoy, Stops, Drive, Talk. Desktop Head Unit testing. Play car-app review.

## After Stage 5: depth

- Seasons and Season Wrapped; county and state fill-in map.
- Global leagues with matchmaking (Postgres function), duels, group challenges.
- OBD-II dongle support for real fuel data.
- More packs: Canadian provinces, then countries, as users appear.
- Second pass on the matcher if the wrong-road rate on dense grids demands it.

## Ongoing

- Monthly pack rebuild on GitHub Actions; keep the last three releases.
- Daily Supabase keep-awake ping.
- Before every release: check each free allowance in `03-architecture.md` §10 against the provider's current pricing page, and confirm the Google quota caps are still set.
- Roast library copywriting, reviewed by a human and the banned-word test.

## Things that are expensive to change

1. **Pack schema version.** Every installed phone has to understand it. Bump the version and keep readers for the old one for a release.
2. **Trip summary schema.** Append fields, never rename. Old summaries are forever.
3. **Supabase schema and RLS.** Migrate forward only; the free tier has no point-in-time recovery to fall back on.
4. **Geohash precision** for tiles. Changing it means rebuilding every pack.
5. **Bundle id `app.drivalry`** and the Sign in with Apple / Google client ids tied to it.

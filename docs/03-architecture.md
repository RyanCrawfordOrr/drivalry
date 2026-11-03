# Drivalry: Architecture

> Local-first, zero-cost. The phone does the work. The cloud keeps score. Nothing we run has a bill. Decisions behind this are in `00-decisions.md`.

## 1. Shape of the system

```
┌──────────────────────────── Phone (Flutter, app/) ─────────────────────────────┐
│                                                                                │
│  Native tracking plugins (Swift / Kotlin)                                      │
│    motion triggers · GPS 1 Hz batched · accel/gyro 20 Hz · phone events        │
│          │                                                                     │
│          ▼                                                                     │
│  Trip Recorder ──► drift (SQLite)                                              │
│                     raw samples (90 days) · events · trips · summaries · outbox │
│          │                                                                     │
│          ▼  (trip end, in an isolate)                                          │
│  Matcher ◄── Pack Store (regional speed-limit packs + shared overrides cache)   │
│          │                                                                     │
│          ▼                                                                     │
│  Scoring (packages/drivalry_scoring) + fixed roast library                     │
│          │                                                                     │
│          ▼                                                                     │
│  Summary (no coordinates) ──► outbox ──► Supabase                              │
│                                                                                │
│  UI: Riverpod · go_router · google_maps_flutter · flutter_tts                  │
│  Live Activity / ongoing notification · CarPlay (later) · Android Auto (Kotlin)│
│  Convoy: WebRTC mesh (audio + data channel), flutter_webrtc                    │
└───────┬──────────────────────────┬──────────────────────────┬──────────────────┘
        │ HTTPS + WebSocket        │ HTTPS                    │ HTTPS
┌───────▼──────────────┐  ┌────────▼───────────────┐  ┌───────▼──────────────────┐
│ Supabase (free tier)  │  │ Google Maps Platform   │  │ GitHub                   │
│  Auth: Apple, Google  │  │  Maps SDK (no-cost)    │  │  Releases: speed-limit   │
│  Postgres + RLS       │  │  Places (New) 150/day  │  │   packs, index.json      │
│  Realtime: presence,  │  │  Routes 300/day        │  │  Actions: monthly pack   │
│   convoy signaling    │  └────────────────────────┘  │   build, daily Supabase  │
│  Storage: small images│                              │   keep-awake ping        │
│  Edge Fn: push fan-out│  Also: Open-Meteo · Nominatim│  Repo: public, MIT       │
└───────────────────────┘  Metered Open Relay (TURN)   └──────────────────────────┘
                           Spotify Web API · APNs · FCM
```

No component in this diagram is a server we operate. Supabase hosts the database and functions. GitHub runs the batch jobs. Everything else is a phone.

## 2. Principles

1. **Local-first.** Recording, map matching and scoring happen on the phone. A trip is scored with no network. The cloud holds summaries so friends can compare.
2. **Raw GPS never leaves the phone.** It is kept 90 days locally for the trip map, the appeal re-score and GPX export, then deleted. The summary carries road names for events and nothing with coordinates.
3. **Zero cost.** Every external service has a free allowance, a cap below it, and a documented degradation (§10). We never pay to upgrade a tier.
4. **Boring native code.** Swift and Kotlin only where the OS requires it: tracking, Live Activities, PushToTalk, Android Auto. Everything else is Dart, written on Windows.

## 3. On-device pipeline

```
Motion trigger ──► Tentative ──► Active ──► Ending ──► Passenger? ──► Match ──► Score ──► Upload
 (OS says          (GPS on,      (1 Hz GPS,  (3 min       (interstitial,  (pack,    (Dart     (summary
  "in vehicle",     confirm       20 Hz       stationary    pre-answered    isolate)  engine)   via outbox)
  BT/CarPlay/AA     > 4 m/s       sensors,    or motion     from hints)
  connected)        for 20 s)     phone evts) exit + BT off)
```

### 3.1 Detect

- iOS: `CMMotionActivityManager` `automotive` transitions. Backstops: significant-location-change and a 100 m geofence around the last parking spot. Both can launch the app from a terminated state.
- Android: `ActivityRecognition` Transition API `IN_VEHICLE ENTER` through a `BroadcastReceiver`, so it works after the app is killed. Backstops: fused location `PRIORITY_PASSIVE` and a geofence around the parking spot.
- Both: car Bluetooth connection, CarPlay session, or Android Auto session starts a *tentative* trip immediately. Tentative becomes active when speed exceeds 4 m/s for 20 s. Otherwise it is discarded with no trace.
- The idle → tentative → active → ended state machine runs **natively**, because it has to gate the GPS radio while the Dart side may not be running (Android kills the app; iOS relaunches it in the background). Every event the plugin emits is also appended to an on-device spool file, and Dart drains the spool when it next runs, so a trip recorded while the app was dead is replayed in full. The channel contract is `08-tracking-channel.md`.

### 3.2 Record

- GPS at 1 Hz, batched delivery (§6). Each fix: `t, lat, lon, speed, accuracy, heading, altitude`.
- Linear acceleration at 20 Hz from the motion coprocessor, FIFO-batched. The plugin keeps only per-second peaks above 2.5 m/s² (`accelPeak`), which corroborate the GPS-derived brake, accel and corner events the engine detects and will feed crash detection. Phone orientation is unknown, so the plugin does not try to classify the direction of a peak. Raw motion data is discarded after each batch.
- Phone events: unlock, interaction, handheld call, and whether the screen is projecting to CarPlay or Android Auto. Timestamps only.
- Weather at trip start from Open-Meteo (one call). Night fraction from local sunrise/sunset math.
- Everything is appended to drift as it happens, so a killed app loses at most one batch (about 20 s).

### 3.3 End and ask

- Trip ends after 3 minutes stationary, or `automotive` exit plus Bluetooth disconnect.
- Passenger hints collected during the trip: car Bluetooth name not in the garage; handheld call while moving; another circle member's active trip within 50 m at the same time.
- The "Were you the passenger?" interstitial shows on the next app open or as an actionable notification. It is pre-answered from the hints. Passenger trips skip scoring and roasting.

### 3.4 Match

The matcher runs in a Dart isolate against the regional pack (§4) and produces the `RoadSegment[]` input the engine expects. Details in §5. It also computes **limit coverage**: moving seconds on segments with confidence ≥ 0.7 divided by moving seconds. Coverage is shown on the trip card and uploaded with the summary.

### 3.5 Score

`packages/drivalry_scoring`, the Dart port of `packages/scoring`, runs the rules in `02-game-design.md`. Output: score, components, events with road names, flags, XP, roast as `{ templateId, slots }` plus the rendered line. Both ports pass the same fixtures in `packages/scoring/fixtures/`.

### 3.6 Upload

A trip summary is roughly 5–20 KB of JSON:

```
{ id, startedAt, endedAt, distanceM, movingS, score,
  components: { speed, smoothness, attention, efficiency },
  reckless, xp, creditedKm, isPassenger, vehicleLabel,
  packRegion, packVersion, limitCoverage, nightFraction, weather,
  events: [{ kind, severity, offsetS, durationS, overMps?, roadName?, wayId? }],
  roast: { templateId, slots, text } }
```

No coordinates. No start or end place. No route. It goes into the outbox and uploads on any network. Everything the feed shows is derived from this.

## 4. Speed-limit packs

### 4.1 Build (`tools/packs`)

- Python with pyosmium. Input: Geofabrik extracts per region (US states first, then Canadian provinces, then countries).
- Keep ways with a driveable `highway` tag. Parse `maxspeed`, `maxspeed:forward`, `maxspeed:backward`, `maxspeed:type`, `oneway`, `name`. Normalise to km/h.
- Confidence: numeric `maxspeed` tag 0.9; implied by `maxspeed:type` or a road-class default 0.5; nothing 0.
- Simplify geometry to 2 m (Douglas-Peucker). Clip ways into geohash cells.
- Target under 60 MB per pack. Large states (Texas, California) may need to drop `service` and `track` ways to fit. Measure first.
- Runs monthly on GitHub Actions as a matrix over regions. Output: one pack per region plus `index.json` on a GitHub Release tagged `packs-YYYY.MM`. Keep the last three releases.

### 4.2 Format

The exact bytes are specified in `07-pack-format.md` (schema 1). In outline: one SQLite file per region, opened read-only.

```
meta    (key TEXT PRIMARY KEY, value TEXT)
          schema_version, region, osm_replication_timestamp, built_at, way_count, tile_count, bbox
tiles   (geohash TEXT PRIMARY KEY, ways BLOB)
          geohash precision 5 (about 4.9 km × 4.9 km); blob is zlib over a compact varint stream
names   (name_id INTEGER PRIMARY KEY, name TEXT)
          deduplicated street names, sorted, 1-based

Each way inside a tile blob: way id, road class 0..8, name id, forward limit, backward limit
(when different), flags (oneway direction, limit source, mph vs km/h, roundabout), then the
simplified polyline as zigzag-varint deltas at 1e-6 degrees. Limits are stored in the posted
unit (35 mph stays 35 mph); the reader converts to m/s.
```

Two deliberate departures from the first sketch: **zlib and hand-rolled varints instead of zstd and CBOR**, because both sides get them for free (`dart:io` and Python's standard library) and the varint stream is smaller than CBOR anyway; and **ways are stored whole in every cell they pass through** rather than clipped, which keeps the builder and the matcher simple at the cost of some duplication of long motorway ways. The reader dedupes by way id when it loads a cell and its eight neighbours.

`index.json` on the release lists `{ region, name, url, bytes, sha256, osmTimestamp, wayCount, bbox }` per pack plus a top-level `schemaVersion`. The app refuses a pack whose `schemaVersion` it does not know. The index is republished every month to a permanent release tagged `packs-index`, so the app always fetches the same URL.

### 4.3 Download

- The app installs the pack for the region containing Home, and any region it detects a trip in.
- Wi-Fi only. Checks `index.json` monthly. Downloads to a temp file, verifies the hash, swaps atomically, keeps the previous pack until the new one is verified.
- No pack for the region: trips are still recorded and scored for smoothness, attention and efficiency. Speed Discipline shows "no speed-limit data here" and the card is silent on speeding.

### 4.4 Shared corrections

- A user taps "limit is wrong here" on an event. The phone inserts a `speed_limit_flags` row: way id, region, suggested km/h, user id.
- A Postgres trigger creates a `speed_limit_overrides` row (confidence 0.85) when two distinct users flag the same way with the same limit.
- Phones pull overrides for their installed regions on pack install and once a day, and apply them on top of the pack at match time.
- A single pending flag drops that way's confidence to 0.5 on the flagging user's phone only, so they stop getting roasted there while the second flag is awaited.
- We never edit OSM automatically.

## 5. Matcher

Nearest road with heading. Deliberately simple; measured, then improved only if the wrong-road rate on known routes demands it.

```
for each sample at 1 Hz:
  candidates = ways from the sample's geohash cell and its 8 neighbours
               whose nearest point is within max(35 m, accuracy)
  cost(way)  = distance_m / 10 + heading_delta_deg / 30
               (oneway ways: heading compared against the allowed direction only)
  keep the current way unless another candidate beats it by a margin for 3 consecutive samples
  samples with accuracy > 50 m, or speed < 2 m/s with no usable heading, inherit the previous way
emit RoadSegment runs { fromIdx, toIdx, speedLimit (m/s), confidence, roadClass, name, wayId }
pick the directional limit (max / maxb) from the travel direction along the way
apply shared overrides by wayId
```

Details fixed by the implementation in `packages/drivalry_packs` (tests pin them): limit coverage counts a sample only when the segment has confidence ≥ 0.7 *and* a limit, time-weighted by the gap to the previous sample clamped to 5 s; while a switch is pending, inaccurate or stationary samples inherit the current way without advancing or resetting the three-sample counter, and when the switch lands the whole pending run is reassigned; with no usable heading the heading term is 0 and the travel direction is inherited; a direction change on the same way (a U-turn) starts a new segment because the limit can differ per direction.

A one-hour trip is about 3,600 samples and matches in about 15 ms in an isolate (measured on a 50-way grid). Tiles for the trip's bounding box are loaded once and kept in memory for the run.

For spoken cues (opt-in) the same matcher runs live every 5 s on the latest fix only, against tiles already cached for the current area. It never touches the network.

## 6. Battery strategy

The rule is simple to state and fiddly to implement: **the GPS radio is on only while the phone is physically in a moving vehicle, and the network radio is used in bursts.**

### 6.1 Parked: about 0% per day

- No GPS. No timers. No wake locks. No foreground service.
- iOS: motion activity transitions, significant-change location, and a geofence around the parking spot. Android: the Transition API receiver, `PRIORITY_PASSIVE`, and a geofence.
- Presence to friends while parked: only on OS-driven significant-change events (several hundred metres). No polling.
- Target: under 1% per day. Measured on the owner's phones through the in-app diagnostics screen.

### 6.2 Driving: under 6% per hour, usually masked by the car charger

- GPS at 1 Hz. Android: `PRIORITY_HIGH_ACCURACY` with `setMaxUpdateDelayMillis` of 10–20 s so fixes arrive in batches and the CPU wakes every 10–20 s rather than every second. iOS: `activityType = .automotiveNavigation`, `allowsBackgroundLocationUpdates`, `pausesLocationUpdatesAutomatically = false` while active; iOS delivers each fix, so the per-fix handler only appends to a memory buffer that is flushed to drift every 20 s.
- Accelerometer and gyro at 20 Hz via FIFO batching (`maxReportLatencyUs` on Android, batched `CMDeviceMotion` on iOS). Event detection runs per batch. Raw motion never leaves the phone and is dropped after detection.
- **No per-point network calls.** No speed-limit lookups mid-trip, no map tiles, no analytics. Scoring happens after the trip.
- Presence: one small upsert every 30 s over the already-open Supabase connection. In a convoy: positions every 3–5 s over the WebRTC data channel to convoy members only.
- Screen stays off unless the user is on the car screen or the Live Activity, both rendered by the OS.
- Trip end: finalize, match, score and upload the summary (5–20 KB) on any network. Photos wait for Wi-Fi or a charger.

### 6.3 Known battery traps to avoid

- Keeping a foreground service or `UIBackgroundModes location` running while parked "to be safe". The motion triggers are reliable enough; trust them.
- Realtime subscriptions with aggressive heartbeats. Use the default (about 30 s) and drop the socket when parked and backgrounded.
- Map SDK instances alive in the background. Dispose the map when the app is backgrounded.
- Android: forgetting `PRIORITY_PASSIVE` for the parked backstop, or requesting background location without the correct foreground-service type (kills battery *and* fails Play review).
- Matching every sample live. Live matching is only for spoken cues, only when enabled, and only every 5 s.

### 6.4 Why our own plugins

The React Native library that implements this model needs a paid Android license. In Flutter the honest options are the same platform APIs wrapped ourselves. The Swift plugin is CoreMotion plus CoreLocation. The Kotlin plugin is ActivityRecognition plus a `location` foreground service plus FusedLocationProvider. geolocator covers foreground use. Both plugins live in `app/ios` and `app/android` and talk to Dart over platform channels.

## 7. Sync model

- **drift is the source of truth on the phone.** Tables: `trips`, `samples` (90-day TTL), `motion_events`, `phone_events`, `segments`, `summaries`, `outbox`, `packs`, `overrides_cache`, plus caches of friends, leagues, feed pages and presence.
- **Outbox.** Every cloud write (summary, reaction, comment, flag, presence, convoy action) is a row with a client-generated UUID. A worker drains it with exponential backoff. All writes are idempotent by UUID, so retries are safe.
- **Push-based pulls.** Feed, leagues and friends are PostgREST queries, page size 20, run when a screen opens and when a push arrives. Results are cached in drift so the app works offline with stale data.
- **Realtime only for what is on screen.** A circle map subscribes to that circle's presence while visible. A convoy subscribes to its channel while active. Nothing else holds a subscription.
- **Presence.** Own row upserted every 30 s while driving, on significant change when parked, never while hiding. Readers get it via Realtime on the open circle map, or via a plain query otherwise.
- **League rollover.** `finalize_league_week(league_id, week_start)` is a Postgres function. Any member's phone that opens a league after Sunday midnight local calls it. It takes a row lock and is idempotent. pg_cron runs it Monday 06:00 UTC as a backstop.
- **Packs and overrides.** Packs from GitHub Releases on Wi-Fi, checked monthly. Overrides pulled per installed region once a day.
- **Keep-awake.** `.github/workflows/supabase-keepalive.yml` runs daily, checks auth health and reads the one-row `heartbeat` table (`supabase/migrations/0000_heartbeat.sql`) through PostgREST, so the free project never pauses for inactivity. It needs only the public URL and publishable key as repo secrets.
- **Conflicts.** There are none worth resolving. Cloud rows are append-only (summaries, posts, reactions, flags) or owner-only upserts (presence, profile, hiding toggle).

## 8. Cloud data model

`supabase/migrations/0001_init.sql` implements this model (rewritten 2026-11-02; the earlier draft with `trip_samples`, `trip_segments`, `convoy_positions` and `share_level` is gone). Tables:

| Table | Holds | Retention |
| --- | --- | --- |
| `profiles` | handle, display name, avatar path, passenger-marked count, global `location_hidden` | account life |
| `friendships` | pairs with status | account life |
| `leagues`, `league_members`, `league_weeks` | membership, tier, weekly standings as JSON | account life |
| `trip_summaries` | the summary in §3.6, one row per trip | account life |
| `trip_events` | kind, severity, offset, duration, over-speed, road name, way id | pruned to score-only after 1 year |
| `feed_posts` | trip, badge, league, convoy, shame posts; roast text plus template id and slots | 90 days |
| `feed_reactions`, `feed_comments` | per post | with the post |
| `badges`, `user_badges` | definitions and awards | account life |
| `circles`, `circle_members` | membership and the `hiding` flag | account life |
| `presence` | one row per user: lat, lon, speed, heading, battery, driving, updated_at | latest only, overwritten |
| `crash_alerts` | lat, lon, time, extra recipient ids (emergency contacts who use Drivalry); insert triggers the push | 24 hours |
| `convoys`, `convoy_members`, `convoy_stops`, `convoy_stop_votes`, `convoy_expenses`, `convoy_photos` | convoy state and recap inputs | 30 days after the convoy ends |
| `speed_limit_flags`, `speed_limit_overrides` | the shared correction cache (§4.4) | indefinite |
| `push_tokens` | APNs and FCM tokens per device | until sign-out |

Row-level security: a user writes only their own rows; reads are scoped to accepted friends and to leagues and circles they belong to (`can_view`); `presence` is readable by accepted friends and circle members, only when the owner is not hiding in that circle and has not set `location_hidden` (ADR-018, `0002_presence_friends_account.sql`). Saved places (Home, Work) and emergency contact phone numbers stay on the phone.

## 9. Realtime, convoys, radio, music

- **Channels.** `presence:circle:{id}` (Postgres changes on `presence` filtered by circle), `convoy:{id}` (broadcast: WebRTC signaling, stop proposals and votes, regroup pins, chat, and a 15 s position fallback), `league:{id}` (standings deltas, rare).
- **Push-to-talk.** flutter_webrtc, full mesh, audio only (Opus, about 24–32 kbps). Each phone holds up to five peer connections. PTT unmutes the local track while held. Signaling (SDP, ICE) goes over the convoy channel. STUN and TURN from Metered Open Relay (free 20 GB/month; TURN is only used when a direct path fails). Audio routes through the normal phone audio session (Bluetooth, CarPlay, Android Auto) and ducks music. iOS uses the `PushToTalk` framework for the system PTT UI and background audio; Android uses a foreground service with `microphone` and `mediaPlayback` types.
- **Positions.** Convoy positions ride the WebRTC data channel every 3–5 s, so they cost no Realtime messages. The broadcast fallback at 15 s covers peers whose data channel is down.
- **Music.** Spotify Jam and Apple Music SharePlay via deep links only; we detect the installed app and show the button. Convoy DJ: the DJ's phone holds the queue and broadcasts track URI plus a target start time over the data channel; each car calls the Spotify play endpoint with `position_ms` adjusted for its measured clock offset; re-sync every 30 s; expect about ±300 ms, fine between cars. Spotify Web API apps run in Development Mode with a small user allowlist, so Convoy DJ members must be allowlisted in the Spotify dashboard.
- **Recap.** Built on each phone from the positions it received during the convoy (kept locally 30 days), the planned route from Routes, and members' uploaded summaries.

## 10. Free-tier budget

| Service | Free allowance | Our cap | What degrades when exhausted |
| --- | --- | --- | --- |
| Apple Developer Program | n/a | $99/yr | The only recurring spend |
| Google Play Console | n/a | $25 once | n/a |
| Supabase database | 500 MB | Prune `trip_events` to score-only after 1 year; `feed_posts` 90 days; alert at 400 MB | Oldest events pruned sooner; feed window shrinks to 30 days |
| Supabase storage | 1 GB | Avatars ≤ 100 KB; convoy photos ≤ 200 KB, ≤ 50 per convoy, 30-day TTL | New albums stay on the phones only |
| Supabase egress | 5 GB/month | Small images, cached on device; feed pages of 20 | Images stop loading; text feed still works |
| Supabase Auth | 50k MAU | None needed | New sign-ups refused with a message |
| Supabase Realtime | ~2M messages/month, 200 concurrent | Subscribe only for screens on display; convoy positions on WebRTC, not Realtime | Presence falls back to a 60 s query; convoy fallback positions stop, data channel continues |
| Supabase Edge Functions | 500k invocations/month | One invocation per notification batch | Push pauses; in-app feed still updates |
| Supabase pause | After 7 idle days | Daily GitHub Actions ping | App shows "waking up"; owner restores by hand |
| Google Maps SDK (Android, iOS) | No-cost SKU | None needed | n/a |
| Google Places API (New) | 5,000/month | Hard quota 150/day in Cloud Console | Stop suggestions become manual pins or typed names |
| Google Routes API | 10,000/month | Hard quota 300/day | ETAs become straight-line estimates, labelled as such |
| GitHub Actions | Free for public repos | Monthly pack build, daily ping | Packs go stale; phones keep old packs |
| GitHub Releases | 2 GB per asset, fair use | ~1–2 GB per monthly release, keep last 3 | n/a |
| Metered Open Relay (TURN) | 20 GB/month | TURN only when direct fails; about 14 MB per relayed stream-hour | Relayed peers cannot hear each other; direct peers unaffected; app says "direct connection failed" |
| Open-Meteo | 10,000 calls/day, non-commercial | One call per trip start | Weather bonus skipped |
| Nominatim | 1 request/s, light use, attribution | One lookup per trip start or end away from a saved place, cached by 100 m cell | Place names fall back to the road name from the pack |
| Spotify Web API | Development Mode, small allowlist | Allowlist friends who use Convoy DJ | Convoy DJ unavailable to others; Jam deep link still works |
| APNs, FCM | Free | None needed | n/a |

The card on file in Google Cloud exists so the project can call the APIs at all. The hard quotas are what make a bill impossible. Check every allowance against the provider's pricing page before each release; they change.

## 11. Repository layout

```
app/                         Flutter app (bundle id app.drivalry)
  lib/
    main.dart
    app/                     router, theme, top-level providers
    features/
      drive/                 live trip, last trip card, trip detail, passenger interstitial
      leagues/               league table, duels, challenges
      friends/               circles map, feed, profiles
      convoy/                create/join, convoy map, PTT, stops, recap
      garage/                vehicles, fuel, parking memory, documents
      settings/              hiding toggles, cues, diagnostics, attribution
    tracking/                Dart side of the native plugins, trip state machine, recorder
    packs/                   download manager, pack reader, matcher
    scoring/                 thin wrapper over packages/drivalry_scoring and the roast library
    data/                    drift database, Supabase client, outbox, repositories
    car/                     Live Activity and ongoing-notification bridges; CarPlay later
  android/                   Kotlin: ActivityRecognition receiver, foreground service, CarAppService
  ios/                       Swift: CoreMotion, CoreLocation, PushToTalk, WidgetKit extension
packages/
  scoring/                   TypeScript executable spec; emits fixtures/
  drivalry_scoring/          Dart port; fixture tests
  drivalry_packs/            Dart pack reader (07-pack-format.md) and the matcher (§5)
tools/
  packs/                     Python + pyosmium pack builder; tests/vectors pins the bytes
supabase/
  migrations/                schema (summaries only; 0000 heartbeat, 0001 everything else)
.github/workflows/           ci.yml (TS spec, Dart port, pack reader, pack builder, Flutter),
                             supabase-keepalive.yml, packs-monthly.yml
.env                         API keys (gitignored); .env.example is committed
```

## 12. Open technical questions

- Texas (102 MB) and California (80 MB) do not fit under 60 MB with `service` roads included (measured 2026-11-03). Accepted for now; the shrink levers are listed in `07-pack-format.md` §7.
- Real 1 Hz GPS power cost on recent iPhones without deferred updates. Measure on the five test iPhones.
- Realtime message budget under real convoy use once the data-channel fallback kicks in. Measure on the first road trip.
- Spotify Development Mode limits as of today. Confirm the allowlist size before promising Convoy DJ.
- Phone-handling detection fidelity on iOS without private APIs. The OS gives less than Android does.
- Whether the nearest-with-heading matcher needs a Viterbi pass in dense urban grids. Measure the wrong-road rate on ten known routes first.
- Supabase egress with avatars and convoy photos at a few hundred users.

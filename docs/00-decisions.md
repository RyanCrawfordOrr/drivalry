# Drivalry: Decision Log

> ADR-style log. One short entry per settled decision. A decision is changed by adding a new entry that supersedes the old one, not by editing the old one. Everything below was settled on 2026-11-02 during the kickoff and the grilling that followed it.

Each entry has three parts. **Context**: why the question came up. **Decision**: what we chose. **Consequences**: what it costs and what it buys.

## ADR-001: Flutter, not Expo / React Native (2026-11-02)

**Context.** The first skeleton was an Expo app in `apps/mobile`. Automatic trip detection, CarPlay, Android Auto, PushToTalk and Live Activities all need native code anyway. The de-facto React Native background-location library needs a paid Android license. All authoring happens on Windows.

**Decision.** Build the app in Flutter in `app/`. State: Riverpod. Local database: drift. Routing: go_router. Maps: google_maps_flutter. Speech: flutter_tts. Foreground location: geolocator. Tracking: our own native plugins (Swift CoreMotion and CoreLocation; Kotlin ActivityRecognition plus a foreground service). flutter_carplay later. Bundle and package id `app.drivalry`. A Mac only builds, signs and uploads the iOS app.

**Consequences.** The Expo app is deleted. One UI codebase, native code only where the OS requires it. No paid tracking SDK. iOS compile errors round-trip through the Mac, so iOS native code is kept small and boring.

## ADR-002: Zero-cost rule (2026-11-02)

**Context.** This is a hobby project. The owner will not pay recurring fees for an app that may have twenty users.

**Decision.** The owner never pays for any API or hosted service. Free tiers only. The only spend is store fees ($99/yr Apple Developer, $25 Google Play). No server we operate. We never pay to upgrade a tier. When a free tier runs out, the feature degrades. It never bills.

**Consequences.** Every service gets a hard cap below its free allowance and a documented degradation (see `03-architecture.md` §10). Features that need a server to compute something move to the phone or to Supabase's free Postgres. Some things we would like (unlimited Places lookups, hosted voice rooms) are off the table.

## ADR-003: Local-first processing; raw GPS never leaves the phone (2026-11-02)

**Context.** The first architecture uploaded raw 1 Hz traces to a Trip Processor that map-matched and scored them. That needs a server, costs money, and holds the most sensitive data we have.

**Decision.** GPS recording, map matching and scoring all happen on the phone. Raw GPS stays on the phone for 90 days and is never uploaded. The cloud receives trip summaries only: score, penalties, events without raw coordinates, distance, duration, and road names for events.

**Consequences.** Trips are scored with no network at all. Friends see how a trip was driven, never where it went. There is no server-side re-scoring, no human review of traces, and no anti-cheat: a modified client could upload a fake score, and we accept that in a game among friends. The Supabase schema drops `trip_samples` and `trip_segments`.

## ADR-004: Speed limits from OpenStreetMap packs (2026-11-02)

**Context.** Google Roads speed limits need a paid Asset Tracking license. Self-hosted Valhalla needs a server. Paid vendor fallbacks (TomTom, HERE) break the zero-cost rule.

**Decision.** OSM `maxspeed` is the only limit source. A Python/pyosmium pipeline in `tools/packs` compiles regional packs (per US state, Canadian province, or country, each under 60 MB), runs monthly on GitHub Actions, and publishes them as static files on GitHub Releases. The app auto-downloads packs on Wi-Fi. An on-device nearest-road-with-heading matcher runs against the pack. First packs: every US state. Where OSM has no limit, or confidence is below 0.7, the app is silent (no roast). Valhalla is gone. Google Roads is rejected.

**Consequences.** Coverage follows OSM quality. Some roads will never roast. Packs must fit on phones, so geometry is simplified and big states may need a road-class filter. Monthly rebuilds are the only "server job" we have, and GitHub runs it for free.

## ADR-005: Speed-limit corrections through a shared cache; never auto-edit OSM (2026-11-02)

**Context.** OSM limits can be wrong, and a wrong roast is the fastest way to lose trust.

**Decision.** A user flags a wrong limit from the trip card. Flags go to a shared `speed_limit_flags` table in Supabase keyed by OSM way id. Two agreeing flags from different users create a shared override (confidence 0.85) that every phone applies on top of its pack. We never edit OSM automatically. Anyone who wants to fix OSM does it by hand.

**Consequences.** Corrections are live without waiting for a pack rebuild. Overrides are pulled per region, so they cost one small query a day. The *Snitch* badge is earned when a flag gets confirmed.

## ADR-006: Google is the map layer (2026-11-02)

**Context.** An earlier round picked MapLibre with OpenFreeMap tiles. Google's terms forbid showing Places content on a non-Google map, and we want Places for convoy stop suggestions. Google's Maps SDK for Android and iOS is a no-cost SKU.

**Decision.** Google Maps SDK for Android and iOS for every map in the app. Places API (New) for convoy stop suggestions. Routes API for convoy ETAs. All in Google Cloud project `drivalry` with a card on file and hard daily quota caps: Places 150/day, Routes 300/day (free monthly allowances are 5,000 and 10,000). API keys live in a gitignored `.env` and never in the repo. MapLibre and OpenFreeMap are dropped.

**Consequences.** The card on file is protection, not a budget: the quota caps make billing impossible. When a cap is hit, stop suggestions and ETAs degrade (manual pins, straight-line estimates). We must follow Google's attribution and Places caching rules.

## ADR-007: Supabase free tier is the only backend (2026-11-02)

**Context.** We need auth, a shared database, realtime, and push, with no server we operate and no bill.

**Decision.** One Supabase free-tier project (already created). Auth via Sign in with Apple and Google only (no SMS, no email/password). Postgres with row-level security holds handles, friends, leagues, trip summaries, the public roast feed with reactions and comments, coarse presence, circles, convoy signaling, and the shared speed-limit cache. Push via APNs and FCM, sent from a Supabase Edge Function fired by database webhooks. Limits to respect: 500 MB database, 1 GB storage, pause after 7 idle days (a daily GitHub Actions ping keeps it awake), about 2M Realtime messages a month, 50k monthly active auth users.

**Consequences.** Scheduled logic (league rollover) is an idempotent Postgres function any client can call, with pg_cron as backstop. Storage is spent only on small images. Realtime is subscribed only for screens on display. Every limit has a cap and a degradation in `03-architecture.md` §10.

## ADR-008: Convoys are 2 to 6 cars with peer-to-peer radio (2026-11-02)

**Context.** LiveKit (SFU) costs money per participant minute. Convoys are small groups of friends.

**Decision.** Convoys hold 2–6 cars. Push-to-talk is peer-to-peer WebRTC audio in a full mesh. Supabase Realtime carries signaling. Metered Open Relay provides free TURN (20 GB/month). Convoy positions ride the same WebRTC data channel. Music: deep links to Spotify Jam and Apple Music SharePlay (no public API), plus a "Convoy DJ" sync using the Spotify Web API. Stop suggestions from Places, ETAs from Routes. LiveKit is gone.

**Consequences.** No voice server. A six-car convoy means five peer connections per phone, which is fine for audio. When TURN quota runs out, only direct connections work. Spotify keeps hobby apps in Development Mode with a small user allowlist, so Convoy DJ is a friends-only feature.

## ADR-009: Roasts are public, library-only, and every group is mean (2026-11-02)

**Context.** The old design had a per-group Mean Mode toggle and a per-user intensity setting. The point of the product is that your friends see your roast.

**Decision.** Roasts are public to the group by default. They are chosen from a fixed, human-written library only; no generated text. Friends can react and comment. Every group is mean; the per-group Mean Mode toggle is gone. The only opt-out is a per-member hiding toggle, and the group can see who is hiding. Spoken cues are off by default. The roast arrives after the trip. A "Were you the passenger?" interstitial precedes scoring. Passenger claims are honor-system with counts visible to the group.

**Consequences.** Copywriting is a real content job, because the library is the whole roast. The banned-word floor is enforced by tests in both the TypeScript and Dart engines. The tone setting disappears from the UI.

## ADR-010: Circles share precise location by default (2026-11-02)

**Context.** The old design had four share levels (Precise, Neighborhood, Driving only, Ghost). That is a lot of UI for a product whose pitch is "your circle always knows".

**Decision.** Every circle shares precise location by default for every member. Each member has a per-circle hiding toggle. Hiding is visible to the other members.

**Consequences.** One switch instead of four levels. Places (Home, Work) stay on the phone, and arrive/leave alerts are computed on the viewer's phone from presence updates, so the cloud never learns anyone's saved places.

## ADR-011: Crash detection never calls anyone (2026-11-02)

**Context.** False positives are common with phone-only crash detection. Emergency numbers differ by country. Automatic calls are a liability.

**Decision.** On a candidate crash: a 30 s full-screen countdown with a large "I'm OK" button. On timeout: a push to emergency contacts who use Drivalry, plus a pre-filled SMS with location opened on the phone for the rest. Never an automatic call.

**Consequences.** Simple, cheap, and safe to ship worldwide. The SMS is pre-filled rather than sent silently because iOS does not allow silent sending.

## ADR-012: Other free sources and an attribution screen (2026-11-02)

**Context.** Weather, place names and speech are needed and must cost nothing.

**Decision.** Open-Meteo for weather at trip start (no key). Nominatim for reverse geocoding, used sparingly, cached, with attribution. On-device TTS for spoken cues. An attribution screen credits OpenStreetMap, Google, Open-Meteo and Nominatim.

**Consequences.** One weather call per trip. Nominatim is called only when a trip starts or ends away from a saved place and a cached name. Attribution is part of the definition of done for the settings screen.

## ADR-013: Build everything, in order, with no gating (2026-11-02)

**Context.** The old roadmap had six phases with exit criteria. The owner chose to build all the features.

**Decision.** Build order: tracking and scoring, then friends, leagues and public roasts, then circles, then convoys, then CarPlay and Android Auto. No stage gates. The tracking quality bar stays as a bar, not a gate: drives start and stop with no taps, under 6% battery per hour driving, under 1% per day parked, scored on-device against the pack, trip card names the right roads with the right roast. Testing via TestFlight and Play internal testing on 5 iPhones and 2 Android phones. The CarPlay Driving Task entitlement is requested now, because Apple is slow and may refuse.

**Consequences.** `06-roadmap.md` is an ordered build plan with milestones, not phases with exits. The quality bar is measured on the owner's own phones through an in-app diagnostics screen.

## ADR-014: TypeScript engine is the executable spec; Dart port must match (2026-11-02)

**Context.** The scoring engine exists in TypeScript with tests. The app is Dart.

**Decision.** `packages/scoring` stays as the executable spec. It emits JSON fixtures into `packages/scoring/fixtures/`. A Dart port in `packages/drivalry_scoring` must pass the same fixtures. Scoring numbers are unchanged from `02-game-design.md` and will be tuned after two weeks of real trips. Doc, fixtures and both ports change together.

**Consequences.** Two implementations to maintain, one source of truth. Tuning is a deliberate, dated step rather than drift. CI (`.github/workflows/ci.yml`) runs the TypeScript tests, the Dart tests and Flutter analyze on every push.

## ADR-015: Hard product rules, reaffirmed (2026-11-02)

**Context.** These predate the architecture change and survive it.

**Decision.** Never reward speed or raw distance. Roasts target the drive, not the person. No selling or sharing location data. 16+ by terms, no teen mode.

**Consequences.** No top-speed stats, no mileage leagues, a daily distance credit cap, a banned-word test on every roast template, no insurer or data-broker integrations, no teen features.

## Open items (not decided)

- **Money.** The docs now say "free, no ads, no subscription". The old Pro tier was removed because the zero-cost, no-server model leaves nothing to pay for, and several Pro perks (12-car convoys, unlimited PTT, raw-GPS retention tiers) conflict with the decisions above. Reinstating a paid tier is a new decision.
- **Web pages.** The old spec had read-only web profiles and shared recap pages. Dropped for now; a static GitHub Pages site would be free if we want it later.
- **Global leagues with strangers.** Still in the spec. Matchmaking would be a Postgres function. Not scheduled.

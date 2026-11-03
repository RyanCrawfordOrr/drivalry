# Drivalry app (Flutter)

Android and iOS app. Bundle and package id `app.drivalry`.

## Run

Secrets and project ids live in the repo-root `.env` (gitignored; copy `.env.example`). Pass them as build-time defines:

```bash
flutter run --dart-define-from-file=../.env
flutter test
flutter analyze --fatal-infos
```

Without a `.env` the app still runs: tracking and scoring are local, the map on the trip screen shows a placeholder, and the social tabs explain that no project is configured. `PACK_INDEX_URL` in the `.env` overrides where speed-limit packs are looked up (docs/07 §6).

## Desk test (no car needed)

1. Install on a phone (`flutter run …` or the adb steps in the root README) and open the **Drive** tab.
2. Tap **Allow** on the permission card and grant location "Always" with precise location, plus motion/activity.
3. Menu (⋮) › **Speed-limit packs** › **Install for my location** (Wi-Fi), or **Import URL** with a `.pack` link. Without a pack trips still score for smoothness, attention and efficiency; speeding stays silent.
4. Menu › **Simulate a drive** › *Messy commute* (or *Drive from here* to synthesise a route from the installed pack). The trip replays through the same recorder, matcher and scorer the native plugin feeds, then opens.
5. The Drive tab shows the trip card with its score ring and roast line; tap it for the map, breakdown, events and "Limit is wrong here".
6. Menu › **Diagnostics** shows what the plugin and the database have seen; "Copy debug info" puts it on the clipboard.

A real drive works the same way with no taps: the native plugin records, the app scores when you park, and the "Were you the passenger?" card appears pre-answered.

## Layout

```
lib/
  main.dart              ProviderScope + DrivalryApp
  app/                   app.dart, router.dart (go_router; Drive branch has
                         trip/:id, packs, diagnostics), shell.dart, theme.dart,
                         bootstrap.dart (purge, Maps key, tracking boot)
  config/env.dart        String.fromEnvironment wrappers for .env values
  data/db/               drift tables + AppDatabase (database.g.dart is generated:
                         dart run build_runner build --delete-conflicting-outputs)
  data/models/           TripPhase, TripScoreView (read side of stored scores)
  tracking/              tracking_models (docs/08 maps), tracking_channel (platform
                         channels), trip_recorder (events → rows), match_runner
                         (isolate), trip_finalizer (match → score → store),
                         tracking_controller (Riverpod), simulated_tracking,
                         solar (night fraction), weather (Open-Meteo)
  packs/                 pack_manager (index, download, verify, swap, import)
  features/drive/        Drive tab, trip detail, packs screen, simulate sheet
  features/settings/     diagnostics
  widgets/               units (mph / km/h), shared widgets
test/                    unit and widget tests (support/ has the fakes)
```

## Stack

Riverpod (state), go_router (navigation), drift on `package:sqlite3` 3.x (local
SQLite; the native library is bundled through Dart build hooks, including for
host tests), google_maps_flutter (maps), our own native tracking plugins
(`docs/08-tracking-channel.md`), `drivalry_packs` (pack reader + matcher),
`drivalry_scoring` (the engine), flutter_tts (spoken cues, later),
supabase_flutter (accounts, friends, leagues, feeds, later). See
`../docs/03-architecture.md`.

## Tests

`flutter test` runs everything, including database-backed tests against an
in-memory SQLite. If the sqlite3 build hook cannot provide a native library on
the host (no network for the prebuilt download), those tests skip and say why.

## Cloud sync, sign-in, push (Stage 2, part A)

Everything cloud-side goes through one outbox (`lib/data/sync/outbox.dart`): a feature enqueues a row with a client id and a `kind`, and a registered handler uploads it with retries and backoff. Handlers throw `OutboxRetryLater` while signed out, so a trip scored before sign-in uploads right after. The worker drains on start, on reconnect, on sign-in and every two minutes (`lib/data/sync/sync_bootstrap.dart`).

| Kind | Payload | Handler |
| --- | --- | --- |
| `trip_summary` | `{trip_id, hash, summary: {…docs/03 §3.6…}, events: […]}` | upsert `trip_summaries`, replace `trip_events`, upsert `feed_posts` (trip, plus `shame` when reckless) |
| `trip_delete` | `{trip_id}` | delete the summary (cascades) |
| `limit_flag` | `{flag_id, way_id, region, suggested_value, suggested_mph, suggested_mps}` | insert `speed_limit_flags`, mark the local flag synced |
| `profile_update` | `{user_id, fields: {display_name \| location_hidden …}}` | update `profiles` |
| `push_token` | `{token, platform, device_label}` | upsert `push_tokens` |

Trips upload once per content hash (`UploadedTrips`), so a re-scored trip goes again and an unchanged one never does. Nothing with coordinates leaves the phone; events carry road names only.

- **Sign-in**: `lib/data/supabase/auth_service.dart`. Apple on iOS (native), Google on both (native id token → `signInWithIdToken`). The owner steps are in `docs/09-auth-setup.md`; until they are done the sign-in screen says "not configured for this build".
- **Profile**: `lib/features/profile/` (handle, display name, avatar ≤ 100 KB in the `avatars` bucket, rating, passenger count, badges, streaks), cached in `RemoteCache` so it renders offline.
- **Settings**: account (sign out, delete account via `delete_own_account()`, export my data as JSON), units, the global "Hide my location from everyone" switch (ADR-018), notifications (quiet hours, per-category switches), speed-limit packs, diagnostics, attribution.
- **Push**: `lib/data/push/`. FCM on both platforms, initialised from the `FIREBASE_*` values in `.env` (docs/09 §7), so no `google-services.json` is needed. Foreground messages and the local "Trip scored" notification go through `flutter_local_notifications` and respect quiet hours; crash alerts never wait.
- **Speed-limit corrections**: "Limit is wrong here" flags upload; the shared `speed_limit_overrides` for each installed region are pulled daily into `RemoteCache` and applied by the finalizer under the phone's own pending flags.

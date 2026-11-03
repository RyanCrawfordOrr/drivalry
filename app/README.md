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

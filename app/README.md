# Drivalry app (Flutter)

Android and iOS app. Bundle and package id `app.drivalry`.

## Run

Secrets and project ids live in the repo-root `.env` (gitignored; copy `.env.example`). Pass them as build-time defines:

```bash
flutter run --dart-define-from-file=../.env
flutter test
flutter analyze
```

Without a `.env` the app still runs: tracking and scoring are local, and the social tabs explain that no project is configured.

## Layout

```
lib/
  main.dart            ProviderScope + DrivalryApp
  app/                 app.dart (MaterialApp.router), router.dart (go_router,
                       five StatefulShellRoute branches), shell.dart
                       (NavigationBar), theme.dart (brand + score colours)
  config/env.dart      String.fromEnvironment wrappers for .env values
  features/<tab>/      one folder per tab: drive, leagues, friends, convoy, garage
  widgets/             shared widgets
test/                  widget tests
```

## Stack

Riverpod (state), go_router (navigation), drift (local SQLite for trips and
packs), google_maps_flutter (maps), geolocator plus our own native plugins
(tracking), flutter_tts (spoken cues), supabase_flutter (accounts, friends,
leagues, feeds). See `../docs/03-architecture.md`.

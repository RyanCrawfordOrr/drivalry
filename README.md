# Drivalry

The step challenge for driving. Your phone notices when you drive, scores the trip 0 to 100 on the device, and your friends see the result. Smooth, legal, efficient driving climbs the weekly league. Speeding and phone use get roasted in public. Circles share where everyone is, and convoys turn a road trip into one shared map with a push-to-talk radio.

Drivalry never rewards speed or distance. It costs nothing to run: every service it touches is a free tier, there is no server of ours, and raw GPS never leaves the phone.

## Repository

```
app/                      Flutter app (Android + iOS), bundle id app.drivalry
packages/scoring/         TypeScript scoring engine: the executable spec, with JSON fixtures
packages/drivalry_scoring Dart port of the engine; must match the fixtures
packages/drivalry_packs   Dart speed-limit pack reader and on-device road matcher
tools/packs/              Speed-limit pack builder (OpenStreetMap, Python); monthly GitHub Release
supabase/                 Database schema and policies for the free-tier backend
docs/                     Product spec, game design, architecture, car platforms,
                          privacy, roadmap, decision log, pack format, tracking contract
```

## Working on it

```bash
npm install && npm test                        # TypeScript spec + fixtures
cd packages/drivalry_scoring && dart test
cd packages/drivalry_packs && dart test
cd tools/packs && python -m pytest             # see tools/packs/README.md for the venv
cd app && flutter run --dart-define-from-file=../.env
```

Copy `.env.example` to `.env` and fill in the Supabase and Google values. `.env` is gitignored.

Start with `docs/00-decisions.md` for why things are the way they are, then `docs/03-architecture.md`.

## License

MIT. See `LICENSE`.

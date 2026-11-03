# drivalry_packs

Pure-Dart reader for Drivalry speed-limit packs and the on-device road matcher.
No Flutter dependency; `dart:io` is used only for zlib and (through
`package:sqlite3`) SQLite.

A pack is one SQLite file per region built by `tools/packs` from OpenStreetMap.
It holds simplified road geometry, `maxspeed` values and street names, indexed
by 5-character geohash cells. The byte format is `docs/07-pack-format.md`; this
package is its reference reader.

## What it does

```
GPS samples (1 Hz)  ──►  RoadMatcher  ──►  RoadSegment[] + limit coverage
                            ▲
                       TileCache  ◄──  SqlitePack / MemoryPack  ◄──  .pack file
```

- `SqlitePack.open(path)` opens a pack read-only and refuses unknown schema
  versions (`UnsupportedPackException`), so the app keeps its old pack.
- `TileCodec` decodes a tile blob (zlib + varints) into `PackWay` objects;
  `PackWay.limitMps(forward: …)` resolves the directional limit and converts
  mph / km/h to m/s. Confidence is 0.9 for a tagged limit, 0.5 for an implied
  one, 0 for none.
- `TileCache` decodes and LRU-caches cells, and answers "ways near this point"
  with the cell plus its eight neighbours, deduplicated.
- `RoadMatcher.match(samples, pack)` produces the non-overlapping
  `RoadSegment` runs the scoring engine (`package:drivalry_scoring`) consumes,
  plus `limitCoverage` (moving seconds on segments with confidence ≥ 0.7) and
  `matchedFraction`.
- `LiveMatcher.locate(fix)` is the single-fix variant for spoken cues and the
  live card. Sticky across fixes, never touches the network.
- `PackIndex` models the release `index.json` and answers which regions contain
  a coordinate.
- `MemoryPack.fromWays(...)` builds a pack in memory for tests and tools.

## The matcher

Nearest road with heading, as specified in `docs/03-architecture.md` §5:

1. Candidates are the ways within `max(35 m, fix accuracy)` of the sample
   (bounding-box prefilter, then nearest point on the polyline on a local flat
   projection).
2. Cost = `distance / 10 + headingDelta / 30`. The heading is the OS course
   when speed ≥ 2 m/s, else the bearing from the previous to the next sample
   when they are more than 3 m apart. Two-way roads are compared against both
   directions and remember which one won; one-way roads only against their
   allowed direction.
3. The current way is kept until a rival beats its cost by 1.0 for three
   consecutive samples; the switch is then back-dated to the first of those
   samples, so segment boundaries land where the new road actually started.
   If the current way drops out of reach the matcher switches immediately.
4. Fixes with accuracy > 50 m, or stationary fixes with no usable heading,
   inherit the previous way.
5. Runs of (way, direction) become `RoadSegment`s; unmatched runs become
   segments with a null limit and confidence 0, so the result always tiles the
   whole index range.
6. Shared corrections (`LimitOverride`, keyed by way id) replace the limit and
   confidence of a way.

An hour of 1 Hz samples on a 50-way grid matches in about 15 ms on a desktop.

## Tests

```
dart pub get
dart analyze --fatal-infos
dart test
```

`package:sqlite3` 3.x downloads its own prebuilt SQLite library through Dart
hooks the first time it builds (also on Windows), so the SQLite-backed tests
run everywhere with network access. Without it they are skipped with a reason.
`test/real_pack_test.dart` runs only when `tools/packs/out/us-dc.pack` exists.

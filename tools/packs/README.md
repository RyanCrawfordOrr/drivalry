# tools/packs: speed-limit pack builder

Python batch tool that turns a Geofabrik OpenStreetMap extract into one `<region>.pack`
SQLite file in the schema-1 format defined in [`docs/07-pack-format.md`](../../docs/07-pack-format.md).
The Flutter app downloads these packs and matches GPS traces against them offline; the Dart
reader lives in `packages/drivalry_packs`. Both sides are tested against the same vector,
`tests/vectors/mini.pack`.

What a pack holds: every driveable `highway` way (road class 0-7, see docs/07 §3) with its
posted limits in the posted unit (35 mph stays 35 mph), oneway and roundabout flags, a street
name id, and its geometry simplified to 2 m, filed under every geohash-5 cell it passes
through and compressed with zlib. Nothing else: no footways, no driveways, no routing graph.

## Layout

```
drivalry_packs/
  osm.py        tags -> road class, oneway, roundabout, limits (docs/07 §3-§5)
  geohash.py    Niemeyer geohash encode / decode_bbox / neighbors
  geometry.py   Douglas-Peucker at a metre tolerance, 500 m cell sampling
  encoding.py   varints, zigzag, tile blob encode/decode, zlib
  build.py      build_pack(): two passes with pyosmium, writes the SQLite file
  index.py      index.json for a release directory
  cli.py        python -m drivalry_packs {build,download,index,regions}
regions.json    region code -> { name, geofabrik path }   (50 states + us-dc + us-pr)
zones.json      maxspeed:type / source:maxspeed values with a fixed legal value
tests/          pytest; tests/vectors/mini.osm + mini.pack are the format vectors
out/            local build output (gitignored)
```

## Set up

Python 3.12. From this directory:

```powershell
python -m venv .venv
.venv\Scripts\python -m pip install -r requirements.txt     # pyosmium 4.3.2, pytest
```

(`source .venv/Scripts/activate` in Git Bash, or call `.venv/Scripts/python` directly.)

## Build one region

```powershell
.venv\Scripts\python -m drivalry_packs regions                       # list codes
.venv\Scripts\python -m drivalry_packs download --region us-dc --dest ..\..\..\osm-extracts
.venv\Scripts\python -m drivalry_packs build --region us-dc --input ..\..\..\osm-extracts\district-of-columbia-latest.osm.pbf --out out
```

`download` is resumable (it keeps a `.part` file) and reuses a complete file if it is already
there; delete the file to fetch a fresher extract. Keep extracts outside the repo. `build`
writes `out/us-dc.pack` and prints way count, tile count, bytes, seconds and bbox. Options:
`--built-at 2026-11-02T00:00:00Z` for reproducible output, `--keep-minor-service` to keep
driveways and parking aisles, `--source` and `--region-name` for inputs that are not in
`regions.json`.

`index --packs out --base-url <url> --out index.json [--merge previous.json]` writes the
release index (docs/07 §6). `--merge` keeps entries of a previous index for regions that
have no pack in the directory.

## Tests

```powershell
.venv\Scripts\python -m pytest
```

`tests/test_build.py` builds `tests/vectors/mini.osm` and asserts the result is byte-identical
to the committed `tests/vectors/mini.pack` (ignoring only the four header bytes where SQLite
stamps its own library version), then decodes it and checks every way. When the format or
`mini.osm` changes, regenerate the vector with the command at the top of `tests/test_build.py`
and commit it together with `docs/07-pack-format.md`. The Dart tests read the same file.

## Publishing (`.github/workflows/packs-monthly.yml`)

Runs at 03:00 UTC on the 2nd of every month, or by hand (`workflow_dispatch`, optional
comma-separated `regions` input; empty means all).

1. `plan` reads `regions.json` and emits the matrix and the tag `packs-YYYY.MM`.
2. `build` (matrix, 8 at a time, 90-minute limit) downloads the extract with retries, builds
   the pack and uploads it as artifact `pack-<region>`.
3. `release` runs only when every region built. It writes `index.json` (merging the current
   index so a partial manual run never drops a region), creates the release `packs-YYYY.MM`
   with all `.pack` files plus `index.json`, uploads `index.json` with `--clobber` to the
   permanent release `packs-index`, and deletes monthly releases older than the newest three.

The app fetches `https://github.com/<owner>/<repo>/releases/download/packs-index/index.json`
and follows each entry's `url`, verifying `bytes` and `sha256`.

## Rules

**Determinism.** The same input, the same `--built-at`, the same `zones.json` and the same
SQLite and zlib libraries give the same bytes. Everything that could vary is pinned: names
are sorted (UTF-8 byte order, ids from 1), ways in a tile are sorted by id, tiles are inserted
in geohash order, meta rows in a fixed order, and the file is `VACUUM`ed. Do not add
timestamps, random ids or dict-order-dependent output.

**Schema bumps.** Any change to the bytes a reader sees (tables, meta semantics, blob
layout, flags, class mapping, what is kept or dropped) is a schema bump: raise
`schema_version` in `drivalry_packs/__init__.py`, update `docs/07-pack-format.md`,
regenerate `mini.pack`, and keep the Dart reader able to read the previous schema for one
release. Adding a new `meta` key is not a bump. Changing simplification tolerance or the
sampling step changes bytes but not meaning; still regenerate the vector in the same commit.

**Implied limits.** `zones.json` lists only zone tags whose value is fixed by law wherever
they are used (today: `US-DC:urban` = 20 mph). Road-class defaults are intentionally not
applied: US defaults vary by state and city, and the reader gives implied limits confidence
0.5 anyway. A `maxspeed` that cannot be parsed and has no known zone yields "no limit".

## Sizes measured on 2026-11-02 (minor service roads dropped)

| region | PBF | pack | ways | tiles | build time | peak RSS |
| --- | --- | --- | --- | --- | --- | --- |
| us-dc | 21 MB | 0.6 MB | 28,480 | 20 | 2.4 s | 138 MB |
| us-md | 216 MB | 13.7 MB | 378,259 | 1,854 | 41 s | 874 MB |

Memory is dominated by the node location store (about 4 MB per MB of PBF), so California
needs roughly 5.5 GB; GitHub's 16 GB runners cover it. If that ever fails, switch
`with_locations("flex_mem")` in `build.py` to a disk-backed store such as `sparse_file_array`.

In Maryland the pack is 6.3 % of the PBF and `service` ways are 44 % of the ways and 37 % of
the tile bytes. Scaling by PBF size (Texas 727 MB, California 1,335 MB on 2026-11-02) puts
Texas near 45 MB and California near 85 MB, so California is expected to miss the 60 MB
target with `service` roads included. The workflow log prints every pack's size; if a region
exceeds the target, drop `highway=service` entirely for it first (about -30 % of the file),
then `unclassified`.

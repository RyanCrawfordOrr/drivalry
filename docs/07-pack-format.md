# Drivalry: Speed-limit pack format (schema 1)

> The exact bytes. `tools/packs` (Python) writes this; `packages/drivalry_packs` (Dart) reads it. Both have tests against the same vectors. Changing anything here means a schema bump and a reader that still understands the old one for one release (`06-roadmap.md`, "expensive to change").

## 1. Container

One SQLite 3 file per region, opened read-only on the phone. Page size 4096. Three tables, nothing else (no indexes beyond the primary keys, no views).

```sql
CREATE TABLE meta  (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE names (name_id INTEGER PRIMARY KEY, name TEXT NOT NULL);
CREATE TABLE tiles (geohash TEXT PRIMARY KEY, ways BLOB NOT NULL);
```

`meta` rows (all values are strings):

| key | value |
| --- | --- |
| `schema_version` | `1` |
| `region` | region code, e.g. `us-dc` (see §6) |
| `region_name` | human name, e.g. `District of Columbia` |
| `source` | Geofabrik URL the pack was built from |
| `osm_replication_timestamp` | ISO-8601 UTC from the PBF header, e.g. `2026-10-31T21:20:04Z`; empty string when the input was OSM XML (no header timestamp) |
| `built_at` | ISO-8601 UTC |
| `builder` | `drivalry-packs/<version>` |
| `way_count` | number of distinct ways in the pack |
| `tile_count` | number of rows in `tiles` |
| `geohash_precision` | `5` |
| `bbox` | `min_lat,min_lon,max_lat,max_lon` with 6 decimals, over all kept ways; empty string for an empty pack |

`names` holds every distinct street name once. `name_id` starts at 1 and follows the sorted order of the names (UTF-8 byte order), so a rebuild from the same input gives the same ids.

`tiles.geohash` is a 5-character geohash (base-32 alphabet `0123456789bcdefghjkmnpqrstuvwxyz`, standard Niemeyer encoding, cells about 4.9 km × 4.9 km). A way is stored in **every** cell that any of its polyline segments passes through (segments are sampled every 500 m plus both endpoints when computing the cells). Ways are stored whole, not clipped, so a long way appears in several tiles; the reader dedupes by way id when it loads a cell and its neighbours.

## 2. Tile blob

`ways` is the **zlib** (RFC 1950, level 9) compression of this byte stream. All integers are unsigned LEB128 varints unless marked `u8`. Signed values use zigzag encoding (`(n << 1) ^ (n >> 31)`) before the varint.

```
u8      blob_version        = 1
varint  way_count
way[way_count]              sorted by way_id ascending
```

Each `way`:

```
varint  way_id              OSM way id
u8      cls                 road class, §3
varint  name_id_plus_one    0 = no name, otherwise names.name_id + 1
varint  max_plus_one        0 = no forward limit, otherwise posted value + 1 (integer in the posted unit)
varint  maxb_plus_one       0 = backward limit same as forward (or also none), otherwise posted value + 1
u8      flags               §4
varint  point_count         >= 2
zigzag  lat0_e6             first point, absolute, degrees × 1e6 rounded to int
zigzag  lon0_e6
zigzag  dlat_e6 [point_count - 1]   each subsequent point as a delta from the previous point
zigzag  dlon_e6 [point_count - 1]   (interleaved: dlat, dlon, dlat, dlon, ...)
```

Points are the way's node coordinates in way order, simplified with Douglas–Peucker at 2 m (tolerance converted to degrees at the way's mean latitude). The first and last node are always kept.

## 3. Road class `cls`

| cls | OSM `highway` values | `RoadClass` in the scoring engine |
| --- | --- | --- |
| 0 | `motorway`, `motorway_link` | `motorway` |
| 1 | `trunk`, `trunk_link` | `trunk` |
| 2 | `primary`, `primary_link` | `primary` |
| 3 | `secondary`, `secondary_link` | `secondary` |
| 4 | `tertiary`, `tertiary_link` | `tertiary` |
| 5 | `residential`, `living_street` | `residential` |
| 6 | `service` | `service` |
| 7 | `unclassified`, `road` | `unclassified` |
| 8 | anything else that was kept | `unknown` |

Kept: exactly the values in rows 0–7. Dropped: `track`, `path`, `footway`, `cycleway`, `bridleway`, `steps`, `pedestrian`, `corridor`, `busway`, `bus_guideway`, `escape`, `raceway`, `construction`, `proposed`, `platform`, `elevator`, and anything without a `highway` tag. Also dropped by default (builder flag `--keep-minor-service` restores them): `highway=service` with `service` in `driveway`, `parking_aisle`, `drive-through`, `emergency_access`. Ways with `area=yes` are dropped.

## 4. `flags`

```
bit 0-1  oneway    0 = two-way, 1 = oneway in point order, 2 = oneway against point order
bit 2-3  src       0 = no limit, 1 = numeric maxspeed tag, 2 = implied (maxspeed:type / zone / class default)
bit 4    mph       1 = max and maxb are in mph, 0 = km/h
bit 5    roundabout  junction=roundabout or junction=circular
bit 6-7  reserved  always 0
```

There is one unit bit for both directions. In the rare case where a way mixes units (`maxspeed=30 mph` with `maxspeed:backward=40`), the backward value is converted into the forward unit and rounded.

Confidence is derived by the reader, not stored: `src 1` → 0.9, `src 2` → 0.5, `src 0` → 0.

Oneway is implied (unless `oneway` says otherwise) for `highway=motorway`, `highway=motorway_link`, and `junction=roundabout` / `junction=circular`. `oneway=-1` or `reverse` gives value 2. Any other truthy `oneway` (`yes`, `1`, `true`) gives 1.

## 5. Parsing `maxspeed`

For `maxspeed` (forward, and the way's default), `maxspeed:forward`, `maxspeed:backward`:

- `"35 mph"`, `"35mph"`, `"35 MPH"` → 35, mph.
- `"50"`, `"50 km/h"`, `"50 kmh"`, `"50 kph"` → 50, km/h.
- `"20 knots"` → round(20 × 1.852), km/h.
- `"none"`, `"signals"`, `"variable"`, `"walk"`, `"national"`, `"urban"`, `"rural"`, `"implicit"` and anything that is not a number → no limit from this tag.
- A list (`"35 mph; 25 mph"`) → first value.
- Decimal values are rounded to the nearest integer.

When the tag is unparsable but `maxspeed:type` or `source:maxspeed` names a zone the builder knows a value for (`US:*` entries in `tools/packs/zones.json`), the value is stored with `src = 2`. Otherwise `src = 0`.

A way whose forward and backward limits are both present and equal stores only `max` (`maxb_plus_one = 0`). If only `maxspeed:backward` exists, `max_plus_one = 0` and `maxb_plus_one` holds it. The reader resolves the limit for the direction of travel: travelling in point order uses `max`; against point order uses `maxb` when set, otherwise `max`.

Conversion to m/s in the reader: mph × 0.44704; km/h ÷ 3.6. Never pre-convert in the pack: 35 mph must stay 35 mph.

## 6. Regions and the release

Region codes: `us-xx` with the USPS state abbreviation in lower case (`us-ca`, `us-dc`). Later `ca-xx` for Canadian provinces and ISO-3166 alpha-2 for countries. `tools/packs/regions.json` maps codes to Geofabrik paths and names.

Each monthly GitHub Release is tagged `packs-YYYY.MM` and carries one `<region>.pack` per region plus `index.json`:

```json
{
  "schemaVersion": 1,
  "builtAt": "2026-11-02T03:14:15Z",
  "packs": [
    {
      "region": "us-dc",
      "name": "District of Columbia",
      "url": "https://github.com/RyanCrawfordOrr/drivalry/releases/download/packs-2026.11/us-dc.pack",
      "bytes": 1234567,
      "sha256": "…",
      "osmTimestamp": "2026-10-31T21:20:04Z",
      "wayCount": 23456,
      "bbox": [minLat, minLon, maxLat, maxLon]
    }
  ]
}
```

`bbox` is the bounding box of the region's ways and is what the phone uses to decide which region a trip falls in. The app refuses a pack whose `schemaVersion` it does not know and keeps its old pack.

## 7. Test vectors

`tools/packs/tests/vectors/` holds `mini.osm` (a hand-written OSM XML with twenty ways covering every branch above; seventeen are kept) and the exact `mini.pack` the builder must produce from it. The Python test rebuilds it and compares bytes, masking only SQLite's four library-version bytes at header offsets 96–99. `packages/drivalry_packs/test/mini_pack_test.dart` reads the same `mini.pack` and asserts the decoded ways, limits, flags and geometry. If the builder changes output, the vector, both tests and this document change in the same commit.

Measured on 2026-11-02 (pyosmium 4.3.2): District of Columbia 21 MB PBF → 0.6 MB pack, 28,480 ways, 20 tiles, 2.4 s; Maryland 216 MB PBF → 13.7 MB pack, 378,259 ways, 1,854 tiles, 41 s, 874 MB RSS.

First full release (`packs-2026.11`, 2026-11-03, all 52 US regions on GitHub Actions, every build succeeded): 1,136 MB in total. Texas 102 MB and California 80 MB exceed the 60 MB target; Florida 46 MB and North Carolina 42 MB are the next largest; everything else is under 40 MB. The two big packs are accepted for now (Wi-Fi only, once a month, one region per user). Levers if they need to shrink, in order: Douglas–Peucker at 5 m instead of 2 m (fewer points on curvy roads), dropping `highway=service` for regions over the target (about 30% of the file), and splitting a state into two packs by longitude with their own bboxes.

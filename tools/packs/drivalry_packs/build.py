"""Build one `.pack` from an OSM extract (docs/07 §1-§5).

Two passes over the input with pyosmium: the first collects street names so
`names.name_id` can follow sorted order, the second encodes every kept way once
and files the encoded record under each geohash cell it passes through. Node
locations live in pyosmium's `flex_mem` store, so memory is bounded by the
number of nodes in the extract plus the encoded ways.
"""

from __future__ import annotations

import math
import sqlite3
import time
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path

import osmium

from . import BUILDER, GEOHASH_PRECISION, SCHEMA_VERSION, utc_now_iso
from .encoding import PackWay, assemble_tile, compress_tile, encode_way, pack_flags
from .geometry import Point, cells_for_way, simplify
from .osm import Zones, is_roundabout, load_zones, oneway, resolve_limits, road_class

SIMPLIFY_TOLERANCE_M = 2.0
PAGE_SIZE = 4096

SCHEMA_SQL = (
    "CREATE TABLE meta  (key TEXT PRIMARY KEY, value TEXT NOT NULL)",
    "CREATE TABLE names (name_id INTEGER PRIMARY KEY, name TEXT NOT NULL)",
    "CREATE TABLE tiles (geohash TEXT PRIMARY KEY, ways BLOB NOT NULL)",
)

BBox = tuple[float, float, float, float]
"""`(min_lat, min_lon, max_lat, max_lon)` in degrees."""


@dataclass(frozen=True)
class BuildStats:
    """What `build_pack` produced."""

    way_count: int
    tile_count: int
    bytes: int
    bbox: BBox | None
    osm_timestamp: str
    seconds: float


def _highway_ways(path: Path, with_locations: bool) -> osmium.FileProcessor:
    """Iterate the ways carrying a `highway` tag, optionally with node locations."""
    if with_locations:
        processor = osmium.FileProcessor(str(path), osmium.osm.NODE | osmium.osm.WAY)
        processor.with_locations("flex_mem").with_filter(osmium.filter.EntityFilter(osmium.osm.WAY))
    else:
        processor = osmium.FileProcessor(str(path), osmium.osm.WAY)
    return processor.with_filter(osmium.filter.KeyFilter("highway"))


def _collect_names(path: Path, keep_minor_service: bool) -> dict[str, int]:
    """Pass 1: distinct names of kept ways -> `name_id`, 1-based in sorted order."""
    names: set[str] = set()
    for way in _highway_ways(path, with_locations=False):
        if road_class(way.tags, keep_minor_service) is not None:
            name = way.tags.get("name")
            if name:
                names.add(name)
    return {name: index for index, name in enumerate(sorted(names), start=1)}


def _e6(degrees: float) -> int:
    return int(math.floor(degrees * 1_000_000 + 0.5))


def _convert_way(
    way: osmium.osm.Way, zones: Zones, keep_minor_service: bool
) -> tuple[PackWay, list[Point]] | None:
    """Turn an OSM way into a `PackWay` plus its simplified points, or `None` to drop it."""
    cls = road_class(way.tags, keep_minor_service)
    if cls is None:
        return None
    raw = [(node.location.lat, node.location.lon) for node in way.nodes if node.location.valid()]
    if len(raw) < 2:
        return None
    points = simplify(raw, SIMPLIFY_TOLERANCE_M)
    limits = resolve_limits(way.tags, zones)
    flags = pack_flags(
        oneway(way.tags, way.tags.get("highway", "")),
        limits.src,
        limits.mph,
        is_roundabout(way.tags),
    )
    pack_way = PackWay(
        way_id=way.id,
        cls=cls,
        name=way.tags.get("name") or None,
        forward=limits.forward,
        backward=limits.backward,
        flags=flags,
        points=tuple((_e6(lat), _e6(lon)) for lat, lon in points),
    )
    return pack_way, points


def _write_sqlite(
    output_path: Path,
    meta: list[tuple[str, str]],
    name_ids: dict[str, int],
    tiles: dict[str, list[tuple[int, bytes]]],
) -> None:
    """Create the three tables, fill them in deterministic order and VACUUM."""
    output_path.parent.mkdir(parents=True, exist_ok=True)
    if output_path.exists():
        output_path.unlink()
    connection = sqlite3.connect(output_path)
    try:
        connection.execute(f"PRAGMA page_size={PAGE_SIZE}")
        for statement in SCHEMA_SQL:
            connection.execute(statement)
        connection.executemany("INSERT INTO meta VALUES (?, ?)", meta)
        connection.executemany(
            "INSERT INTO names VALUES (?, ?)",
            ((index, name) for name, index in sorted(name_ids.items(), key=lambda item: item[1])),
        )
        connection.executemany(
            "INSERT INTO tiles VALUES (?, ?)",
            ((cell, compress_tile(assemble_tile(records))) for cell, records in sorted(tiles.items())),
        )
        connection.commit()
        connection.execute("VACUUM")
    finally:
        connection.close()


def build_pack(
    input_pbf: str | Path,
    output_path: str | Path,
    region: str,
    region_name: str,
    source_url: str,
    built_at: str | None = None,
    keep_minor_service: bool = False,
    zones: Zones | None = None,
) -> BuildStats:
    """Build `output_path` from `input_pbf` (PBF or OSM XML).

    Output is byte-for-byte deterministic for the same input, `built_at`,
    `zones`, SQLite library and zlib. `built_at` defaults to now (UTC).
    """
    started = time.perf_counter()
    input_path = Path(input_pbf)
    output = Path(output_path)
    if zones is None:
        zones = load_zones()

    header = osmium.io.Reader(str(input_path), osmium.osm.NOTHING).header()
    osm_timestamp = header.get("osmosis_replication_timestamp", "")

    name_ids = _collect_names(input_path, keep_minor_service)

    tiles: dict[str, list[tuple[int, bytes]]] = defaultdict(list)
    way_count = 0
    min_lat = min_lon = math.inf
    max_lat = max_lon = -math.inf
    for way in _highway_ways(input_path, with_locations=True):
        converted = _convert_way(way, zones, keep_minor_service)
        if converted is None:
            continue
        pack_way, points = converted
        record = encode_way(pack_way, name_ids)
        for cell in cells_for_way(points, GEOHASH_PRECISION):
            tiles[cell].append((pack_way.way_id, record))
        for lat, lon in pack_way.points:
            min_lat, max_lat = min(min_lat, lat), max(max_lat, lat)
            min_lon, max_lon = min(min_lon, lon), max(max_lon, lon)
        way_count += 1

    bbox: BBox | None = None
    if way_count:
        bbox = (min_lat / 1e6, min_lon / 1e6, max_lat / 1e6, max_lon / 1e6)
    meta = [
        ("schema_version", str(SCHEMA_VERSION)),
        ("region", region),
        ("region_name", region_name),
        ("source", source_url),
        ("osm_replication_timestamp", osm_timestamp),
        ("built_at", built_at or utc_now_iso()),
        ("builder", BUILDER),
        ("way_count", str(way_count)),
        ("tile_count", str(len(tiles))),
        ("geohash_precision", str(GEOHASH_PRECISION)),
        ("bbox", ",".join(f"{value:.6f}" for value in bbox) if bbox else ""),
    ]
    _write_sqlite(output, meta, name_ids, tiles)

    return BuildStats(
        way_count=way_count,
        tile_count=len(tiles),
        bytes=output.stat().st_size,
        bbox=bbox,
        osm_timestamp=osm_timestamp,
        seconds=time.perf_counter() - started,
    )

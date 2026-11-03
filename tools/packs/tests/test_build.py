"""End-to-end: build tests/vectors/mini.osm and compare with the committed mini.pack.

Regenerate the vector (from tools/packs, with the venv active) when the format
or mini.osm changes, and commit it together with docs/07-pack-format.md:

    python -m drivalry_packs build --region test-mini --region-name "Mini test vector" \
        --source file://mini.osm --input tests/vectors/mini.osm --out tests/vectors \
        --built-at 2026-11-02T00:00:00Z
    mv tests/vectors/test-mini.pack tests/vectors/mini.pack
"""

import sqlite3
from pathlib import Path

import pytest

from drivalry_packs import BUILDER
from drivalry_packs.build import build_pack
from drivalry_packs.encoding import PackWay, decode_tile, pack_flags
from drivalry_packs.index import build_index

VECTORS = Path(__file__).parent / "vectors"
BUILT_AT = "2026-11-02T00:00:00Z"
SQLITE_VERSION_FIELD = slice(96, 100)
"""Header bytes holding the SQLite library version that last wrote the file."""


def _without_sqlite_version(data: bytes) -> bytes:
    return data[: SQLITE_VERSION_FIELD.start] + b"\0\0\0\0" + data[SQLITE_VERSION_FIELD.stop :]


@pytest.fixture(scope="module")
def built(tmp_path_factory):
    out = tmp_path_factory.mktemp("mini") / "mini.pack"
    stats = build_pack(
        VECTORS / "mini.osm",
        out,
        region="test-mini",
        region_name="Mini test vector",
        source_url="file://mini.osm",
        built_at=BUILT_AT,
    )
    return out, stats


def _read(pack: Path):
    connection = sqlite3.connect(pack.resolve().as_uri() + "?mode=ro", uri=True)
    try:
        meta = dict(connection.execute("SELECT key, value FROM meta"))
        names = dict(connection.execute("SELECT name_id, name FROM names ORDER BY name_id"))
        tiles = {
            cell: decode_tile(blob, names)
            for cell, blob in connection.execute("SELECT geohash, ways FROM tiles ORDER BY geohash")
        }
        tables = [row[0] for row in connection.execute("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name")]
        page_size = connection.execute("PRAGMA page_size").fetchone()[0]
    finally:
        connection.close()
    return meta, names, tiles, tables, page_size


def test_matches_committed_vector(built):
    out, _ = built
    actual, expected = out.read_bytes(), (VECTORS / "mini.pack").read_bytes()
    assert len(actual) == len(expected)
    # Byte-identical apart from the SQLite library version stamped in the header,
    # which differs between the machine that generated the vector and CI.
    assert _without_sqlite_version(actual) == _without_sqlite_version(expected)


def test_stats(built):
    _, stats = built
    assert stats.way_count == 17
    assert stats.tile_count == 5
    assert stats.osm_timestamp == ""  # OSM XML carries no replication timestamp
    assert stats.bbox == (38.9, -77.12, 38.919, -76.94)
    assert stats.bytes > 0 and stats.seconds > 0


def test_container_and_meta(built):
    out, _ = built
    meta, names, tiles, tables, page_size = _read(out)
    assert tables == ["meta", "names", "tiles"]
    assert page_size == 4096
    assert meta == {
        "schema_version": "1",
        "region": "test-mini",
        "region_name": "Mini test vector",
        "source": "file://mini.osm",
        "osm_replication_timestamp": "",
        "built_at": BUILT_AT,
        "builder": BUILDER,
        "way_count": "17",
        "tile_count": "5",
        "geohash_precision": "5",
        "bbox": "38.900000,-77.120000,38.919000,-76.940000",
    }
    assert list(names.items()) == list(
        enumerate(
            ["Alley Service", "Circle", "I-395", "Long Pike", "Metric Avenue",
             "Nolimit Lane", "Oak Street", "Split Road", "Zone Street", "Émile Way"],
            start=1,
        )
    )


def test_tiles_and_ways(built):
    out, _ = built
    _, _, tiles, _, _ = _read(out)
    assert set(tiles) == {"dqcjm", "dqcjq", "dqcjr", "dqcm2", "dqcm3"}
    main = {way.way_id: way for way in tiles["dqcjr"]}
    assert [way.way_id for way in tiles["dqcjr"]] == sorted(main)
    assert sorted(main) == [101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 113, 114, 116, 117, 118, 119, 120]
    for cell in ("dqcjm", "dqcjq", "dqcm2", "dqcm3"):
        assert [way.way_id for way in tiles[cell]] == [114]
        assert tiles[cell][0] == main[114]

    tag = pack_flags(0, 1, True, False)
    assert main[101] == PackWay(101, 5, "Oak Street", 25, None, tag, ((38900000, -77030000), (38900000, -77028000)))
    assert main[102] == PackWay(102, 3, "Metric Avenue", 50, None, pack_flags(0, 1, False, False), ((38901000, -77030000), (38901000, -77028000)))
    assert (main[103].forward, main[103].backward, main[103].flags) == (45, 35, tag)
    assert (main[104].cls, main[104].name, main[104].forward, main[104].backward, main[104].flags) == (4, None, None, 30, tag)
    assert (main[105].forward, main[105].backward, main[105].flags) == (None, None, 0)
    assert (main[106].forward, main[106].flags) == (20, pack_flags(0, 2, True, False))
    assert main[107].flags == pack_flags(1, 1, True, False)
    assert main[108].flags == pack_flags(2, 1, True, False)
    assert (main[109].cls, main[109].name, main[109].forward, main[109].flags) == (0, "I-395", 55, pack_flags(1, 1, True, False))
    assert (main[110].flags, len(main[110].points)) == (pack_flags(1, 0, False, True), 5)
    assert main[110].points[0] == main[110].points[-1]
    assert (main[113].cls, main[113].name, main[113].flags) == (6, "Alley Service", 0)
    assert (main[114].cls, main[114].name, main[114].forward) == (1, "Long Pike", 45)
    assert main[114].points == ((38905000, -77120000), (38905500, -77110000), (38905000, -77100000), (38905000, -76940000))
    assert (main[116].name, main[116].forward, main[116].flags) == ("Émile Way", None, 0)
    assert (main[117].cls, main[117].forward, main[117].flags) == (7, 30, tag)
    assert (main[118].cls, main[118].flags) == (0, 0)
    assert (main[119].cls, main[119].forward, main[119].backward) == (5, 15, None)
    assert (main[120].cls, main[120].forward, main[120].backward, main[120].flags) == (2, 40, None, tag)


def test_keep_minor_service_keeps_the_driveway(tmp_path):
    out = tmp_path / "mini.pack"
    stats = build_pack(VECTORS / "mini.osm", out, "test-mini", "Mini", "file://mini.osm", BUILT_AT, keep_minor_service=True)
    assert stats.way_count == 18
    _, _, tiles, _, _ = _read(out)
    assert 112 in {way.way_id for way in tiles["dqcjr"]}


def test_index_json(built):
    out, _ = built
    index = build_index(out.parent, "https://example.test/releases/download/packs-2026.11", built_at=BUILT_AT)
    assert index["schemaVersion"] == 1
    assert index["builtAt"] == BUILT_AT
    assert len(index["packs"]) == 1
    entry = index["packs"][0]
    assert entry["region"] == "test-mini"
    assert entry["name"] == "Mini test vector"
    assert entry["url"] == "https://example.test/releases/download/packs-2026.11/mini.pack"
    assert entry["bytes"] == out.stat().st_size
    assert len(entry["sha256"]) == 64
    assert entry["osmTimestamp"] == ""
    assert entry["wayCount"] == 17
    assert entry["bbox"] == [38.9, -77.12, 38.919, -76.94]


def test_index_merge_keeps_regions_not_rebuilt(built):
    out, _ = built
    previous = {
        "schemaVersion": 1,
        "builtAt": "2026-10-02T03:00:00Z",
        "packs": [
            {"region": "test-mini", "name": "stale", "url": "old/mini.pack", "bytes": 1, "sha256": "x",
             "osmTimestamp": "", "wayCount": 1, "bbox": None},
            {"region": "us-zz", "name": "Kept", "url": "old/us-zz.pack", "bytes": 2, "sha256": "y",
             "osmTimestamp": "", "wayCount": 2, "bbox": None},
        ],
    }
    index = build_index(out.parent, "https://example.test/new/", merge_from=previous)
    assert [entry["region"] for entry in index["packs"]] == ["test-mini", "us-zz"]
    assert index["packs"][0]["url"] == "https://example.test/new/mini.pack"
    assert index["packs"][1]["url"] == "old/us-zz.pack"
    # A previous index from another schema is ignored.
    previous["schemaVersion"] = 2
    assert [entry["region"] for entry in build_index(out.parent, "u/", merge_from=previous)["packs"]] == ["test-mini"]


def test_index_merge_drops_entries_on_pruned_releases(built, capsys):
    """A merged entry must not point at a monthly release the prune step deletes."""
    out, _ = built

    def entry(region: str, url: str) -> dict:
        return {"region": region, "name": region, "url": url, "bytes": 1, "sha256": "x",
                "osmTimestamp": "", "wayCount": 1, "bbox": None}

    repo = "https://github.com/o/r/releases/download"
    previous = {
        "schemaVersion": 1,
        "builtAt": "2026-10-02T03:00:00Z",
        "packs": [
            entry("us-aa", f"{repo}/packs-2026.08/us-aa.pack"),   # release will be pruned → dropped
            entry("us-bb", f"{repo}/packs-2026.10/us-bb.pack"),   # kept release → kept
            entry("us-cc", "https://mirror.example/us-cc.pack"),  # not a release URL → kept
        ],
    }
    keep = ["packs-2026.11", "packs-2026.10", "packs-2026.09"]
    index = build_index(out.parent, f"{repo}/packs-2026.11/", merge_from=previous, keep_tags=keep)
    assert [e["region"] for e in index["packs"]] == ["test-mini", "us-bb", "us-cc"]
    assert "us-aa (packs-2026.08)" in capsys.readouterr().err
    # Without keep_tags nothing is filtered (local use).
    index = build_index(out.parent, f"{repo}/packs-2026.11/", merge_from=previous)
    assert [e["region"] for e in index["packs"]] == ["test-mini", "us-aa", "us-bb", "us-cc"]


def test_release_tag_of():
    from drivalry_packs.index import release_tag_of

    assert release_tag_of("https://github.com/o/r/releases/download/packs-2026.11/us-dc.pack") == "packs-2026.11"
    assert release_tag_of("https://mirror.example/us-dc.pack") is None

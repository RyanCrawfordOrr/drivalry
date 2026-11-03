"""Geohash vectors and cell arithmetic."""

import pytest

from drivalry_packs.geohash import decode_bbox, encode, neighbors


@pytest.mark.parametrize(
    ("lat", "lon", "precision", "expected"),
    [
        (42.6, -5.6, 5, "ezs42"),
        (57.64911, 10.40744, 11, "u4pruydqqvj"),
        # The White House. -77.0365 lies 0.0004 degrees west of cell dqcjr's edge.
        (38.8977, -77.0365, 5, "dqcjq"),
        (38.8977, -77.0300, 5, "dqcjr"),
        (0.0, 0.0, 5, "s0000"),
        (-89.999, -179.999, 5, "00000"),
        (89.999, 179.999, 5, "zzzzz"),
    ],
)
def test_encode(lat, lon, precision, expected):
    assert encode(lat, lon, precision) == expected


def test_decode_bbox_contains_point_and_roundtrips():
    min_lat, min_lon, max_lat, max_lon = decode_bbox("dqcjr")
    assert min_lat <= 38.90 < max_lat
    assert min_lon <= -77.03 < max_lon
    assert max_lat - min_lat == pytest.approx(180 / 2**12)
    assert max_lon - min_lon == pytest.approx(360 / 2**13)
    assert encode((min_lat + max_lat) / 2, (min_lon + max_lon) / 2, 5) == "dqcjr"


def test_decode_bbox_rejects_bad_characters():
    with pytest.raises(ValueError):
        decode_bbox("dqcja")


def test_neighbors_are_eight_adjacent_cells():
    cells = neighbors("dqcjr")
    assert len(cells) == 8
    assert "dqcjr" not in cells
    assert set(cells) == {"dqcjw", "dqcjx", "dqcm8", "dqcjq", "dqcm2", "dqcjn", "dqcjp", "dqcm0"}
    for cell in cells:
        assert "dqcjr" in neighbors(cell)


def test_neighbors_wrap_longitude_and_clip_at_pole():
    assert len(neighbors(encode(0.0, 179.99, 5))) == 8
    assert len(neighbors("zzzzz")) == 5

"""Tag interpretation: maxspeed parsing, road class, oneway, roundabout, limits."""

import pytest

from drivalry_packs.osm import (
    Limits,
    implied_limit,
    is_roundabout,
    load_zones,
    oneway,
    parse_maxspeed,
    resolve_limits,
    road_class,
)

ZONES = {"US-DC:urban": (20, True), "XX:metric": (50, False)}


@pytest.mark.parametrize(
    ("value", "expected"),
    [
        ("35 mph", (35, True)),
        ("35mph", (35, True)),
        ("35 MPH", (35, True)),
        ("50", (50, False)),
        ("50 km/h", (50, False)),
        ("50 kmh", (50, False)),
        ("50 kph", (50, False)),
        ("20 knots", (37, False)),
        ("35 mph; 25 mph", (35, True)),
        ("30 mph;25 mph", (30, True)),
        ("24.5", (25, False)),
        ("24.4 mph", (24, True)),
        (" 40 ", (40, False)),
        ("none", None),
        ("signals", None),
        ("variable", None),
        ("walk", None),
        ("national", None),
        ("urban", None),
        ("rural", None),
        ("implicit", None),
        ("US:urban", None),
        ("", None),
        ("mph", None),
        ("35 mph extra", None),
    ],
)
def test_parse_maxspeed(value, expected):
    assert parse_maxspeed(value) == expected


@pytest.mark.parametrize(
    ("tags", "expected"),
    [
        ({"highway": "motorway"}, 0),
        ({"highway": "motorway_link"}, 0),
        ({"highway": "trunk_link"}, 1),
        ({"highway": "primary"}, 2),
        ({"highway": "secondary_link"}, 3),
        ({"highway": "tertiary"}, 4),
        ({"highway": "residential"}, 5),
        ({"highway": "living_street"}, 5),
        ({"highway": "service"}, 6),
        ({"highway": "service", "service": "alley"}, 6),
        ({"highway": "unclassified"}, 7),
        ({"highway": "road"}, 7),
        ({"highway": "footway"}, None),
        ({"highway": "track"}, None),
        ({"highway": "cycleway"}, None),
        ({"highway": "pedestrian"}, None),
        ({"highway": "construction"}, None),
        ({"highway": "busway"}, None),
        ({"highway": "no"}, None),
        ({"name": "No highway tag"}, None),
        ({"highway": "residential", "area": "yes"}, None),
        ({"highway": "service", "service": "driveway"}, None),
        ({"highway": "service", "service": "parking_aisle"}, None),
        ({"highway": "service", "service": "drive-through"}, None),
        ({"highway": "service", "service": "emergency_access"}, None),
        ({"highway": "service", "service": "alley;driveway"}, None),
    ],
)
def test_road_class(tags, expected):
    assert road_class(tags) == expected


def test_keep_minor_service_flag():
    tags = {"highway": "service", "service": "driveway"}
    assert road_class(tags) is None
    assert road_class(tags, keep_minor_service=True) == 6
    assert road_class({"highway": "footway"}, keep_minor_service=True) is None


@pytest.mark.parametrize(
    ("tags", "highway", "expected"),
    [
        ({}, "residential", 0),
        ({"oneway": "yes"}, "residential", 1),
        ({"oneway": "1"}, "residential", 1),
        ({"oneway": "true"}, "residential", 1),
        ({"oneway": "-1"}, "residential", 2),
        ({"oneway": "reverse"}, "residential", 2),
        ({"oneway": "no"}, "residential", 0),
        ({}, "motorway", 1),
        ({}, "motorway_link", 1),
        ({"oneway": "no"}, "motorway", 0),
        ({"oneway": "-1"}, "motorway", 2),
        ({"junction": "roundabout"}, "residential", 1),
        ({"junction": "circular"}, "tertiary", 1),
        ({"junction": "roundabout", "oneway": "no"}, "residential", 0),
        ({"oneway": "reversible"}, "residential", 0),
    ],
)
def test_oneway(tags, highway, expected):
    assert oneway(tags, highway) == expected


def test_is_roundabout():
    assert is_roundabout({"junction": "roundabout"})
    assert is_roundabout({"junction": "circular"})
    assert not is_roundabout({"junction": "jughandle"})
    assert not is_roundabout({})


def test_implied_limit_prefers_maxspeed_type_then_source():
    assert implied_limit({"maxspeed:type": "US-DC:urban"}, ZONES) == (20, True)
    assert implied_limit({"source:maxspeed": "XX:metric"}, ZONES) == (50, False)
    assert implied_limit({"maxspeed:type": "sign", "source:maxspeed": "XX:metric"}, ZONES) == (50, False)
    assert implied_limit({"maxspeed:type": "US:urban"}, ZONES) is None
    assert implied_limit({}, ZONES) is None


def test_load_zones_skips_comment_keys():
    zones = load_zones()
    assert zones["US-DC:urban"] == (20, True)
    assert not any(key.startswith("_") for key in zones)


@pytest.mark.parametrize(
    ("tags", "expected"),
    [
        ({}, Limits(None, None, 0, False)),
        ({"maxspeed": "25 mph"}, Limits(25, None, 1, True)),
        ({"maxspeed": "50"}, Limits(50, None, 1, False)),
        ({"maxspeed:forward": "45 mph", "maxspeed:backward": "35 mph"}, Limits(45, 35, 1, True)),
        ({"maxspeed": "45 mph", "maxspeed:backward": "35 mph"}, Limits(45, 35, 1, True)),
        ({"maxspeed:backward": "30 mph"}, Limits(None, 30, 1, True)),
        ({"maxspeed": "15 mph", "maxspeed:backward": "15 mph"}, Limits(15, None, 1, True)),
        ({"maxspeed:forward": "40 mph"}, Limits(40, None, 1, True)),
        ({"maxspeed": "none"}, Limits(None, None, 0, False)),
        ({"maxspeed": "none", "maxspeed:type": "sign"}, Limits(None, None, 0, False)),
        ({"maxspeed:type": "US-DC:urban"}, Limits(20, None, 2, True)),
        ({"maxspeed": "none", "maxspeed:type": "US-DC:urban"}, Limits(20, None, 2, True)),
        ({"maxspeed": "25 mph", "maxspeed:type": "US-DC:urban"}, Limits(25, None, 1, True)),
        # Mixed units are stored in the forward unit (rare in practice).
        ({"maxspeed": "30 mph", "maxspeed:backward": "40"}, Limits(30, 25, 1, True)),
    ],
)
def test_resolve_limits(tags, expected):
    assert resolve_limits(tags, ZONES) == expected

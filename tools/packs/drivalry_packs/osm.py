"""Interpretation of OSM tags: road class, oneway, roundabout and speed limits.

Implements `docs/07-pack-format.md` §3 (road class), §4 (oneway) and §5
(maxspeed parsing). Functions take any object with a `dict`-like `get`, so
they work on pyosmium `TagList`s and on plain dicts in tests.
"""

from __future__ import annotations

import json
import math
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping, Optional, Protocol


class Tags(Protocol):
    """The subset of `Mapping[str, str]` that pyosmium's `TagList` also offers."""

    def get(self, key: str, default: Optional[str] = None) -> Optional[str]: ...


Zones = Mapping[str, tuple[int, bool]]
"""Zone name (e.g. `US-DC:urban`) -> (posted value, is_mph)."""

ZONES_PATH = Path(__file__).resolve().parents[1] / "zones.json"

#: `highway` value -> road class (docs/07 §3). Anything else is dropped.
ROAD_CLASSES: dict[str, int] = {
    "motorway": 0,
    "motorway_link": 0,
    "trunk": 1,
    "trunk_link": 1,
    "primary": 2,
    "primary_link": 2,
    "secondary": 3,
    "secondary_link": 3,
    "tertiary": 4,
    "tertiary_link": 4,
    "residential": 5,
    "living_street": 5,
    "service": 6,
    "unclassified": 7,
    "road": 7,
}

#: `service=*` values dropped unless the builder runs with `keep_minor_service`.
MINOR_SERVICE = frozenset({"driveway", "parking_aisle", "drive-through", "emergency_access"})

ONEWAY_TRUE = frozenset({"yes", "1", "true"})
ONEWAY_FALSE = frozenset({"no", "0", "false"})
ONEWAY_REVERSE = frozenset({"-1", "reverse"})
ONEWAY_IMPLIED_HIGHWAYS = frozenset({"motorway", "motorway_link"})
ROUNDABOUT_JUNCTIONS = frozenset({"roundabout", "circular"})

KMH_PER_MPH = 1.609344
KMH_PER_KNOT = 1.852

_MAXSPEED_RE = re.compile(r"^\s*(\d+(?:\.\d+)?)\s*(mph|km/h|kmh|kph|knots)?\s*$", re.IGNORECASE)


def _round_half_up(value: float) -> int:
    return int(math.floor(value + 0.5))


def parse_maxspeed(value: str) -> tuple[int, bool] | None:
    """Parse one `maxspeed`-style tag value into `(integer, is_mph)`.

    Follows docs/07 §5: `"35 mph"` -> (35, True); `"50"`, `"50 km/h"`, `"50 kmh"`,
    `"50 kph"` -> (50, False); knots are converted to km/h; a `;`-separated list
    yields its first entry; decimals round to the nearest integer. Words such as
    `none`, `signals`, `walk` or zone names give `None`.
    """
    match = _MAXSPEED_RE.match(value.split(";", 1)[0])
    if match is None:
        return None
    number = float(match.group(1))
    unit = (match.group(2) or "").lower()
    if unit == "mph":
        return _round_half_up(number), True
    if unit == "knots":
        return _round_half_up(number * KMH_PER_KNOT), False
    return _round_half_up(number), False


def road_class(tags: Tags, keep_minor_service: bool = False) -> int | None:
    """Return the road class 0-7 for a way, or `None` if the way is dropped.

    Drops ways without a kept `highway` value, ways tagged `area=yes`, and
    (unless `keep_minor_service`) `highway=service` ways whose `service` tag
    names a driveway, parking aisle, drive-through or emergency access.
    """
    highway = tags.get("highway")
    if highway is None:
        return None
    cls = ROAD_CLASSES.get(highway)
    if cls is None or tags.get("area") == "yes":
        return None
    if highway == "service" and not keep_minor_service:
        service = tags.get("service") or ""
        if any(part.strip() in MINOR_SERVICE for part in service.split(";")):
            return None
    return cls


def is_roundabout(tags: Tags) -> bool:
    """True for `junction=roundabout` and `junction=circular`."""
    return tags.get("junction") in ROUNDABOUT_JUNCTIONS


def oneway(tags: Tags, highway: str) -> int:
    """Return 0 (two-way), 1 (oneway in point order) or 2 (oneway against it).

    An explicit `oneway` tag wins. Without one, motorways, motorway links and
    roundabouts are oneway in point order (docs/07 §4).
    """
    value = tags.get("oneway")
    if value in ONEWAY_REVERSE:
        return 2
    if value in ONEWAY_TRUE:
        return 1
    if value in ONEWAY_FALSE:
        return 0
    if highway in ONEWAY_IMPLIED_HIGHWAYS or is_roundabout(tags):
        return 1
    return 0


def load_zones(path: Path = ZONES_PATH) -> dict[str, tuple[int, bool]]:
    """Load `zones.json`. Keys starting with `_` are documentation and skipped."""
    with path.open(encoding="utf-8") as handle:
        raw = json.load(handle)
    return {
        zone: (int(entry["value"]), bool(entry["mph"]))
        for zone, entry in raw.items()
        if not zone.startswith("_")
    }


def implied_limit(tags: Tags, zones: Zones) -> tuple[int, bool] | None:
    """Limit implied by `maxspeed:type` or `source:maxspeed` naming a known zone."""
    for key in ("maxspeed:type", "source:maxspeed"):
        zone = tags.get(key)
        if zone is not None and zone in zones:
            return zones[zone]
    return None


@dataclass(frozen=True)
class Limits:
    """Resolved speed limits of one way, in the posted unit.

    `backward` is `None` when the backward limit equals the forward one or is
    absent. `src` is the 2-bit source code of docs/07 §4 (0 none, 1 tag, 2 implied).
    """

    forward: int | None
    backward: int | None
    src: int
    mph: bool


def _convert(limit: tuple[int, bool], to_mph: bool) -> int:
    value, is_mph = limit
    if is_mph == to_mph:
        return value
    return _round_half_up(value / KMH_PER_MPH if to_mph else value * KMH_PER_MPH)


def _parse_tag(tags: Tags, key: str) -> tuple[int, bool] | None:
    value = tags.get(key)
    return None if value is None else parse_maxspeed(value)


def resolve_limits(tags: Tags, zones: Zones) -> Limits:
    """Combine `maxspeed`, `maxspeed:forward`, `maxspeed:backward` and zones.

    Forward comes from `maxspeed:forward`, else `maxspeed`. Both directions are
    stored in the unit of the forward value (the rare mixed-unit way has its
    backward value converted). Zones are consulted only when no numeric tag
    parsed, in which case the result is `src = 2`.
    """
    forward = _parse_tag(tags, "maxspeed:forward") or _parse_tag(tags, "maxspeed")
    backward = _parse_tag(tags, "maxspeed:backward")
    if forward is None and backward is None:
        implied = implied_limit(tags, zones)
        if implied is None:
            return Limits(None, None, 0, False)
        return Limits(implied[0], None, 2, implied[1])
    mph = (forward or backward)[1]  # type: ignore[index]
    forward_value = forward[0] if forward else None
    backward_value = _convert(backward, mph) if backward else None
    if backward_value is not None and backward_value == forward_value:
        backward_value = None
    return Limits(forward_value, backward_value, 1, mph)

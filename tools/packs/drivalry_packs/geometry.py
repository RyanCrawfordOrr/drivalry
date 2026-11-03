"""Polyline geometry: Douglas-Peucker simplification and geohash cell coverage.

Points are `(lat, lon)` in degrees. Distances use an equirectangular
approximation with longitude scaled by `cos(mean latitude)`, which is accurate
to well under a percent at the scale of a single way.
"""

from __future__ import annotations

import math
from collections.abc import Sequence

from .geohash import encode

EARTH_RADIUS_M = 6_371_000.0
METRES_PER_DEGREE = math.pi * EARTH_RADIUS_M / 180.0

Point = tuple[float, float]


def _segment_distance_sq(p: Point, a: Point, b: Point) -> float:
    """Squared distance from `p` to segment `a`-`b`, all in the same planar units."""
    dx = b[0] - a[0]
    dy = b[1] - a[1]
    length_sq = dx * dx + dy * dy
    if length_sq == 0.0:
        t = 0.0
    else:
        t = ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / length_sq
        t = min(1.0, max(0.0, t))
    ex = p[0] - (a[0] + t * dx)
    ey = p[1] - (a[1] + t * dy)
    return ex * ex + ey * ey


def simplify(points: Sequence[Point], tolerance_m: float) -> list[Point]:
    """Douglas-Peucker simplification keeping points farther than `tolerance_m`.

    The tolerance is converted to degrees of latitude and longitudes are
    scaled by `cos(mean latitude)`, as docs/07 §2 requires. The first and last
    points are always kept. Distances are measured to the segment, not the
    infinite line, so closed ways (first point == last point) simplify sanely.
    """
    count = len(points)
    if count <= 2:
        return list(points)
    mean_lat = sum(p[0] for p in points) / count
    scale = math.cos(math.radians(mean_lat))
    planar = [(lat, lon * scale) for lat, lon in points]
    tolerance_sq = (tolerance_m / METRES_PER_DEGREE) ** 2

    keep = [False] * count
    keep[0] = keep[-1] = True
    stack = [(0, count - 1)]
    while stack:
        start, end = stack.pop()
        farthest = -1
        farthest_sq = tolerance_sq
        for index in range(start + 1, end):
            distance_sq = _segment_distance_sq(planar[index], planar[start], planar[end])
            if distance_sq > farthest_sq:
                farthest, farthest_sq = index, distance_sq
        if farthest >= 0:
            keep[farthest] = True
            stack.append((start, farthest))
            stack.append((farthest, end))
    return [point for point, kept in zip(points, keep) if kept]


def segment_length_m(a: Point, b: Point) -> float:
    """Approximate length in metres of the segment `a`-`b`."""
    mean_lat = math.radians((a[0] + b[0]) / 2)
    dlat = (b[0] - a[0]) * METRES_PER_DEGREE
    dlon = (b[1] - a[1]) * METRES_PER_DEGREE * math.cos(mean_lat)
    return math.hypot(dlat, dlon)


def cells_for_way(points: Sequence[Point], precision: int = 5, step_m: float = 500.0) -> set[str]:
    """Geohash cells a polyline passes through.

    Every segment is sampled every `step_m` metres plus both endpoints
    (docs/07 §1), so a cell narrower than `step_m` could only be missed by a
    segment that clips its corner.
    """
    cells: set[str] = set()
    for a, b in zip(points, points[1:]):
        cells.add(encode(a[0], a[1], precision))
        steps = math.ceil(segment_length_m(a, b) / step_m)
        for i in range(1, steps):
            t = i / steps
            cells.add(encode(a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, precision))
    if points:
        cells.add(encode(points[-1][0], points[-1][1], precision))
    return cells


def bbox(points: Sequence[Point]) -> tuple[float, float, float, float]:
    """`(min_lat, min_lon, max_lat, max_lon)` of a non-empty point sequence."""
    lats = [p[0] for p in points]
    lons = [p[1] for p in points]
    return min(lats), min(lons), max(lats), max(lons)

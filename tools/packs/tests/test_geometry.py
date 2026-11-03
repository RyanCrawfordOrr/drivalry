"""Douglas-Peucker simplification and geohash coverage of polylines."""

import pytest

from drivalry_packs.geohash import encode
from drivalry_packs.geometry import bbox, cells_for_way, segment_length_m, simplify


def test_simplify_keeps_endpoints_and_drops_near_collinear_points():
    points = [
        (38.9050, -77.1200),
        (38.9055, -77.1100),  # 55 m bend: kept
        (38.9050, -77.1000),  # end of the bend: kept
        (38.9050, -77.0500),  # exactly collinear: dropped
        (38.905001, -77.0000),  # 0.1 m off: dropped
        (38.9050, -76.9400),
    ]
    assert simplify(points, 2.0) == [points[0], points[1], points[2], points[5]]


def test_simplify_short_inputs_unchanged():
    assert simplify([], 2.0) == []
    assert simplify([(1.0, 2.0)], 2.0) == [(1.0, 2.0)]
    assert simplify([(1.0, 2.0), (1.0, 2.0)], 2.0) == [(1.0, 2.0), (1.0, 2.0)]


def test_simplify_closed_way_keeps_real_corners():
    square = [(38.91, -77.03), (38.911, -77.03), (38.911, -77.029), (38.91, -77.029), (38.91, -77.03)]
    assert simplify(square, 2.0) == square


def test_segment_length():
    assert segment_length_m((0.0, 0.0), (1.0, 0.0)) == pytest.approx(111_194.93, abs=0.01)
    assert segment_length_m((38.9, -77.03), (38.9, -77.02)) == pytest.approx(865.3, abs=1.0)


def test_cells_for_way_short_way_single_cell():
    assert cells_for_way([(38.9000, -77.0300), (38.9000, -77.0280)]) == {"dqcjr"}


def test_cells_for_way_long_segment_samples_every_500m():
    # One straight 15.6 km segment, no intermediate nodes: the 500 m sampling
    # must still find every cell between the endpoints.
    start, end = (38.9050, -77.1200), (38.9050, -76.9400)
    cells = cells_for_way([start, end])
    expected = {encode(38.9050, -77.1200 + i * 0.001, 5) for i in range(181)}
    assert cells == expected
    assert len(cells) == 5
    assert encode(*start, 5) in cells and encode(*end, 5) in cells


def test_bbox():
    assert bbox([(1.0, 5.0), (-2.0, 7.0), (0.5, 6.0)]) == (-2.0, 5.0, 1.0, 7.0)

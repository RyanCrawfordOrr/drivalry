"""Tile blob encoding (docs/07 §2): LEB128 varints, zigzag deltas, zlib level 9."""

from __future__ import annotations

import zlib
from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass

BLOB_VERSION = 1
ZLIB_LEVEL = 9

ONEWAY_MASK = 0b0000_0011
SRC_SHIFT = 2
MPH_BIT = 1 << 4
ROUNDABOUT_BIT = 1 << 5


@dataclass(frozen=True)
class PackWay:
    """One way as stored in a tile. Limits are in the posted unit (see `flags`)."""

    way_id: int
    cls: int
    name: str | None
    forward: int | None
    backward: int | None
    flags: int
    points: tuple[tuple[int, int], ...]
    """`(lat_e6, lon_e6)` pairs, at least two."""


def pack_flags(oneway: int, src: int, mph: bool, roundabout: bool) -> int:
    """Assemble the `flags` byte of docs/07 §4."""
    if not 0 <= oneway <= 2 or not 0 <= src <= 2:
        raise ValueError("oneway and src must be 0..2")
    return oneway | (src << SRC_SHIFT) | (MPH_BIT if mph else 0) | (ROUNDABOUT_BIT if roundabout else 0)


def zigzag(value: int) -> int:
    """Map a signed 32-bit integer to an unsigned one: `(n << 1) ^ (n >> 31)`."""
    return (value << 1) ^ (value >> 31)


def unzigzag(value: int) -> int:
    """Inverse of `zigzag`."""
    return (value >> 1) ^ -(value & 1)


def write_varint(buffer: bytearray, value: int) -> None:
    """Append `value` (>= 0) as an unsigned LEB128 varint."""
    if value < 0:
        raise ValueError("varints are unsigned")
    while value >= 0x80:
        buffer.append((value & 0x7F) | 0x80)
        value >>= 7
    buffer.append(value)


def read_varint(data: bytes, pos: int) -> tuple[int, int]:
    """Read an unsigned LEB128 varint at `pos`; return `(value, next_pos)`."""
    result = 0
    shift = 0
    while True:
        byte = data[pos]
        pos += 1
        result |= (byte & 0x7F) << shift
        if byte < 0x80:
            return result, pos
        shift += 7


def encode_way(way: PackWay, name_ids: Mapping[str, int]) -> bytes:
    """Encode one way record (everything after the tile header)."""
    if len(way.points) < 2:
        raise ValueError(f"way {way.way_id} has fewer than two points")
    buffer = bytearray()
    write_varint(buffer, way.way_id)
    buffer.append(way.cls)
    write_varint(buffer, 0 if way.name is None else name_ids[way.name] + 1)
    write_varint(buffer, 0 if way.forward is None else way.forward + 1)
    write_varint(buffer, 0 if way.backward is None else way.backward + 1)
    buffer.append(way.flags)
    write_varint(buffer, len(way.points))
    prev_lat, prev_lon = way.points[0]
    write_varint(buffer, zigzag(prev_lat))
    write_varint(buffer, zigzag(prev_lon))
    for lat, lon in way.points[1:]:
        write_varint(buffer, zigzag(lat - prev_lat))
        write_varint(buffer, zigzag(lon - prev_lon))
        prev_lat, prev_lon = lat, lon
    return bytes(buffer)


def assemble_tile(records: Sequence[tuple[int, bytes]]) -> bytes:
    """Build an uncompressed tile from `(way_id, encoded way)` pairs, sorted by id."""
    buffer = bytearray([BLOB_VERSION])
    write_varint(buffer, len(records))
    for _, record in sorted(records, key=lambda item: item[0]):
        buffer += record
    return bytes(buffer)


def encode_tile(ways: Iterable[PackWay], name_ids: Mapping[str, int]) -> bytes:
    """Encode ways into an uncompressed tile blob. `name_ids` maps name -> `names.name_id`."""
    return assemble_tile([(way.way_id, encode_way(way, name_ids)) for way in ways])


def compress_tile(data: bytes) -> bytes:
    """zlib (RFC 1950) level-9 compression of an uncompressed tile."""
    return zlib.compress(data, ZLIB_LEVEL)


def decode_tile(blob: bytes, names: Mapping[int, str]) -> list[PackWay]:
    """Decompress and parse a tile blob. `names` maps `names.name_id` -> name."""
    data = zlib.decompress(blob)
    if data[0] != BLOB_VERSION:
        raise ValueError(f"unknown blob version {data[0]}")
    way_count, pos = read_varint(data, 1)
    ways: list[PackWay] = []
    for _ in range(way_count):
        way_id, pos = read_varint(data, pos)
        cls = data[pos]
        pos += 1
        name_plus_one, pos = read_varint(data, pos)
        forward_plus_one, pos = read_varint(data, pos)
        backward_plus_one, pos = read_varint(data, pos)
        flags = data[pos]
        pos += 1
        point_count, pos = read_varint(data, pos)
        lat, pos = read_varint(data, pos)
        lon, pos = read_varint(data, pos)
        lat, lon = unzigzag(lat), unzigzag(lon)
        points = [(lat, lon)]
        for _ in range(point_count - 1):
            dlat, pos = read_varint(data, pos)
            dlon, pos = read_varint(data, pos)
            lat += unzigzag(dlat)
            lon += unzigzag(dlon)
            points.append((lat, lon))
        ways.append(
            PackWay(
                way_id=way_id,
                cls=cls,
                name=None if name_plus_one == 0 else names[name_plus_one - 1],
                forward=None if forward_plus_one == 0 else forward_plus_one - 1,
                backward=None if backward_plus_one == 0 else backward_plus_one - 1,
                flags=flags,
                points=tuple(points),
            )
        )
    if pos != len(data):
        raise ValueError(f"{len(data) - pos} trailing bytes in tile")
    return ways

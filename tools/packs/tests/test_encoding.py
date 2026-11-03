"""Varints, zigzag, flags and the tile encode/decode round trip."""

import zlib

import pytest

from drivalry_packs.encoding import (
    BLOB_VERSION,
    PackWay,
    compress_tile,
    decode_tile,
    encode_tile,
    pack_flags,
    read_varint,
    unzigzag,
    write_varint,
    zigzag,
)


@pytest.mark.parametrize(
    ("value", "expected"),
    [
        (0, b"\x00"),
        (1, b"\x01"),
        (127, b"\x7f"),
        (128, b"\x80\x01"),
        (300, b"\xac\x02"),
        (16_383, b"\xff\x7f"),
        (16_384, b"\x80\x80\x01"),
        (2**32 - 1, b"\xff\xff\xff\xff\x0f"),
    ],
)
def test_write_varint(value, expected):
    buffer = bytearray()
    write_varint(buffer, value)
    assert bytes(buffer) == expected
    assert read_varint(bytes(buffer), 0) == (value, len(expected))


def test_write_varint_rejects_negative():
    with pytest.raises(ValueError):
        write_varint(bytearray(), -1)


@pytest.mark.parametrize(
    ("value", "expected"),
    [(0, 0), (-1, 1), (1, 2), (-2, 3), (2, 4), (2147483647, 4294967294), (-2147483648, 4294967295)],
)
def test_zigzag(value, expected):
    assert zigzag(value) == expected
    assert unzigzag(expected) == value


def test_pack_flags():
    assert pack_flags(0, 0, False, False) == 0
    assert pack_flags(1, 1, True, False) == 0b01_0101
    assert pack_flags(2, 2, False, True) == 0b10_1010
    assert pack_flags(1, 0, False, True) == 0b10_0001
    with pytest.raises(ValueError):
        pack_flags(3, 0, False, False)


WAYS = [
    PackWay(1002, 5, "Oak Street", 25, None, pack_flags(0, 1, True, False), ((38900000, -77030000), (38900000, -77028000))),
    PackWay(1001, 2, None, 45, 35, pack_flags(1, 1, True, False), ((38902000, -77030000), (38902100, -77029000), (38901900, -77028000))),
    PackWay(1003, 0, "Ring", None, None, pack_flags(1, 0, False, True), ((0, 0), (-1, 1), (0, 0))),
]
NAME_IDS = {"Oak Street": 2, "Ring": 1}


def test_encode_tile_layout_and_sort_order():
    data = encode_tile(WAYS, NAME_IDS)
    assert data[0] == BLOB_VERSION
    assert data[1] == 3  # way_count
    # First way is 1001 (sorted), id varint 0xe9 0x07, cls 2, no name, max 46, maxb 36, flags, 3 points.
    assert data[2:10] == bytes([0xE9, 0x07, 2, 0, 46, 36, pack_flags(1, 1, True, False), 3])


def test_tile_round_trip():
    blob = compress_tile(encode_tile(WAYS, NAME_IDS))
    assert blob[:1] == b"\x78"  # zlib header
    assert zlib.decompress(blob) == encode_tile(WAYS, NAME_IDS)
    decoded = decode_tile(blob, {id_: name for name, id_ in NAME_IDS.items()})
    assert decoded == sorted(WAYS, key=lambda way: way.way_id)


def test_encode_rejects_single_point_way():
    way = PackWay(1, 5, None, None, None, 0, ((0, 0),))
    with pytest.raises(ValueError):
        encode_tile([way], {})


def test_decode_rejects_unknown_version():
    with pytest.raises(ValueError):
        decode_tile(compress_tile(b"\x02\x00"), {})

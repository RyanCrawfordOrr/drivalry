"""Niemeyer geohash encoding (docs/07 §1): base-32 alphabet, longitude bit first."""

from __future__ import annotations

BASE32 = "0123456789bcdefghjkmnpqrstuvwxyz"
_DECODE = {char: index for index, char in enumerate(BASE32)}


def encode(lat: float, lon: float, precision: int = 5) -> str:
    """Encode a WGS-84 point to a geohash of `precision` characters."""
    lat_lo, lat_hi = -90.0, 90.0
    lon_lo, lon_hi = -180.0, 180.0
    chars: list[str] = []
    bits = 0
    value = 0
    even = True
    while len(chars) < precision:
        if even:
            mid = (lon_lo + lon_hi) / 2
            if lon >= mid:
                value = value * 2 + 1
                lon_lo = mid
            else:
                value *= 2
                lon_hi = mid
        else:
            mid = (lat_lo + lat_hi) / 2
            if lat >= mid:
                value = value * 2 + 1
                lat_lo = mid
            else:
                value *= 2
                lat_hi = mid
        even = not even
        bits += 1
        if bits == 5:
            chars.append(BASE32[value])
            bits = 0
            value = 0
    return "".join(chars)


def decode_bbox(geohash: str) -> tuple[float, float, float, float]:
    """Return the cell bounds `(min_lat, min_lon, max_lat, max_lon)` of a geohash."""
    lat_lo, lat_hi = -90.0, 90.0
    lon_lo, lon_hi = -180.0, 180.0
    even = True
    for char in geohash:
        try:
            value = _DECODE[char]
        except KeyError as exc:
            raise ValueError(f"invalid geohash character {char!r}") from exc
        for shift in (16, 8, 4, 2, 1):
            bit = value & shift
            if even:
                mid = (lon_lo + lon_hi) / 2
                if bit:
                    lon_lo = mid
                else:
                    lon_hi = mid
            else:
                mid = (lat_lo + lat_hi) / 2
                if bit:
                    lat_lo = mid
                else:
                    lat_hi = mid
            even = not even
    return lat_lo, lon_lo, lat_hi, lon_hi


def neighbors(geohash: str) -> list[str]:
    """Return the up-to-eight distinct cells touching `geohash`, same precision.

    Longitude wraps at the antimeridian; cells beyond a pole are omitted.
    """
    min_lat, min_lon, max_lat, max_lon = decode_bbox(geohash)
    height = max_lat - min_lat
    width = max_lon - min_lon
    center_lat = (min_lat + max_lat) / 2
    center_lon = (min_lon + max_lon) / 2
    result: list[str] = []
    for dlat in (1, 0, -1):
        for dlon in (-1, 0, 1):
            if dlat == 0 and dlon == 0:
                continue
            lat = center_lat + dlat * height
            if not -90.0 <= lat <= 90.0:
                continue
            lon = center_lon + dlon * width
            if lon >= 180.0:
                lon -= 360.0
            elif lon < -180.0:
                lon += 360.0
            cell = encode(lat, lon, len(geohash))
            if cell != geohash and cell not in result:
                result.append(cell)
    return result

"""Drivalry speed-limit pack builder.

Turns an OpenStreetMap extract into a `.pack` SQLite file in the schema-1 format
described in `docs/07-pack-format.md`. The Dart reader in `packages/drivalry_packs`
consumes the output; both are tested against `tests/vectors/mini.pack`.
"""

from __future__ import annotations

from datetime import datetime, timezone

__version__ = "0.1.0"

SCHEMA_VERSION = 1
GEOHASH_PRECISION = 5
BUILDER = f"drivalry-packs/{__version__}"


def utc_now_iso() -> str:
    """Current UTC time as `YYYY-MM-DDTHH:MM:SSZ`, the timestamp form used in packs."""
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

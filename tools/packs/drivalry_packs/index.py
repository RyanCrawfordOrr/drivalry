"""`index.json` for a release (docs/07 §6), built from a directory of `.pack` files."""

from __future__ import annotations

import hashlib
import json
import re
import sqlite3
import sys
from collections.abc import Iterable
from pathlib import Path
from typing import Any

from . import SCHEMA_VERSION, utc_now_iso


def read_meta(pack_path: Path) -> dict[str, str]:
    """Return the `meta` table of a pack, opened read-only."""
    connection = sqlite3.connect(pack_path.resolve().as_uri() + "?mode=ro", uri=True)
    try:
        return dict(connection.execute("SELECT key, value FROM meta"))
    finally:
        connection.close()


def sha256_of(path: Path) -> str:
    """Hex SHA-256 of a file, streamed."""
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


_RELEASE_TAG = re.compile(r"/releases/download/([^/]+)/")


def release_tag_of(url: str) -> str | None:
    """The GitHub release tag a download URL points at, or None."""
    match = _RELEASE_TAG.search(url)
    return match.group(1) if match else None


def build_index(
    packs_dir: str | Path,
    base_url: str,
    built_at: str | None = None,
    merge_from: dict[str, Any] | None = None,
    keep_tags: Iterable[str] | None = None,
) -> dict[str, Any]:
    """Describe every `*.pack` in `packs_dir`; URLs are `base_url` + file name.

    `merge_from` is a previous index whose entries are kept for regions that
    have no pack in `packs_dir`, so a partial rebuild never drops a region. It
    is ignored when its `schemaVersion` differs.

    `keep_tags` lists the release tags that will still exist after the
    workflow prunes old releases. A merged entry whose URL points at a
    `packs-*` release tag outside that list would 404, so it is dropped with a
    warning on stderr. None means "keep every merged entry".
    """
    base = base_url if base_url.endswith("/") else base_url + "/"
    packs: list[dict[str, Any]] = []
    for pack_path in sorted(Path(packs_dir).glob("*.pack")):
        meta = read_meta(pack_path)
        if int(meta["schema_version"]) != SCHEMA_VERSION:
            raise ValueError(f"{pack_path.name}: schema_version {meta['schema_version']} != {SCHEMA_VERSION}")
        bbox = [float(value) for value in meta["bbox"].split(",")] if meta.get("bbox") else None
        packs.append(
            {
                "region": meta["region"],
                "name": meta["region_name"],
                "url": base + pack_path.name,
                "bytes": pack_path.stat().st_size,
                "sha256": sha256_of(pack_path),
                "osmTimestamp": meta["osm_replication_timestamp"],
                "wayCount": int(meta["way_count"]),
                "bbox": bbox,
            }
        )
    if merge_from and merge_from.get("schemaVersion") == SCHEMA_VERSION:
        present = {entry["region"] for entry in packs}
        kept = None if keep_tags is None else set(keep_tags)
        dropped: list[str] = []
        for entry in merge_from.get("packs", []):
            if entry["region"] in present:
                continue
            tag = release_tag_of(entry.get("url", ""))
            if kept is not None and tag is not None and tag.startswith("packs-") and tag not in kept:
                dropped.append(f"{entry['region']} ({tag})")
                continue
            packs.append(entry)
        if dropped:
            print(
                "index: dropped merged entries whose release will be pruned: " + ", ".join(dropped),
                file=sys.stderr,
            )
    packs.sort(key=lambda entry: entry["region"])
    return {"schemaVersion": SCHEMA_VERSION, "builtAt": built_at or utc_now_iso(), "packs": packs}


def read_index(path: str | Path) -> dict[str, Any]:
    """Load a previously written `index.json`."""
    with Path(path).open(encoding="utf-8") as handle:
        return json.load(handle)


def write_index(index: dict[str, Any], out_path: str | Path) -> None:
    """Write `index` as pretty-printed UTF-8 JSON with a trailing newline."""
    Path(out_path).write_text(json.dumps(index, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

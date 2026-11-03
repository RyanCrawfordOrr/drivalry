"""Command line: `python -m drivalry_packs {build,download,index,regions}`."""

from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

from . import __version__
from .build import build_pack
from .index import build_index, read_index, write_index

REGIONS_PATH = Path(__file__).resolve().parents[1] / "regions.json"
GEOFABRIK_BASE = "https://download.geofabrik.de/"
CHUNK_BYTES = 1 << 20


def load_regions() -> dict[str, dict[str, str]]:
    """Load `regions.json`: code -> `{"name", "geofabrik"}`."""
    with REGIONS_PATH.open(encoding="utf-8") as handle:
        return json.load(handle)


def geofabrik_url(region: dict[str, str]) -> str:
    """The `-latest.osm.pbf` URL for a `regions.json` entry."""
    return f"{GEOFABRIK_BASE}{region['geofabrik']}-latest.osm.pbf"


def download(url: str, dest_dir: Path) -> Path:
    """Download `url` into `dest_dir`, resuming a partial `.part` file if present.

    Returns the final path. An existing complete file is reused as is; delete
    it to fetch a fresher extract.
    """
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest = dest_dir / url.rsplit("/", 1)[1]
    if dest.exists():
        return dest
    part = dest.with_name(dest.name + ".part")
    offset = part.stat().st_size if part.exists() else 0

    request = urllib.request.Request(url, headers={"User-Agent": f"drivalry-packs/{__version__}"})
    if offset:
        request.add_header("Range", f"bytes={offset}-")
    try:
        response = urllib.request.urlopen(request, timeout=120)
    except urllib.error.HTTPError as error:
        if error.code == 416 and offset:  # range not satisfiable: the .part is already complete
            part.replace(dest)
            return dest
        raise
    with response:
        if response.status == 206:
            mode = "ab"
        else:  # server ignored the range; start over
            mode, offset = "wb", 0
        total = offset + int(response.headers.get("Content-Length") or 0)
        done = offset
        with part.open(mode) as handle:
            while chunk := response.read(CHUNK_BYTES):
                handle.write(chunk)
                done += len(chunk)
                if total:
                    print(f"\r{dest.name}: {done / 1e6:,.0f} / {total / 1e6:,.0f} MB", end="", file=sys.stderr)
        print(file=sys.stderr)
    part.replace(dest)
    return dest


def cmd_build(args: argparse.Namespace) -> None:
    region = load_regions().get(args.region)
    region_name = args.region_name or (region["name"] if region else None)
    source = args.source or (geofabrik_url(region) if region else None)
    if region_name is None or source is None:
        sys.exit(f"unknown region {args.region!r}: pass --region-name and --source, or add it to regions.json")
    output = Path(args.out) / f"{args.region}.pack"
    stats = build_pack(
        input_pbf=args.input,
        output_path=output,
        region=args.region,
        region_name=region_name,
        source_url=source,
        built_at=args.built_at,
        keep_minor_service=args.keep_minor_service,
    )
    print(
        f"{output}: {stats.way_count:,} ways, {stats.tile_count:,} tiles, {stats.bytes:,} bytes, "
        f"{stats.seconds:.1f} s, osm {stats.osm_timestamp or 'n/a'}, bbox {stats.bbox}"
    )


def cmd_download(args: argparse.Namespace) -> None:
    regions = load_regions()
    if args.region not in regions:
        sys.exit(f"unknown region {args.region!r}; see `regions`")
    path = download(geofabrik_url(regions[args.region]), Path(args.dest))
    print(path)


def cmd_index(args: argparse.Namespace) -> None:
    previous = read_index(args.merge) if args.merge else None
    keep_tags = [tag.strip() for tag in args.keep_tags.split(",") if tag.strip()] if args.keep_tags else None
    index = build_index(args.packs, args.base_url, args.built_at, previous, keep_tags=keep_tags)
    write_index(index, args.out)
    print(f"{args.out}: {len(index['packs'])} packs")


def cmd_regions(args: argparse.Namespace) -> None:
    for code, region in sorted(load_regions().items()):
        print(f"{code}\t{region['name']}\t{region['geofabrik']}")


def make_parser() -> argparse.ArgumentParser:
    """The argument parser; exposed for `--help` rendering in docs and tests."""
    parser = argparse.ArgumentParser(prog="python -m drivalry_packs", description=__doc__)
    parser.add_argument("--version", action="version", version=f"drivalry-packs {__version__}")
    commands = parser.add_subparsers(dest="command", required=True)

    build = commands.add_parser("build", help="build <out>/<region>.pack from an OSM extract")
    build.add_argument("--region", required=True, help="region code, e.g. us-dc")
    build.add_argument("--input", required=True, help="path to the .osm.pbf (or .osm XML) extract")
    build.add_argument("--out", required=True, help="output directory")
    build.add_argument("--built-at", help="ISO-8601 UTC timestamp to record; default: now")
    build.add_argument("--keep-minor-service", action="store_true", help="keep driveways, parking aisles, ...")
    build.add_argument("--source", help="override the `source` meta value (default: Geofabrik URL)")
    build.add_argument("--region-name", help="override the human name (default: from regions.json)")
    build.set_defaults(func=cmd_build)

    fetch = commands.add_parser("download", help="download a region's Geofabrik extract (resumable)")
    fetch.add_argument("--region", required=True)
    fetch.add_argument("--dest", required=True, help="directory to download into")
    fetch.set_defaults(func=cmd_download)

    index = commands.add_parser("index", help="write index.json for a directory of packs")
    index.add_argument("--packs", required=True, help="directory containing *.pack")
    index.add_argument("--base-url", required=True, help="URL prefix the packs will be served from")
    index.add_argument("--out", required=True, help="path of the index.json to write")
    index.add_argument("--built-at", help="ISO-8601 UTC timestamp to record; default: now")
    index.add_argument("--merge", help="previous index.json whose entries are kept for regions not in --packs")
    index.add_argument(
        "--keep-tags",
        help="comma-separated release tags that will still exist; merged entries pointing at other packs-* tags are dropped",
    )
    index.set_defaults(func=cmd_index)

    regions = commands.add_parser("regions", help="list region codes")
    regions.set_defaults(func=cmd_regions)
    return parser


def main(argv: list[str] | None = None) -> None:
    """Entry point used by `__main__`."""
    args = make_parser().parse_args(argv)
    args.func(args)

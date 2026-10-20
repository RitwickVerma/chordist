"""Command line interface: ``lyricist <command>``.

Handy on its own (``lyricist chords "Radiohead" "Creep"`` prints a chart to the
terminal) and essential for debugging what the widget will actually receive.
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
from typing import Any

from . import __version__, chart, shapes
from .cache import DiskCache
from .config import Config, config_path
from .http import Throttle


def _setup_logging(level: str) -> None:
    logging.basicConfig(
        level=getattr(logging, str(level).upper(), logging.INFO),
        format="%(asctime)s %(levelname)-7s %(name)s: %(message)s",
        datefmt="%H:%M:%S",
    )


def _render_chart(result: dict[str, Any], width: int = 0) -> str:
    """Draw chord-over-lyric text for the terminal."""
    out: list[str] = []
    if result.get("title") or result.get("artist"):
        header = " - ".join(part for part in (result.get("artist"), result.get("title")) if part)
        out.append(header)
        bits = []
        if result.get("key"):
            bits.append(f"key {result['key']}")
        if result.get("capo"):
            bits.append(f"capo {result['capo']}")
        bits.append(f"source {result.get('source')}")
        out.append("(" + ", ".join(bits) + ")")
        out.append("")

    for section in result.get("sections", []):
        if section.get("name"):
            out.append(section["name"].upper())
        for line in section.get("lines", []):
            lyric = line.get("lyric", "")
            chords = sorted(line.get("chords", []), key=lambda c: c["pos"])
            if chords and lyric:
                row = ""
                for chord in chords:
                    pos = max(0, int(chord["pos"]))
                    if pos > len(row):
                        row += " " * (pos - len(row))
                    elif pos < len(row):
                        row += " "
                    row += chord["name"] + " "
                out.append(row.rstrip())
            elif chords:
                out.append("  ".join(chord["name"] for chord in chords))
            out.append(lyric if lyric else "")
        out.append("")
    return "\n".join(out).rstrip() + "\n"


def _render_shapes(names: list[str], color: str) -> str:
    lines: list[str] = []
    for name in names:
        shape = shapes.shape_for(name)
        if not shape:
            lines.append(f"{name}: no fingering known")
            continue
        frets = " ".join("x" if f < 0 else str(f) for f in shape["frets"])
        lines.append(f"{name}: {frets}   (base fret {shape['base']})")
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="lyricist", description="synced lyrics and guitar chords")
    parser.add_argument("--version", action="version", version=f"lyricist {__version__}")
    sub = parser.add_subparsers(dest="command")

    sub.add_parser("serve", help="run the local JSON API the widget uses")
    sub.add_parser("health", help="print service status from the running daemon")

    for name, helptext in (("lyrics", "fetch lyrics"), ("chords", "fetch a chord chart")):
        child = sub.add_parser(name, help=helptext)
        child.add_argument("artist")
        child.add_argument("title")
        child.add_argument("--album", default="")
        child.add_argument("--duration", type=float, default=0.0)
        child.add_argument("--json", action="store_true", help="dump the raw JSON")

    shapes_parser = sub.add_parser("shapes", help="print chord fingerings")
    shapes_parser.add_argument("names", nargs="+")
    shapes_parser.add_argument("--svg", action="store_true")
    shapes_parser.add_argument("--color", default="#ffffff")
    shapes_parser.add_argument("--json", action="store_true")

    local = sub.add_parser("local", help="manage your own chord charts")
    local.add_argument("action", nargs="?", default="list", choices=["list", "path", "add", "rm"])
    local.add_argument("args", nargs="*")

    cache = sub.add_parser("cache", help="inspect or clear caches")
    cache.add_argument("action", nargs="?", default="stats", choices=["stats", "clear"])

    sub.add_parser("config", help="print the configuration file path and values")

    args = parser.parse_args(argv)
    config = Config.load()
    _setup_logging(config.get("log_level", "info"))

    if args.command in (None, "serve"):
        from .server import serve

        serve(config)
        return 0

    if args.command == "health":
        import urllib.request

        url = f"http://{config.get('host')}:{config.get('port')}/api/health"
        try:
            with urllib.request.urlopen(url, timeout=3) as response:
                print(json.dumps(json.loads(response.read()), indent=2))
        except Exception as exc:  # noqa: BLE001
            print(f"lyricistd is not answering at {url}: {exc}", file=sys.stderr)
            return 1
        return 0

    throttle = Throttle(float(config.get("min_request_interval", 0) or 0))

    if args.command == "lyrics":
        from .lyrics import LyricsProvider

        result = LyricsProvider(config, throttle).lookup(args.artist, args.title, args.album, args.duration)
        if args.json:
            print(json.dumps(result, ensure_ascii=False, indent=2))
        else:
            print(f"{result.get('artist')} - {result.get('track')}")
            print(f"source {result.get('source')}  synced {bool(result.get('synced'))}")
            print()
            for line in result.get("lines", []):
                stamp = f"{line['t']:7.2f}" if line.get("t") is not None else "      -"
                print(f"{stamp}  {line.get('text', '')}")
        return 0

    if args.command == "chords":
        from .chords import ChordProvider

        result = ChordProvider(config, throttle).lookup(args.artist, args.title, args.duration)
        if args.json:
            print(json.dumps(result, ensure_ascii=False, indent=2))
        else:
            print(_render_chart(result))
            if result.get("url"):
                print(result["url"])
        return 0

    if args.command == "shapes":
        if args.json:
            print(json.dumps(shapes.shapes_for(args.names), indent=2))
        elif args.svg:
            for name in args.names:
                shape = shapes.shape_for(name)
                if shape:
                    print(shapes.svg(shape, args.color))
        else:
            print(_render_shapes(args.names, args.color), end="")
        return 0

    if args.command == "local":
        from .chords import ChordProvider

        provider = ChordProvider(config, throttle)
        if args.action == "path":
            print(provider.directory)
        elif args.action == "list":
            for item in provider.list_local():
                print(f"{item['slug']:<40} {item['size']:>7} bytes")
        elif args.action == "add":
            if len(args.args) < 3:
                print("usage: lyricist local add ARTIST TITLE FILE", file=sys.stderr)
                return 2
            artist, title, path = args.args[0], args.args[1], args.args[2]
            with open(path, encoding="utf-8") as handle:
                provider.save_local(artist, title, handle.read())
            print(f"saved {artist} - {title}")
        elif args.action == "rm":
            if len(args.args) < 2:
                print("usage: lyricist local rm ARTIST TITLE", file=sys.stderr)
                return 2
            print("removed" if provider.delete_local(args.args[0], args.args[1]) else "nothing matched")
        return 0

    if args.command == "cache":
        for namespace, ttl in (("lyrics", config.get("lyrics_ttl_seconds")), ("chords", config.get("chords_ttl_seconds"))):
            cache = DiskCache(namespace, ttl=int(ttl or 0))
            stats = cache.stats()
            if args.action == "clear":
                removed = cache.clear()
                print(f"{namespace}: cleared {removed} entries")
            else:
                print(f"{namespace}: {stats['entries']} entries, {stats['bytes'] / 1024:.1f} KiB, {stats['dir']}")
        return 0

    if args.command == "config":
        print(json.dumps(config.as_dict(), indent=2, sort_keys=True))
        print(f"\nfile: {config_path()}", file=sys.stderr)
        return 0

    parser.print_help()
    return 0

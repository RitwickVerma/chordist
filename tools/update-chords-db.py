#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: MIT
"""Refresh chordist/data/guitar-chords.json from the chords-db npm package.

chords-db (https://github.com/tombatossals/chords-db, MIT, (c) 2016 David Rubert)
is the fingering database behind the chord diagrams. This keeps what the service
reads (frets, fingers, base fret, barres) and drops the rest (MIDI notes), and
spells sharps as "#" instead of "sharp".

    tools/update-chords-db.py              # downloads the latest with npm
    tools/update-chords-db.py guitar.json  # or use a file you already have
"""

from __future__ import annotations

import json
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

TARGET = Path(__file__).resolve().parent.parent / "chordist" / "data" / "guitar-chords.json"


def load(source: str | None) -> dict:
    if source:
        return json.loads(Path(source).read_text())
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(["npm", "pack", "@tombatossals/chords-db"], cwd=tmp, check=True, capture_output=True)
        archive = next(Path(tmp).glob("*.tgz"))
        with tarfile.open(archive) as tar:
            member = tar.extractfile("package/lib/guitar.json")
            assert member is not None
            return json.load(member)


def main() -> None:
    raw = load(sys.argv[1] if len(sys.argv) > 1 else None)
    out: dict[str, dict[str, list[dict]]] = {}
    for entries in raw["chords"].values():
        for entry in entries:
            key = entry["key"]
            out.setdefault(key, {})[entry["suffix"]] = [
                {
                    "frets": p["frets"],
                    "fingers": p["fingers"],
                    "base": p["baseFret"],
                    "barres": p.get("barres", []),
                }
                for p in entry["positions"]
            ]
    TARGET.write_text(json.dumps(out, separators=(",", ":"), sort_keys=True) + "\n")
    print(f"wrote {TARGET} ({TARGET.stat().st_size // 1024} KiB, {sum(len(v) for v in out.values())} chords)")


if __name__ == "__main__":
    main()

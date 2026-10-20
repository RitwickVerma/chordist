#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
#
# SPDX-License-Identifier: MIT
"""Fail unless a built wheel carries what the service cannot run without."""

from __future__ import annotations

import sys
import zipfile

REQUIRED = (
    "chordist/__init__.py",
    "chordist/cli.py",
    "chordist/server.py",
    "chordist/data/guitar-chords.json",
    "chordist/data/LICENSE.chords-db",
)


def main(path: str) -> int:
    with zipfile.ZipFile(path) as wheel:
        names = set(wheel.namelist())
        missing = [name for name in REQUIRED if name not in names]
        entry = next((n for n in names if n.endswith("entry_points.txt")), None)
        console = wheel.read(entry).decode() if entry else ""
    if "chordist = chordist.cli:main" not in console:
        missing.append("console script `chordist`")
    if missing:
        print("wheel is missing:", ", ".join(missing), file=sys.stderr)
        return 1
    print(f"{path}: ok ({len(names)} files)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))

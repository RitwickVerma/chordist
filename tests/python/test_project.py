# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
#
# SPDX-License-Identifier: MIT

from __future__ import annotations

import json
import tomllib
from pathlib import Path

import chordist

ROOT = Path(__file__).resolve().parents[2]


def test_one_version_everywhere():
    pyproject = tomllib.loads((ROOT / "pyproject.toml").read_text())["project"]["version"]
    applet = json.loads((ROOT / "applet" / "metadata.json").read_text())["KPlugin"]["Version"]
    assert chordist.__version__ == pyproject == applet == (ROOT / "VERSION").read_text().strip()

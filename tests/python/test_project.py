# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
#
# SPDX-License-Identifier: MIT

from __future__ import annotations

import json
import re
import tomllib
from pathlib import Path

import chordist

ROOT = Path(__file__).resolve().parents[2]


def test_one_version_everywhere():
    pyproject = tomllib.loads((ROOT / "pyproject.toml").read_text())["project"]["version"]
    applet = json.loads((ROOT / "applet" / "metadata.json").read_text())["KPlugin"]["Version"]
    assert chordist.__version__ == pyproject == applet == (ROOT / "VERSION").read_text().strip()


def test_the_arch_package_builds_the_same_version():
    pkgbuild = (ROOT / "packaging" / "PKGBUILD").read_text()
    assert f"\npkgver={chordist.__version__}\n" in pkgbuild


def test_every_file_the_widget_points_at_is_in_the_widget():
    """A Qt.resolvedUrl that names a missing file is not an error in QML: the image is just blank (the panel icon
    would vanish without a word). The package ships applet/ whole, so the file has to be in there."""
    refs = []
    for qml in (ROOT / "applet").rglob("*.qml"):
        for target in re.findall(r'Qt\.resolvedUrl\("([^"]+)"\)', qml.read_text()):
            refs.append((qml, target, (qml.parent / target).resolve()))
    assert refs, "no Qt.resolvedUrl references found; the pattern no longer matches the code"
    missing = [f"{q.relative_to(ROOT)}: {t}" for q, t, path in refs if not path.is_file()]
    outside = [f"{q.relative_to(ROOT)}: {t}" for q, t, path in refs if (ROOT / "applet") not in path.parents]
    assert not missing, f"missing files: {missing}"
    assert not outside, f"files outside the widget package: {outside}"


def test_the_panel_draws_the_widgets_own_guitar():
    """Not a theme icon: a theme without one (Breeze) left the panel with a lyrics page."""
    compact = (ROOT / "applet/contents/ui/Compact.qml").read_text()
    assert 'Qt.resolvedUrl("../images/guitar.png")' in compact
    assert 'source: "guitar"' not in compact
    assert (ROOT / "applet/contents/images/guitar.png").read_bytes()[:8] == b"\x89PNG\r\n\x1a\n"


def test_one_icon_everywhere():
    """The guitar is the icon of the panel, the widget list (metadata.json names the installed "chordist" icon),
    both installers and the README, from the one file. A second icon file is how they drift apart."""
    icon = "applet/contents/images/guitar.png"
    assert json.loads((ROOT / "applet/metadata.json").read_text())["KPlugin"]["Icon"] == "chordist"
    makefile = (ROOT / "Makefile").read_text()
    assert re.search(r"^ICON_DIR\s*:=\s*\$\(ICON_BASE\)/512x512/apps$", makefile, re.MULTILINE)
    assert f"install -Dm644 {icon} $(ICON_DIR)/chordist.png" in makefile
    assert f'install -Dm644 {icon} "$pkgdir/usr/share/icons/hicolor/512x512/apps/chordist.png"' in (
        ROOT / "packaging/PKGBUILD"
    ).read_text()
    assert f'<img src="{icon}"' in (ROOT / "README.md").read_text()
    images = [p for p in ROOT.rglob("*") if p.suffix in (".svg", ".png", ".ico")
              and not {".git", ".venv", "build", "dist"} & set(p.parts) and "docs" not in p.relative_to(ROOT).parts]
    assert [p.relative_to(ROOT).as_posix() for p in images] == [icon], images

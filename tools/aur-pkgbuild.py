#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
#
# SPDX-License-Identifier: MIT
"""Write the AUR files (PKGBUILD, chordist.install, .SRCINFO) from packaging/.

packaging/PKGBUILD is the one source of truth: it builds from a local tarball and has no checksum. The AUR copy
differs in exactly three things, all rewritten here: `source` points at the release download URL, `sha256sums`
holds the tarball's real checksum (it cannot live in the repo: the tarball contains the repo), and the header is
cut down to the Maintainer line. `package()` and `depends` are never touched, so they cannot drift.

    tools/aur-pkgbuild.py --tarball dist/chordist-2.0.0.tar.gz --out build/aur
    tools/aur-pkgbuild.py --sha256 <hex> --version 2.0.0 --pkgrel 2 --out build/aur

.SRCINFO comes from `makepkg --printsrcinfo`, so it needs an Arch environment (`--no-srcinfo` skips it).
"""

from __future__ import annotations

import argparse
import hashlib
import re
import shutil
import subprocess
import sys
import tarfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INSTALL = "chordist.install"
# Must equal the `direct_asset_path` of the release link (tools/gitlab-release.py): the AUR fetches this URL.
SOURCE = '"$pkgname-$pkgver.tar.gz::$url/-/releases/v$pkgver/downloads/$pkgname-$pkgver.tar.gz"'


class Error(Exception):
    pass


def _replace_once(text: str, pattern: str, repl: str, what: str) -> str:
    """Substitute `pattern` (one whole line) and fail unless it matched exactly once."""
    out, n = re.subn(pattern, lambda _: repl, text, flags=re.MULTILINE)
    if n != 1:
        raise Error(f"expected exactly one {what} line in the PKGBUILD, found {n}")
    return out


def _aur_maintainer(line: str) -> str:
    """The AUR convention hides the address from scrapers: `a@b.c` becomes `a at b dot c`."""
    m = re.fullmatch(r"# Maintainer: (.*?) <([^<>@]+)@([^<>]+)>", line.strip())
    if not m:
        raise Error("the PKGBUILD must start with `# Maintainer: Name <user@host>`")
    name, user, host = m.groups()
    return f"# Maintainer: {name} <{user} at {host.replace('.', ' dot ')}>"


def render_pkgbuild(template: str, version: str, sha256: str, pkgrel: int = 1) -> str:
    if not re.fullmatch(r"[0-9a-f]{64}", sha256):
        raise Error(f"not a sha256: {sha256!r}")
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise Error(f"not a release version: {version!r}")
    lines = template.splitlines()
    head = next((ln for ln in lines if ln.startswith("# Maintainer:")), None)
    if head is None:
        raise Error("the PKGBUILD has no `# Maintainer:` line")
    # Everything above the first assignment is a note for people building from a checkout: drop it.
    first = next(i for i, ln in enumerate(lines) if ln and not ln.startswith("#"))
    body = "\n".join(lines[first:]) + "\n"
    body = _replace_once(body, r"^pkgver=.*$", f"pkgver={version}", "pkgver")
    body = _replace_once(body, r"^pkgrel=.*$", f"pkgrel={pkgrel}", "pkgrel")
    body = _replace_once(body, r"^source=\(.*\)$", f"source=({SOURCE})", "single-line source=(...)")
    body = _replace_once(body, r"^sha256sums=\(.*\)$", f"sha256sums=('{sha256}')", "single-line sha256sums=(...)")
    if not re.search(rf"^install={re.escape(INSTALL)}$", body, flags=re.MULTILINE):
        raise Error(f"the PKGBUILD must say install={INSTALL}")
    return f"{_aur_maintainer(head)}\n\n{body}"


def tarball_sha256(path: Path, version: str, template: str) -> tuple[str, list[str]]:
    """Checksum of the release tarball, after checking it really is this version of this tree."""
    warnings: list[str] = []
    top = f"chordist-{version}"
    with tarfile.open(path) as tar:
        names = set(tar.getnames())
        if f"{top}/VERSION" not in names:
            raise Error(f"{path.name} has no {top}/VERSION: wrong tarball for version {version}")
        inside = tar.extractfile(f"{top}/VERSION")
        if inside is None or inside.read().decode().strip() != version:
            raise Error(f"{top}/VERSION inside {path.name} is not {version}")
        packaged = tar.extractfile(f"{top}/packaging/PKGBUILD")
        if packaged is not None and packaged.read().decode() != template:
            warnings.append("packaging/PKGBUILD inside the tarball differs from the one used here")
    return hashlib.sha256(path.read_bytes()).hexdigest(), warnings


def write_srcinfo(out: Path) -> None:
    if shutil.which("makepkg") is None:
        raise Error("makepkg not found: .SRCINFO needs an Arch environment (or pass --no-srcinfo)")
    done = subprocess.run(
        ["makepkg", "--printsrcinfo"], cwd=out, capture_output=True, text=True, check=False
    )
    if done.returncode != 0:
        raise Error(f"makepkg --printsrcinfo failed:\n{done.stderr.strip()}")
    (out / ".SRCINFO").write_text(done.stdout)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--tarball", type=Path, help="the release tarball (checked, then hashed)")
    src.add_argument("--sha256", help="checksum of the release tarball")
    ap.add_argument("--version", help="release version (default: VERSION)")
    ap.add_argument("--pkgrel", type=int, default=1, help="AUR pkgrel (default 1; raise it for a packaging-only fix)")
    ap.add_argument("--pkgbuild", type=Path, default=ROOT / "packaging" / "PKGBUILD")
    ap.add_argument("--out", type=Path, required=True, help="directory to write PKGBUILD, chordist.install, .SRCINFO")
    ap.add_argument("--no-srcinfo", action="store_true", help="skip .SRCINFO (no makepkg here)")
    args = ap.parse_args(argv)

    try:
        version = args.version or (ROOT / "VERSION").read_text().strip()
        template = args.pkgbuild.read_text()
        if args.tarball:
            sha256, warnings = tarball_sha256(args.tarball, version, template)
            for warning in warnings:
                print(f"warning: {warning}", file=sys.stderr)
        else:
            sha256 = args.sha256.lower()
        pkgbuild = render_pkgbuild(template, version, sha256, args.pkgrel)
        args.out.mkdir(parents=True, exist_ok=True)
        (args.out / "PKGBUILD").write_text(pkgbuild)
        shutil.copyfile(args.pkgbuild.parent / INSTALL, args.out / INSTALL)
        if not args.no_srcinfo:
            write_srcinfo(args.out)
    except (Error, OSError, tarfile.TarError) as err:
        print(f"aur-pkgbuild: {err}", file=sys.stderr)
        return 1
    wrote = "PKGBUILD, " + INSTALL + ("" if args.no_srcinfo else ", .SRCINFO")
    print(f"{args.out}: {wrote} (chordist {version}-{args.pkgrel}, sha256 {sha256[:12]}…)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

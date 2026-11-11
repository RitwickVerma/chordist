#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
#
# SPDX-License-Identifier: MIT
"""Cut the GitLab release for a tag pipeline: notes from CHANGELOG.md, the tarball as a release asset.

    tools/gitlab-release.py notes 2.0.0                      # the changelog section, as the release notes
    tools/gitlab-release.py publish dist/chordist-2.0.0.tar.gz   # in a tag pipeline (CI_* variables)

The tarball is uploaded to the project's generic package registry (chordist/X.Y.Z/chordist-X.Y.Z.tar.gz), which
keeps it for as long as the project exists whatever happens to the pipeline, and the release links to that package
file under the stable name /-/releases/vX.Y.Z/downloads/chordist-X.Y.Z.tar.gz that the AUR package downloads from.
It authenticates as the job (CI_JOB_TOKEN), or with RELEASE_TOKEN (a project access token with the api scope) if
that CI variable is set. `publish` fetches the stable name afterwards and compares checksums, so a broken link fails
the job rather than a user's `makepkg`. Needs the project's package registry enabled (docs/releasing.md).
Standard library only.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
JSON = {"Content-Type": "application/json"}


class Error(Exception):
    pass


def changelog_section(text: str, version: str) -> str:
    """The body of `## [version] — date`, up to the next `## ` heading."""
    m = re.search(rf"^## \[{re.escape(version)}\][^\n]*\n(.*?)(?=^## |\Z)", text, flags=re.MULTILINE | re.DOTALL)
    notes = m.group(1).strip() if m else ""
    if not notes:
        raise Error(f"CHANGELOG.md has no filled-in `## [{version}]` section")
    return notes


def asset_name(version: str) -> str:
    return f"chordist-{version}.tar.gz"


def package_url(api: str, project: str, version: str) -> str:
    """Where the tarball lives in the generic package registry (also the URL it is uploaded to)."""
    return f"{api}/projects/{project}/packages/generic/chordist/{version}/{asset_name(version)}"


def release_payload(version: str, notes: str, asset_url: str) -> dict:
    return {
        "name": f"Chordist {version}",
        "tag_name": f"v{version}",
        "description": notes,
        "assets": {
            "links": [
                {
                    "name": asset_name(version),
                    "url": asset_url,
                    # The stable name: /-/releases/v<version>/downloads/chordist-<version>.tar.gz
                    "direct_asset_path": f"/{asset_name(version)}",
                    "link_type": "package",
                }
            ]
        },
    }


def _open(req: urllib.request.Request):
    # An opener, not urlopen: the test suite refuses urlopen outright.
    return urllib.request.build_opener().open(req, timeout=60)


def _auth(token: str, private: bool) -> dict[str, str]:
    return {"PRIVATE-TOKEN" if private else "JOB-TOKEN": token}


def upload_package(url: str, tarball: Path, token: str, private: bool = False) -> None:
    """PUT the tarball into the generic package registry (a retried job simply uploads it again)."""
    req = urllib.request.Request(
        url,
        data=tarball.read_bytes(),
        headers={"Content-Type": "application/octet-stream", **_auth(token, private)},
        method="PUT",
    )
    try:
        _open(req).close()
    except urllib.error.HTTPError as err:
        detail = err.read().decode(errors="replace")[:300]
        hint = " (is the project's package registry enabled? see docs/releasing.md)" if err.code in (401, 403, 404) else ""
        raise Error(f"uploading {tarball.name} to the package registry failed: HTTP {err.code} {detail}{hint}") from err


def create_release(api: str, project: str, token: str, payload: dict, private: bool = False) -> None:
    auth = _auth(token, private)
    req = urllib.request.Request(
        f"{api}/projects/{project}/releases",
        data=json.dumps(payload).encode(),
        headers={**JSON, **auth},
        method="POST",
    )
    try:
        _open(req).close()
    except urllib.error.HTTPError as err:
        detail = err.read().decode(errors="replace")[:300]
        hint = " (the release already exists: delete it in the UI, then retry the job)" if err.code == 409 else ""
        raise Error(f"creating the release failed: HTTP {err.code} {detail}{hint}") from err


def verify_download(project_url: str, version: str, sha256: str) -> None:
    """Fetch the public stable URL, as the AUR does, and compare what comes back."""
    url = f"{project_url}/-/releases/v{version}/downloads/{asset_name(version)}"
    try:
        with _open(urllib.request.Request(url)) as resp:
            got = hashlib.sha256(resp.read()).hexdigest()
    except urllib.error.URLError as err:
        raise Error(f"{url} does not download: {err}") from err
    if got != sha256:
        raise Error(f"{url} serves sha256 {got}, expected {sha256}")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    notes = sub.add_parser("notes", help="print the changelog section for a version")
    notes.add_argument("version")
    notes.add_argument("--changelog", type=Path, default=ROOT / "CHANGELOG.md")
    pub = sub.add_parser("publish", help="create the release for CI_COMMIT_TAG")
    pub.add_argument("tarball", type=Path)
    pub.add_argument("--changelog", type=Path, default=ROOT / "CHANGELOG.md")
    pub.add_argument("--dry-run", action="store_true", help="print the request instead of sending it")
    pub.add_argument("--no-verify", action="store_true", help="do not fetch the stable download URL afterwards")
    args = ap.parse_args(argv)

    try:
        if args.cmd == "notes":
            print(changelog_section(args.changelog.read_text(), args.version))
            return 0

        env = os.environ
        version = (ROOT / "VERSION").read_text().strip()
        tag = env.get("CI_COMMIT_TAG", "")
        if tag != f"v{version}":
            raise Error(f"tag {tag!r} does not match VERSION {version!r}: expected v{version}")
        if args.tarball.name != asset_name(version):
            raise Error(f"{args.tarball.name} is not {asset_name(version)}")
        sha256 = hashlib.sha256(args.tarball.read_bytes()).hexdigest()
        project_url = env["CI_PROJECT_URL"].rstrip("/")
        api, project = env["CI_API_V4_URL"], env["CI_PROJECT_ID"]
        asset_url = package_url(api, project, version)
        payload = release_payload(version, changelog_section(args.changelog.read_text(), version), asset_url)
        if args.dry_run:
            print(f"PUT {asset_url}")
            print(json.dumps(payload, indent=2))
            return 0
        # CI_JOB_TOKEN by default; a project access token (api scope) in RELEASE_TOKEN overrides it.
        private = env.get("RELEASE_TOKEN", "")
        token = private or env["CI_JOB_TOKEN"]
        upload_package(asset_url, args.tarball, token, bool(private))
        print(f"uploaded {asset_url}")
        create_release(api, project, token, payload, bool(private))
        print(f"release v{version} created; tarball sha256 {sha256}")
        if not args.no_verify:
            verify_download(project_url, version, sha256)
            print(f"{project_url}/-/releases/v{version}/downloads/{asset_name(version)} downloads, checksum matches")
    except KeyError as err:
        print(f"gitlab-release: {err.args[0]} is not set (run this in a tag pipeline)", file=sys.stderr)
        return 1
    except (Error, OSError) as err:
        print(f"gitlab-release: {err}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

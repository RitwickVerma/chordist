# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
#
# SPDX-License-Identifier: MIT

"""The release tooling: the AUR file generator and the GitLab release script."""

from __future__ import annotations

import hashlib
import importlib.util
import io
import json
import re
import tarfile
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from typing import ClassVar

import pytest

ROOT = Path(__file__).resolve().parents[2]
SHA = "ab" * 32


def load(name: str):
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"), ROOT / "tools" / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


aur = load("aur-pkgbuild")
release = load("gitlab-release")
PKGBUILD = (ROOT / "packaging" / "PKGBUILD").read_text()


def tarball(path: Path, version: str = "2.0.0", pkgbuild: str = PKGBUILD) -> Path:
    with tarfile.open(path, "w:gz") as tar:
        for name, body in ((f"chordist-{version}/VERSION", f"{version}\n"), (f"chordist-{version}/packaging/PKGBUILD", pkgbuild)):
            data = body.encode()
            info = tarfile.TarInfo(name)
            info.size = len(data)
            tar.addfile(info, io.BytesIO(data))
    return path


# ---- the AUR PKGBUILD --------------------------------------------------------


def test_the_packaging_directory_owns_the_install_file():
    assert re.search(r"^install=chordist\.install$", PKGBUILD, re.MULTILINE)
    assert (ROOT / "packaging" / "chordist.install").is_file()


def test_only_source_checksum_and_header_differ_from_the_source_pkgbuild():
    out = aur.render_pkgbuild(PKGBUILD, "2.0.0", SHA)
    mine = PKGBUILD.splitlines()
    theirs = out.splitlines()
    changed = [line for line in theirs if line not in mine]
    assert changed == [
        "# Maintainer: Ritwick Verma <verma1997 at gmail dot com>",
        'source=("$pkgname-$pkgver.tar.gz::$url/-/releases/v$pkgver/downloads/$pkgname-$pkgver.tar.gz")',
        f"sha256sums=('{SHA}')",
    ]
    # package() and depends survive byte for byte
    assert PKGBUILD[PKGBUILD.index("\npackage() {") :] == out[out.index("\npackage() {") :]
    assert next(x for x in mine if x.startswith("depends=")) in theirs
    assert not any(x.startswith("# Build from") for x in theirs)


def test_pkgrel_and_version_are_set():
    out = aur.render_pkgbuild(PKGBUILD, "2.1.0", SHA, pkgrel=3)
    assert "\npkgver=2.1.0\n" in out
    assert "\npkgrel=3\n" in out


@pytest.mark.parametrize(
    ("mutate", "message"),
    [
        (lambda p: p.replace("install=chordist.install\n", ""), "install=chordist.install"),
        (lambda p: p.replace("source=(", "source=(\n  "), "source"),
        (lambda p: p.replace("sha256sums=('SKIP')", "sha256sums=(\n  'SKIP')"), "sha256sums"),
        (lambda p: p.replace("# Maintainer", "# Packager"), "Maintainer"),
    ],
)
def test_a_pkgbuild_the_generator_cannot_rewrite_is_an_error(mutate, message):
    with pytest.raises(aur.Error, match=message):
        aur.render_pkgbuild(mutate(PKGBUILD), "2.0.0", SHA)


def test_bad_checksum_and_version_are_refused():
    with pytest.raises(aur.Error, match="sha256"):
        aur.render_pkgbuild(PKGBUILD, "2.0.0", "SKIP")
    with pytest.raises(aur.Error, match="version"):
        aur.render_pkgbuild(PKGBUILD, "2.0", SHA)


def test_the_tarball_is_checked_then_hashed(tmp_path):
    path = tarball(tmp_path / "chordist-2.0.0.tar.gz")
    digest, warnings = aur.tarball_sha256(path, "2.0.0", PKGBUILD)
    assert digest == hashlib.sha256(path.read_bytes()).hexdigest()
    assert warnings == []
    assert aur.tarball_sha256(path, "2.0.0", PKGBUILD + "# edited\n")[1]  # stale PKGBUILD: a warning
    with pytest.raises(aur.Error, match="wrong tarball"):
        aur.tarball_sha256(path, "9.9.9", PKGBUILD)


def test_cli_writes_the_files(tmp_path, capsys):
    path = tarball(tmp_path / "chordist-2.0.0.tar.gz")
    out = tmp_path / "aur"
    assert aur.main(["--tarball", str(path), "--version", "2.0.0", "--out", str(out), "--no-srcinfo"]) == 0
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    assert f"sha256sums=('{digest}')" in (out / "PKGBUILD").read_text()
    assert (out / "chordist.install").read_text() == (ROOT / "packaging" / "chordist.install").read_text()
    assert not (out / ".SRCINFO").exists()
    assert aur.main(["--sha256", "nope", "--version", "2.0.0", "--out", str(out), "--no-srcinfo"]) == 1
    assert "not a sha256" in capsys.readouterr().err


# ---- the GitLab release ------------------------------------------------------

CHANGELOG = """# Changelog

## [Unreleased]

Nothing yet.

## [9.8.7] — 2026-11-10

Intro line.

### Added
- A thing.

## [1.0.0]

Old.
"""


def test_the_release_notes_are_that_versions_section_only():
    notes = release.changelog_section(CHANGELOG, "9.8.7")
    assert notes.startswith("Intro line.")
    assert notes.endswith("- A thing.")
    assert "Old." not in notes
    assert release.changelog_section(CHANGELOG, "1.0.0") == "Old."


def test_a_missing_or_empty_section_is_an_error():
    with pytest.raises(release.Error):
        release.changelog_section(CHANGELOG, "3.0.0")
    with pytest.raises(release.Error):
        release.changelog_section("## [3.0.0]\n\n## [2.0.0]\nx\n", "3.0.0")


def test_the_real_changelog_has_a_section_for_every_released_version():
    version = (ROOT / "VERSION").read_text().strip()
    text = (ROOT / "CHANGELOG.md").read_text()
    assert release.changelog_section(text, "2.0.0")
    assert re.search(rf"^## \[({re.escape(version)}|Unreleased)\]", text, re.MULTILINE)


def test_the_stable_download_path_is_what_the_aur_source_uses():
    link = release.release_payload("2.0.0", "n", "https://x/y")["assets"]["links"][0]
    assert link["direct_asset_path"] == "/chordist-2.0.0.tar.gz"
    assert link["link_type"] == "package"
    # .../-/releases/v$pkgver/downloads/$pkgname-$pkgver.tar.gz  <- aur.SOURCE
    assert aur.SOURCE.endswith("/downloads/$pkgname-$pkgver.tar.gz\"")
    assert "/-/releases/v$pkgver/" in aur.SOURCE


PACKAGE_PATH = "/api/v4/projects/42/packages/generic/chordist/9.8.7/chordist-9.8.7.tar.gz"


class FakeGitLab(BaseHTTPRequestHandler):
    """Just enough of GitLab: the generic package registry, release creation, and the stable name redirecting to
    the package file. `seen` records every write as (method, path, token, body)."""

    seen: ClassVar[list] = []
    stored: ClassVar[bytes | None] = None      # what the registry holds, as uploaded
    serve_instead: ClassVar[bytes | None] = None
    conflict: ClassVar[bool] = False
    upload_status: ClassVar[int] = 201

    def log_message(self, *args):  # silence the default stderr logging
        pass

    def _token(self):
        return self.headers["JOB-TOKEN"] or self.headers["PRIVATE-TOKEN"]

    def do_PUT(self):
        data = self.rfile.read(int(self.headers["Content-Length"]))
        FakeGitLab.seen.append(("PUT", self.path, self._token(), data))
        if FakeGitLab.upload_status == 201 and self.path == PACKAGE_PATH:
            FakeGitLab.stored = data
        self.send_response(FakeGitLab.upload_status)
        self.end_headers()
        self.wfile.write(b'{"message":"403 Forbidden"}')

    def do_POST(self):
        payload = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        FakeGitLab.seen.append(("POST", self.path, self._token(), payload))
        self.send_response(409 if FakeGitLab.conflict else 201)
        self.end_headers()
        self.wfile.write(b'{"message":"Release already exists"}')

    def do_GET(self):
        if self.path == "/g/p/-/releases/v9.8.7/downloads/chordist-9.8.7.tar.gz":
            self.send_response(302)
            self.send_header("Location", PACKAGE_PATH)
            self.end_headers()
        elif self.path == PACKAGE_PATH:
            self.send_response(200)
            self.end_headers()
            self.wfile.write(FakeGitLab.serve_instead or FakeGitLab.stored or b"")
        else:
            self.send_response(404)
            self.end_headers()


@pytest.fixture
def gitlab(tmp_path, monkeypatch):
    FakeGitLab.seen, FakeGitLab.stored, FakeGitLab.serve_instead = [], None, None
    FakeGitLab.conflict, FakeGitLab.upload_status = False, 201
    server = HTTPServer(("127.0.0.1", 0), FakeGitLab)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{server.server_port}"
    version = "9.8.7"
    monkeypatch.setattr(release, "ROOT", tmp_path)
    (tmp_path / "VERSION").write_text(f"{version}\n")
    monkeypatch.setenv("CI_COMMIT_TAG", f"v{version}")
    monkeypatch.setenv("CI_API_V4_URL", f"{base}/api/v4")
    monkeypatch.setenv("CI_PROJECT_ID", "42")
    monkeypatch.setenv("CI_PROJECT_URL", f"{base}/g/p")
    monkeypatch.setenv("CI_JOB_TOKEN", "secret-job-token")
    monkeypatch.chdir(tmp_path)
    (tmp_path / "dist").mkdir()
    (tmp_path / "dist" / f"chordist-{version}.tar.gz").write_bytes(b"the tarball")
    (tmp_path / "CHANGELOG.md").write_text(CHANGELOG)
    yield tmp_path
    server.shutdown()
    server.server_close()


@pytest.mark.loopback
@pytest.mark.usefixtures("gitlab")
def test_publish_uploads_the_tarball_then_creates_the_release_and_checks_the_stable_url(capsys):
    assert release.main(["publish", "dist/chordist-9.8.7.tar.gz", "--changelog", "CHANGELOG.md"]) == 0
    put, post = FakeGitLab.seen
    # the tarball goes into the generic package registry with the job's token, before the release names it
    assert put[:3] == ("PUT", PACKAGE_PATH, "secret-job-token")
    assert put[3] == b"the tarball"
    method, path, token, payload = post
    assert (method, path, token) == ("POST", "/api/v4/projects/42/releases", "secret-job-token")
    assert payload["tag_name"] == "v9.8.7"
    assert payload["description"].startswith("Intro line.")
    link = payload["assets"]["links"][0]
    assert link["url"].endswith(PACKAGE_PATH)
    assert link["direct_asset_path"] == "/chordist-9.8.7.tar.gz"
    assert "checksum matches" in capsys.readouterr().out


@pytest.mark.loopback
@pytest.mark.usefixtures("gitlab")
def test_publish_fails_when_the_stable_url_serves_something_else(capsys):
    FakeGitLab.serve_instead = b"another file"
    assert release.main(["publish", "dist/chordist-9.8.7.tar.gz", "--changelog", "CHANGELOG.md"]) == 1
    assert "serves sha256" in capsys.readouterr().err


@pytest.mark.loopback
@pytest.mark.usefixtures("gitlab")
def test_publish_says_what_to_do_when_the_release_exists(capsys):
    FakeGitLab.conflict = True
    assert release.main(["publish", "dist/chordist-9.8.7.tar.gz", "--changelog", "CHANGELOG.md"]) == 1
    assert "already exists" in capsys.readouterr().err


@pytest.mark.loopback
@pytest.mark.usefixtures("gitlab")
def test_a_failed_upload_stops_before_any_release_exists_and_names_the_registry(capsys):
    FakeGitLab.upload_status = 403
    assert release.main(["publish", "dist/chordist-9.8.7.tar.gz", "--changelog", "CHANGELOG.md"]) == 1
    assert "package registry" in capsys.readouterr().err
    assert [call[0] for call in FakeGitLab.seen] == ["PUT"]


@pytest.mark.loopback
@pytest.mark.usefixtures("gitlab")
def test_a_release_token_variable_replaces_the_job_token_for_both_requests(monkeypatch):
    monkeypatch.setenv("RELEASE_TOKEN", "project-token")
    assert release.main(["publish", "dist/chordist-9.8.7.tar.gz", "--changelog", "CHANGELOG.md"]) == 0
    assert [call[2] for call in FakeGitLab.seen] == ["project-token", "project-token"]


@pytest.mark.usefixtures("gitlab")
def test_publish_refuses_a_tag_that_is_not_the_version(monkeypatch, capsys):
    monkeypatch.setenv("CI_COMMIT_TAG", "v1.2.3")
    assert release.main(["publish", "dist/chordist-9.8.7.tar.gz", "--dry-run"]) == 1
    assert "does not match VERSION" in capsys.readouterr().err
    assert FakeGitLab.seen == []


@pytest.mark.usefixtures("gitlab")
def test_publish_dry_run_sends_nothing(capsys):
    assert release.main(["publish", "dist/chordist-9.8.7.tar.gz", "--dry-run", "--changelog", "CHANGELOG.md"]) == 0
    out = capsys.readouterr().out
    first = out.splitlines()[0]
    assert first.startswith("PUT http://127.0.0.1:") and first.endswith(PACKAGE_PATH)
    assert json.loads(out.split("\n", 1)[1])["tag_name"] == "v9.8.7"
    assert FakeGitLab.seen == []

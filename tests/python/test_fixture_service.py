# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
#
# SPDX-License-Identifier: MIT

"""The screenshot harness's fixture service must keep answering as the real one does.

It replaces the lookups that would use the network with canned data, so it can drift
when a real signature changes: the renders would then show an error state and still
look like screenshots. This starts it for real and asks for a song.
"""

from __future__ import annotations

import json
import socket
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

import pytest

pytestmark = pytest.mark.loopback

FIXTURE = Path(__file__).resolve().parents[1] / "qml" / "fixture_service.py"


def free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


@pytest.fixture
def fixture_service(tmp_path):
    port = free_port()
    proc = subprocess.Popen([sys.executable, "-I", str(FIXTURE), str(port), str(tmp_path / "state")],
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    try:
        assert proc.stdout is not None
        assert proc.stdout.readline().startswith("ready")
        yield port
    finally:
        proc.terminate()
        proc.wait(5)


def get(port, path):
    deadline = time.monotonic() + 10
    while True:
        try:
            with urllib.request.build_opener().open(f"http://127.0.0.1:{port}{path}", timeout=10) as response:
                return json.loads(response.read())
        except OSError:
            if time.monotonic() > deadline:
                raise
            time.sleep(0.1)


def test_the_fixture_song_loads_with_synced_lyrics_and_an_aligned_chart(fixture_service):
    song = get(fixture_service, "/api/song?artist=Traditional&title=Amazing%20Grace&album=Hymns&duration=34")
    assert "error" not in song
    assert song["lyrics"]["synced"] is True and len(song["lyrics"]["lines"]) == 4
    assert song["chords"]["chord_names"] == ["C", "D", "Em", "G", "G7"]
    assert len(song["chords"]["row_times"]) == 4        # the chart was aligned to the lyric timings
    assert song["shapes"]["G"]["frets"] == [3, 2, 0, 0, 0, 3]


def test_the_fixture_tab_loads_as_staves(fixture_service):
    song = get(fixture_service, "/api/song?artist=Traditional&title=Open%20String%20Study&duration=34")
    assert song["chords"]["kind"] == "tab"
    assert any("staff" in line for section in song["chords"]["sections"] for line in section["lines"])


def test_the_version_chooser_lists_the_fixture_candidates(fixture_service):
    versions = get(fixture_service, "/api/versions?artist=Traditional&title=Amazing%20Grace&duration=34")
    assert [c["type"] for c in versions["charts"]] == ["Chords", "Tabs"]
    assert len(versions["lyrics"]) == 2

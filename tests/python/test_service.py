# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
#
# SPDX-License-Identifier: MIT

"""Service-level behaviour that spans identity, lyrics and charts."""

from __future__ import annotations

import pytest

from chordist import server
from chordist.config import Config

CANONICAL = {"artist": "Real Artist", "title": "Real Title", "album": "Real Album", "source": "lrclib"}


@pytest.fixture
def svc(monkeypatch):
    config = Config({"chords_sources": ["local"], "ug_enabled": False, "fingerprint_enabled": False,
                     "min_request_interval": 0})
    service = server.Service(config)
    monkeypatch.setattr(server.identity, "resolve", lambda *a, **k: dict(CANONICAL))
    monkeypatch.setattr(service.lyrics, "lookup", lambda *a, **k: {"source": "none", "lines": []})
    return service


def test_a_pasted_chart_is_found_again_when_the_metadata_is_junk(svc):
    junk = ("Some Channel", "Real Title (Official Video) | Film | Singers")
    svc.paste(*junk, "{title: x}\n[Am]hello [F]world")
    # the next lookup runs on the resolved identity, exactly as the widget triggers it
    got = svc.song(*junk)
    assert got["chords"]["source"] == "local" and got["chords"]["chord_names"] == ["Am", "F"]


def test_a_chart_deleted_under_junk_metadata_is_really_gone(svc):
    junk = ("Some Channel", "Real Title (Official Video)")
    svc.paste(*junk, "[Am]hello world")
    assert svc.delete_local(*junk) is True
    assert svc.song(*junk)["chords"]["source"] == "none"


def test_the_version_chooser_searches_the_real_song_and_album(svc, monkeypatch):
    seen = {}
    monkeypatch.setattr(svc.lyrics, "candidates", lambda artist, title, album="", duration=0.0, **k: seen.setdefault("lyrics", (artist, title, album)) and [])
    monkeypatch.setattr(svc.chords, "candidates", lambda artist, title, limit=24, album="": seen.setdefault("charts", (artist, title, album)) and [])
    svc.versions("Some Channel", "Junk Title", "", 200.0)
    assert seen["lyrics"] == ("Real Artist", "Real Title", "Real Album")
    assert seen["charts"] == ("Real Artist", "Real Title", "Real Album")

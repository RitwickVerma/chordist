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


# ---- what the widget relies on the service for, since the sync review


def test_a_title_with_no_song_in_it_is_not_looked_up_at_all(svc, monkeypatch):
    """A browser tab called "YouTube" is the site's front page; a same-length junk upload must not become its song."""
    asked = []
    monkeypatch.setattr(server.identity, "resolve", lambda *a, **k: asked.append(a) or None)
    monkeypatch.setattr(svc.lyrics, "lookup", lambda *a, **k: asked.append(a) or {"source": "none", "lines": []})
    for artist, title in (("", "YouTube"), ("", "(80) YouTube"), ("Topic", "Official Audio")):
        got = svc.song(artist, title, duration=200)
        assert got["chords"]["source"] == "none" and got["lyrics"]["source"] == "none"
        assert got["error"] == "no song in the title"
    assert asked == []
    # but a real artist carries the song even when the title is noise
    svc.song("India.Arie", "Video", duration=200)
    assert asked, "a meaningful artist is worth a lookup"


def test_remembered_pins_apply_when_the_caller_sends_none(svc, monkeypatch):
    seen = []

    def chords(artist, title, duration=0.0, chord_url=None, album="", refresh=False):
        seen.append(chord_url)
        return {"source": "none", "sections": [], "chord_names": []}

    monkeypatch.setattr(svc.chords, "lookup", chords)
    url = "https://tabs.ultimate-guitar.com/tab/a/b-chords-1"
    svc.set_prefs("Artist", "Song", {"chord_url": url})
    svc.song("Artist", "Song")                        # the widget's first request for the track: no pins said
    svc.song("Artist", "Song", chord_url="")          # an explicit "none": the widget just un-pinned
    svc.song("Artist", "Song", chord_url="https://tabs.ultimate-guitar.com/tab/c/d-chords-2")
    assert seen == [url, None, "https://tabs.ultimate-guitar.com/tab/c/d-chords-2"]


def test_a_paused_player_is_never_recorded(svc, monkeypatch):
    seen = {}

    def resolve(config, lyrics, artist, title, duration=0.0, album="", allow_fingerprint=True):
        seen["fingerprint"] = allow_fingerprint
        return None

    monkeypatch.setattr(server.identity, "resolve", resolve)
    svc.song("Artist", "Song", playing=False)
    assert seen["fingerprint"] is False
    svc.song("Artist", "Song")
    assert seen["fingerprint"] is True

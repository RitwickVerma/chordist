# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
#
# SPDX-License-Identifier: MIT

from __future__ import annotations

import urllib.error

import pytest

from chordist import lyrics
from chordist.config import Config
from chordist.http import HttpError, Throttle

ENTRY = {"id": 7, "trackName": "Creep", "artistName": "Radiohead", "albumName": "Pablo Honey", "duration": 238,
         "syncedLyrics": "[00:10.00]When you were here before", "plainLyrics": "When you were here before"}


def provider(**overrides):
    return lyrics.LyricsProvider(Config({"min_request_interval": 0, **overrides}), Throttle(0))


@pytest.fixture
def lrclib(monkeypatch):
    """Scripted LRCLIB: set ``lrclib.handler`` to a function(url) -> data or raise."""
    calls: list[str] = []

    def fetch_json(url, **kwargs):
        calls.append(url)
        return lrclib.handler(url)

    monkeypatch.setattr(lyrics, "fetch_json", fetch_json)
    lrclib.calls = calls
    lrclib.handler = lambda url: (_ for _ in ()).throw(AssertionError(url))
    return lrclib


def not_found(url):
    if "/get?" in url:
        raise HttpError(404, url)
    return []


def test_a_hit_is_found_and_cached(lrclib):
    lrclib.handler = lambda url: ENTRY
    p = provider()
    assert p.lookup("Radiohead", "Creep", duration=238)["synced"] is True
    n = len(lrclib.calls)
    assert p.lookup("Radiohead", "Creep", duration=238)["cached"] is True
    assert len(lrclib.calls) == n


def test_a_song_lrclib_does_not_have_is_not_searched_again_straight_away(lrclib):
    lrclib.handler = not_found
    p = provider()
    assert p.lookup("Nobody", "Nothing")["source"] == "none"
    n = len(lrclib.calls)
    assert n > 0
    again = p.lookup("Nobody", "Nothing")
    assert again["source"] == "none" and again["cached"] is True
    assert len(lrclib.calls) == n, "a remembered miss went back to the network"


def test_being_offline_is_not_remembered_as_no_lyrics(lrclib):
    def down(url):
        raise urllib.error.URLError("network unreachable")

    lrclib.handler = down
    p = provider()
    first = p.lookup("Radiohead", "Creep")
    assert first["source"] == "none" and first["error"] == "offline"
    n = len(lrclib.calls)
    lrclib.handler = lambda url: ENTRY          # the network is back
    assert p.lookup("Radiohead", "Creep")["source"] == "lrclib"
    assert len(lrclib.calls) > n


def test_a_server_error_is_not_remembered_as_no_lyrics_either(lrclib):
    def broken(url):
        raise HttpError(503, url)

    lrclib.handler = broken
    p = provider()
    assert p.lookup("Radiohead", "Creep")["error"] == "offline"
    lrclib.handler = lambda url: ENTRY
    assert p.lookup("Radiohead", "Creep")["source"] == "lrclib"


def test_asking_again_looks_past_a_remembered_miss(lrclib):
    lrclib.handler = not_found
    p = provider()
    p.lookup("Nobody", "Nothing")
    lrclib.handler = lambda url: {**ENTRY, "trackName": "Nothing", "artistName": "Nobody"}
    assert p.lookup("Nobody", "Nothing")["source"] == "none"                     # still remembered
    assert p.lookup("Nobody", "Nothing", refresh=True)["source"] == "lrclib"     # but not when asked again


def test_a_remembered_miss_expires(lrclib):
    lrclib.handler = not_found
    p = provider(lyrics_negative_ttl_seconds=1)
    p.lookup("Nobody", "Nothing")
    import time

    time.sleep(1.1)
    n = len(lrclib.calls)
    p.lookup("Nobody", "Nothing")
    assert len(lrclib.calls) > n

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


# ---- title cleaning, scoring and search ----

@pytest.mark.parametrize(
    ("raw", "cleaned"),
    [
        ("Creep (Official Video)", "Creep"),
        ("Creep (Official Music Video)", "Creep"),
        ("Creep [Lyrics]", "Creep"),
        ("Creep - Topic", "Creep"),
        ("Creep - YouTube", "Creep"),
        ("Creep lyrics", "Creep"),
        ("Song ft. Someone", "Song"),
        ("Song (feat. X) (Remastered 2011)", "Song (feat. X)"),
        ("Yesterday (Remastered 2009)", "Yesterday"),
        ("Song (Live at Wembley)", "Song"),
        ("Pure (Instrumental)", "Pure"),
        ("(3) Believer (Official Audio)", "Believer"),
        ("Hello (Adele)", "Hello (Adele)"),          # a bracket that is not decoration stays
        ("Ek Villain (2014)", "Ek Villain (2014)"),
        ("", ""),
    ],
)
def test_streaming_decoration_is_stripped_from_titles(raw, cleaned):
    assert lyrics.clean(raw) == cleaned


def test_cleaning_twice_changes_nothing():
    for raw in ("Creep (Official Video)", "(3) Song - Topic", "Song ft. X [HD]"):
        assert lyrics.clean(lyrics.clean(raw)) == lyrics.clean(raw)


def test_a_video_title_is_cut_into_its_segments():
    assert lyrics._title_variants("Judaai | Badlapur | Arijit Singh") == [
        "Judaai | Badlapur | Arijit Singh", "Judaai", "Arijit Singh"]
    assert lyrics._title_variants("Plain") == ["Plain"]


def test_a_fallback_hit_must_name_a_song_in_the_title():
    assert lyrics._plausible({"trackName": "Judaai"}, "Judaai | Badlapur")
    assert not lyrics._plausible({"trackName": "Something Else"}, "Judaai | Badlapur")
    assert not lyrics._plausible({}, "Judaai")


def test_the_better_match_scores_higher():
    exact = {"trackName": "Creep", "artistName": "Radiohead", "duration": 238, "syncedLyrics": "x"}
    wrong_length = {**exact, "duration": 400}
    plain = {**exact, "syncedLyrics": ""}
    wrong_song = {**exact, "trackName": "Karma Police"}
    score = lambda e: lyrics._score(e, "Radiohead", "Creep", 238)   # noqa: E731
    assert score(exact) > score(wrong_length)
    assert score(exact) > score(plain)
    assert score(exact) > score(wrong_song)


def test_a_search_picks_the_best_scoring_candidate(lrclib):
    rows = [
        {"id": 1, "trackName": "Creep", "artistName": "Cover Band", "duration": 240, "syncedLyrics": "[00:01.00]x"},
        {"id": 2, "trackName": "Creep", "artistName": "Radiohead", "duration": 238, "syncedLyrics": "[00:01.00]x"},
    ]
    lrclib.handler = lambda url: (_ for _ in ()).throw(HttpError(404, url)) if "/get?" in url else rows
    assert provider().lookup("Radiohead", "Creep", duration=238)["id"] == 2


def test_a_title_made_of_segments_is_found_by_its_song_part(lrclib):
    row = {"id": 9, "trackName": "Judaai", "artistName": "Arijit Singh", "duration": 250, "syncedLyrics": "[00:01.00]x"}

    def handler(url):
        if "/get?" in url:
            raise HttpError(404, url)
        return [row] if "q=Judaai" in url and "Badlapur" not in url else []

    lrclib.handler = handler
    got = provider().lookup("Some Channel", "Judaai | Badlapur | Arijit Singh", duration=250)
    assert got["id"] == 9


def test_plain_lyrics_become_untimed_lines(lrclib):
    lrclib.handler = lambda url: {**ENTRY, "syncedLyrics": "", "plainLyrics": "one\ntwo"}
    got = provider().lookup("Radiohead", "Creep")
    assert got["synced"] is False and [line["text"] for line in got["lines"]] == ["one", "two"]
    assert all(line["t"] is None for line in got["lines"])


def test_a_hand_picked_entry_is_fetched_by_id_and_marked(lrclib):
    lrclib.handler = lambda url: ENTRY if "/get/42" in url else None
    got = provider().lookup("x", "y", lyrics_id=42)
    assert got["pinned"] is True and got["id"] == 7
    assert provider().lookup("x", "y", lyrics_id=42)["cached"] is True


def test_a_hand_picked_entry_that_will_not_load_falls_back_and_says_so(lrclib):
    def handler(url):
        if "/get/99" in url:
            raise HttpError(404, url)
        return ENTRY

    lrclib.handler = handler
    got = provider().lookup("Radiohead", "Creep", lyrics_id=99)
    assert got["pin_failed"] is True and got["source"] == "lrclib"


def test_the_version_chooser_lists_candidates_best_first(lrclib):
    rows = [
        {"id": 1, "trackName": "Creep (Live)", "artistName": "Radiohead", "duration": 300, "syncedLyrics": ""},
        {"id": 2, "trackName": "Creep", "artistName": "Radiohead", "duration": 238, "syncedLyrics": "x",
         "albumName": "Pablo Honey"},
    ]
    lrclib.handler = lambda url: rows
    out = provider().candidates("Radiohead", "Creep", duration=238)
    assert [c["id"] for c in out] == [2, 1]
    assert out[0]["synced"] is True and out[0]["album"] == "Pablo Honey" and out[0]["score"] > out[1]["score"]
    assert provider().candidates("x", "") == []


def test_the_version_chooser_survives_a_dead_network(lrclib):
    def down(url):
        raise urllib.error.URLError("no route")

    lrclib.handler = down
    assert provider().candidates("Radiohead", "Creep") == []


def test_requests_identify_the_client_and_its_contact(monkeypatch):
    seen = {}

    def fetch_json(url, **kwargs):
        seen.update(kwargs.get("headers") or {})
        return ENTRY

    monkeypatch.setattr(lyrics, "fetch_json", fetch_json)
    provider(contact="me@example.org").lookup("Radiohead", "Creep")
    assert seen["User-Agent"].startswith("chordist/") and "me@example.org" in seen["User-Agent"]

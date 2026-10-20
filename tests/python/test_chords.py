# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
#
# SPDX-License-Identifier: MIT

from __future__ import annotations

import pytest
from conftest import ug_page, ug_search_page

from chordist import chords
from chordist.config import Config
from chordist.http import Throttle

TAB_URL = "https://tabs.ultimate-guitar.com/tab/x/y-chords-1"
TABS_URL = "https://tabs.ultimate-guitar.com/tab/x/y-tabs-2"

CHORDS_BODY = "[Verse]\n[tab][ch]Em[/ch]   [ch]G[/ch]\nToday is gonna be the day[/tab]"
TAB_BODY = "[Intro]\n[tab]e|--0--2--|\nB|--0--3--|\nG|--0--2--|\nD|--2--0--|\nA|--2--x--|\nE|--0--x--|[/tab]"

TAB_VIEW = {
    "wiki_tab": {"content": CHORDS_BODY, "username": "someone"},
    "meta": {"capo": 2, "tonality": "F#m", "difficulty": "novice", "tuning": {"name": "Standard", "value": "E A D G B E"}},
    "stats": {"view_total": 1234, "favorites_count": 56},
    "applicature": {
        "Em": [{"frets": [0, 0, 0, 2, 2, 0], "fingers": [0, 0, 0, 2, 1, 0]}],
        "G": "garbage",
    },
    "encode_strummings": '{"patterns":[{"part":"Whole Song","denuminator":16,"bpm":87,"is_triplet":0,"measures":[1,202,3]}]}',
    "is_simplify_available": True,
}


def provider(**overrides):
    values = {"chords_sources": ["local", "cache", "ultimate-guitar"], "ug_enabled": True, "min_request_interval": 0}
    values.update(overrides)
    return chords.ChordProvider(Config(values), Throttle(0))


def result(url, kind, name="Y", artist="X"):
    return {"tab_url": url, "song_name": name, "artist_name": artist, "type": kind,
            "votes": 10, "rating": 4.5, "tab_access_type": "public"}


@pytest.fixture
def fake_ug(monkeypatch):
    """Serves a search page and tab pages from a dict; records what was fetched."""
    pages: dict[str, str] = {}
    fetched: list[str] = []

    def fetch(url, **kwargs):
        fetched.append(url)
        if "search.php" in url:
            return pages["search"]
        return pages[url]

    monkeypatch.setattr(chords, "fetch", fetch)
    fake_ug.pages, fake_ug.fetched = pages, fetched
    return fake_ug


@pytest.mark.parametrize("url", [
    "https://tabs.ultimate-guitar.com/tab/a/b-chords-1",
    "https://www.ultimate-guitar.com/tab/a",
    "https://ultimate-guitar.com/x",
])
def test_ug_urls_are_accepted(url):
    assert chords.is_ug_url(url)


@pytest.mark.parametrize("url", [
    "file:///etc/passwd",
    "http://tabs.ultimate-guitar.com/tab/a",       # not https
    "https://ultimate-guitar.com.evil.example/x",  # suffix trick
    "https://evil.example/ultimate-guitar.com",
    "https://127.0.0.1:8080/",
    "https://localhost/",
    "",
    None,
])
def test_other_urls_are_refused(url):
    assert not chords.is_ug_url(url)


def test_pinned_foreign_url_is_never_fetched(fake_ug):
    out = provider().lookup("x", "y", chord_url="http://192.168.1.1/admin")
    assert fake_ug.fetched == [] or all("search.php" in u for u in fake_ug.fetched)
    assert "192.168.1.1" not in " ".join(fake_ug.fetched)
    assert out["source"] == "none"


def test_ug_fetch_carries_the_guitarists_metadata(fake_ug):
    fake_ug.pages[TAB_URL] = ug_page(TAB_VIEW, {"type": "Chords", "version": 2, "votes": 11388, "rating": 4.8})
    got = provider()._ug_fetch({"tab_url": TAB_URL, "song_name": "Y", "artist_name": "X"})
    meta = got["meta"]
    assert meta["tuning"] == {"name": "Standard", "notes": ["E", "A", "D", "G", "B", "E"]}
    assert (meta["difficulty"], meta["tonality"], meta["type"]) == ("novice", "F#m", "Chords")
    assert (meta["views"], meta["favorites"], meta["votes"], meta["author"]) == (1234, 56, 11388, "someone")
    assert meta["bpm"] == 87 and meta["strumming"][0]["measures"] == [1, 202, 3]
    assert got["capo"] == 2 and got["key"] == "F#m" and got["kind"] == "chords"
    # UG's own fingerings come through, low E first; garbage entries are dropped
    assert list(got["applicature"]) == ["Em"]
    assert got["applicature"]["Em"][0]["frets"] == [0, 2, 2, 0, 0, 0]


def test_metadata_survives_a_sparse_page(fake_ug):
    fake_ug.pages[TAB_URL] = ug_page({"wiki_tab": {"content": CHORDS_BODY}})
    got = provider()._ug_fetch({"tab_url": TAB_URL})
    assert got["meta"]["tuning"] == {"name": "", "notes": []} and got["meta"]["bpm"] is None
    assert got["applicature"] == {}


def test_a_tabs_only_song_falls_back_to_tablature(fake_ug):
    fake_ug.pages["search"] = ug_search_page([result(TABS_URL, "Tabs"), result(TAB_URL, "Official")])
    fake_ug.pages[TABS_URL] = ug_page({"wiki_tab": {"content": TAB_BODY}, "meta": {"tuning": {"name": "Standard", "value": "E A D G B E"}}})
    got = provider().lookup("X", "Y")
    assert got["kind"] == "tab" and got["url"] == TABS_URL


def test_chords_are_preferred_over_tabs(fake_ug):
    fake_ug.pages["search"] = ug_search_page([result(TABS_URL, "Tabs"), result(TAB_URL, "Chords")])
    fake_ug.pages[TAB_URL] = ug_page(TAB_VIEW)
    fake_ug.pages[TABS_URL] = ug_page({"wiki_tab": {"content": TAB_BODY}})
    got = provider().lookup("X", "Y")
    assert got["url"] == TAB_URL and TABS_URL not in fake_ug.fetched


def test_a_found_chart_is_cached(fake_ug):
    fake_ug.pages["search"] = ug_search_page([result(TAB_URL, "Chords")])
    fake_ug.pages[TAB_URL] = ug_page(TAB_VIEW)
    p = provider()
    p.lookup("X", "Y")
    before = len(fake_ug.fetched)
    again = p.lookup("X", "Y")
    assert again["cached"] is True and len(fake_ug.fetched) == before


def test_a_pinned_tab_wins_and_is_marked(fake_ug):
    fake_ug.pages[TABS_URL] = ug_page({"wiki_tab": {"content": TAB_BODY}})
    got = provider().lookup("X", "Y", chord_url=TABS_URL)
    assert got["pinned"] is True and got["kind"] == "tab"


def test_local_chart_beats_the_internet(fake_ug):
    p = provider()
    p.save_local("X", "Y", "{title: Y}\n[Am]hello [F]world")
    got = p.lookup("X", "Y")
    assert got["source"] == "local" and fake_ug.fetched == []
    assert p.delete_local("X", "Y") is True


def test_unreadable_pages_do_not_raise(fake_ug):
    fake_ug.pages["search"] = "<html>no store here</html>"
    got = provider().lookup("X", "Y")
    assert got["source"] == "none" and got["sections"] == []


# ---- review pass ----

def test_search_queries_are_url_encoded(fake_ug, monkeypatch):
    urls = []

    def fetch(url, **kwargs):
        urls.append(url)
        return ug_search_page([])

    monkeypatch.setattr(chords, "fetch", fetch)
    provider()._ug_search("Rock & Roll #1 आसमान")
    (url,) = urls
    assert "%26" in url and "%23" in url          # & and # would cut the query short
    assert "&Roll" not in url and "#1" not in url
    assert "%E0%A4%86" in url                     # non-ASCII is UTF-8 percent-encoded
    assert url.isascii()                          # urllib refuses a non-ASCII URL outright
    assert "Rock+%26+Roll" in url                 # spaces stay '+', as the site writes them


def test_a_file_named_after_the_artist_is_not_every_songs_chart():
    p = provider()
    p.directory.mkdir(parents=True, exist_ok=True)
    (p.directory / "radiohead.chordpro").write_text("[Am]one chart")
    assert p.local_candidates("Radiohead", "Creep") == []
    (p.directory / "creep.chordpro").write_text("[Am]by title")
    assert [f.name for f in p.local_candidates("Radiohead", "Creep")] == ["creep.chordpro"]


def test_a_miss_is_remembered_so_the_site_is_not_searched_again(fake_ug):
    fake_ug.pages["search"] = ug_search_page([])
    p = provider()
    first = p.lookup("X", "Nothing Here")
    assert first["error"] == "no chords found"
    searches = len(fake_ug.fetched)
    assert searches > 0
    again = p.lookup("X", "Nothing Here")
    assert again["source"] == "none" and again["cached"] is True
    assert len(fake_ug.fetched) == searches, "the second lookup went back to the network"


def test_a_rate_limited_miss_is_also_not_hammered(fake_ug, monkeypatch):
    calls = []

    def fetch(url, **kwargs):
        calls.append(url)
        raise chords.HttpError(502, url)

    monkeypatch.setattr(chords, "fetch", fetch)
    p = provider()
    p.lookup("X", "Y")
    n = len(calls)
    p.lookup("X", "Y")
    assert len(calls) == n


def test_a_pinned_tab_that_fails_to_load_falls_back_and_says_so(fake_ug, monkeypatch):
    fake_ug.pages["search"] = ug_search_page([result(TAB_URL, "Chords")])
    fake_ug.pages[TAB_URL] = ug_page(TAB_VIEW)

    def fetch(url, **kwargs):
        if url == TABS_URL:
            raise chords.HttpError(404, url)
        return fake_ug.pages["search"] if "search.php" in url else fake_ug.pages[url]

    monkeypatch.setattr(chords, "fetch", fetch)
    got = provider().lookup("X", "Y", chord_url=TABS_URL)
    assert got["url"] == TAB_URL            # the automatic pick took over
    assert got["pin_failed"] is True        # and the widget can tell the user
    assert "pinned" not in got


def test_a_pin_that_works_is_not_marked_failed(fake_ug):
    fake_ug.pages[TABS_URL] = ug_page({"wiki_tab": {"content": TAB_BODY}})
    got = provider().lookup("X", "Y", chord_url=TABS_URL)
    assert got["pinned"] is True and "pin_failed" not in got


def test_saving_and_finding_a_chart_agree_on_decorated_names():
    p = provider(chords_sources=["local"])
    p.save_local("Radiohead - Topic", "Creep (Official Video)", "{title: Creep}\n[Am]hello [F]world")
    assert p.lookup("Radiohead - Topic", "Creep (Official Video)")["source"] == "local"
    assert p.lookup("Radiohead", "Creep")["source"] == "local"      # the cleaned name finds it too
    assert p.delete_local("Radiohead", "Creep (Official Video)") is True
    assert p.lookup("Radiohead", "Creep")["source"] == "none"

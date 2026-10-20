# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
#
# SPDX-License-Identifier: MIT

from __future__ import annotations

import threading
import time

import pytest

from lyricist import http
from lyricist.cache import DiskCache, key_for
from lyricist.songprefs import SongPrefs


def test_throttle_spaces_a_host_but_not_two_hosts():
    throttle = http.Throttle(0.25)
    start = time.monotonic()
    throttle.wait("https://a.example/1")
    throttle.wait("https://b.example/1")
    assert time.monotonic() - start < 0.2
    throttle.wait("https://a.example/2")
    assert time.monotonic() - start >= 0.25


def test_a_waiting_host_does_not_block_another():
    throttle = http.Throttle(0.6)
    throttle.wait("https://slow.example/")
    done: dict[str, float] = {}

    def slow() -> None:
        throttle.wait("https://slow.example/")  # has to sit out the gap
        done["slow"] = time.monotonic()

    start = time.monotonic()
    thread = threading.Thread(target=slow)
    thread.start()
    time.sleep(0.05)
    throttle.wait("https://fast.example/")
    done["fast"] = time.monotonic()
    thread.join()
    assert done["fast"] - start < 0.3 < done["slow"] - start


@pytest.mark.parametrize("url", ["file:///etc/passwd", "ftp://x/y", "gopher://x"])
def test_fetch_refuses_non_http(url):
    with pytest.raises(ValueError):
        http.fetch(url)


def test_cache_ttl_and_prune(tmp_path):
    cache = DiskCache("t", ttl=0)
    cache.set("fresh", {"a": 1})
    cache.set("stale", {"a": 2}, ttl=1)
    (cache.dir / "broken.json").write_text("{nope")
    assert cache.get("fresh") == {"a": 1}
    time.sleep(1.1)
    assert cache.get("stale") is None
    assert cache.prune() == 2  # the expired one and the unreadable one
    assert cache.get("fresh") == {"a": 1}
    assert cache.stats()["entries"] == 1


def test_cache_key_ignores_case_and_padding():
    assert key_for(" Radiohead ", "CREEP") == key_for("radiohead", "creep")


def test_prefs_clean_and_remember():
    prefs = SongPrefs()
    entry = prefs.update("A", "B", {"offset": "1.5", "transpose": 2, "capo": "x", "chord_url": " u ", "junk": 1})
    assert entry == {"offset": 1.5, "transpose": 2, "chord_url": "u"}
    assert SongPrefs().get("a", "b") == entry  # persisted, key is case-insensitive
    prefs.update("A", "B", {"chord_url": ""})
    assert "chord_url" not in prefs.get("A", "B")
    assert prefs.update("", "", {"offset": 1}) == {}


def test_prefs_evict_the_stalest_not_the_first_written(monkeypatch):
    monkeypatch.setattr("lyricist.songprefs._MAX_ENTRIES", 2)
    prefs = SongPrefs()
    prefs.update("a", "1", {"capo": 1})
    prefs.update("b", "2", {"capo": 2})
    prefs.update("a", "1", {"capo": 3})  # touched again: now the freshest
    prefs.update("c", "3", {"capo": 4})
    assert prefs.get("a", "1") and prefs.get("c", "3") and not prefs.get("b", "2")


def test_an_unwritable_cache_never_breaks_a_request(tmp_path):
    blocker = tmp_path / "file"
    blocker.write_text("not a directory")
    cache = DiskCache("t")
    cache.dir = blocker / "inside"          # mkdir under a regular file fails
    cache.set("k", {"a": 1})                # must not raise
    assert cache.get("k") is None

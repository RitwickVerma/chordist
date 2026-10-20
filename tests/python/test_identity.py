# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
#
# SPDX-License-Identifier: MIT

"""Working out which song is really playing."""

from __future__ import annotations

import pytest

from chordist import identity
from chordist.config import Config


class FakeLyrics:
    """LRCLIB, answering from a dict keyed by (artist, title)."""

    def __init__(self, known):
        self.known, self.calls = known, []

    def lookup(self, artist, title, album="", duration=0.0, **_):
        self.calls.append((artist, title))
        hit = self.known.get((artist, title))
        return hit or {"source": "none", "lines": []}


def entry(artist, track, duration=200, album="Album", lines=True):
    return {"source": "lrclib", "artist": artist, "track": track, "album": album, "duration": duration,
            "lines": [{"t": 1, "text": "x"}] if lines else []}


CONFIG = Config({"fingerprint_enabled": False})


def test_a_clean_pair_resolves_on_the_first_try():
    lyrics = FakeLyrics({("Radiohead", "Creep"): entry("Radiohead", "Creep", 238)})
    got = identity.resolve(CONFIG, lyrics, "Radiohead", "Creep", 238)
    assert got["artist"] == "Radiohead" and got["title"] == "Creep" and got["confidence"] == "duration"
    assert lyrics.calls == [("Radiohead", "Creep")]


def test_a_channel_as_artist_is_dropped_to_find_the_song():
    lyrics = FakeLyrics({("", "Creep"): entry("Radiohead", "Creep", 238)})
    got = identity.resolve(CONFIG, lyrics, "SomeChannel", "Creep", 238)
    assert got["artist"] == "Radiohead"
    assert lyrics.calls[:2] == [("SomeChannel", "Creep"), ("", "Creep")]


def test_a_same_named_song_of_another_length_is_refused():
    lyrics = FakeLyrics({("Radiohead", "Creep"): entry("Radiohead", "Creep", duration=500)})
    assert identity.resolve(CONFIG, lyrics, "Radiohead", "Creep", 238) is None


def test_a_junk_entry_that_merely_has_the_right_length_is_refused():
    lyrics = FakeLyrics({("X", "Raabta"): entry("Nobody", "YOUTUBE", duration=200)})
    assert identity.resolve(CONFIG, lyrics, "X", "Raabta", 200) is None


def test_no_duration_means_the_name_has_to_stand_alone():
    lyrics = FakeLyrics({("A", "Song"): entry("A", "Song", duration=999)})
    assert identity.resolve(CONFIG, lyrics, "A", "Song", 0)["title"] == "Song"


def test_an_entry_with_no_lyrics_does_not_count_unless_instrumental():
    lyrics = FakeLyrics({("A", "Song"): entry("A", "Song", lines=False)})
    assert identity.resolve(CONFIG, lyrics, "A", "Song", 200) is None
    instrumental = {**entry("A", "Tune", lines=False), "instrumental": True}
    assert identity.resolve(CONFIG, FakeLyrics({("A", "Tune"): instrumental}), "A", "Tune", 200) is not None


def test_a_resolved_identity_is_cached():
    lyrics = FakeLyrics({("A", "Song"): entry("A", "Song")})
    identity.resolve(CONFIG, lyrics, "A", "Song", 200)
    identity.resolve(CONFIG, lyrics, "A", "Song", 200)
    assert len(lyrics.calls) == 1


def test_a_title_with_the_film_and_singers_is_taken_apart():
    title = "Judaai - Full Audio Song | Badlapur | Varun Dhawan | Arijit Singh"
    lyrics = FakeLyrics({("", "Judaai"): entry("Arijit Singh", "Judaai", 250, "Badlapur")})
    got = identity.resolve(CONFIG, lyrics, "T-Series", title, 250)
    assert got["artist"] == "Arijit Singh" and got["album"] == "Badlapur"


def test_candidates_start_raw_then_drop_the_channel():
    pairs = identity.candidates("Chan", "Song - Film | Singer")
    assert pairs[0] == ("Chan", "Song - Film | Singer") and pairs[1] == ("", "Song - Film | Singer")


def test_the_audio_is_identified_only_when_the_text_gives_up(monkeypatch):
    seen = []
    monkeypatch.setattr(identity.fingerprint, "identify",
                        lambda config, *parts, **k: seen.append(parts) or {"artist": "Radiohead", "title": "Creep",
                                                                          "album": "", "source": "shazam"})
    config = Config({"fingerprint_enabled": True})
    got = identity.resolve(config, FakeLyrics({}), "Chan", "Creep", 200)
    assert got["confidence"] == "fingerprint" and seen
    seen.clear()
    identity.resolve(config, FakeLyrics({("A", "Song"): entry("A", "Song")}), "A", "Song", 200)
    assert not seen, "found by name: no recording needed"


def test_a_fingerprint_answer_for_a_different_song_is_not_trusted(monkeypatch):
    monkeypatch.setattr(identity.fingerprint, "identify",
                        lambda *a, **k: {"artist": "X", "title": "Totally Different", "album": "", "source": "shazam"})
    assert identity.resolve(Config({"fingerprint_enabled": True}), FakeLyrics({}), "Chan", "Creep", 200) is None


def test_a_caller_that_only_wants_the_known_answer_never_records_audio(monkeypatch):
    def boom(*a, **k):
        raise AssertionError("must not record")

    monkeypatch.setattr(identity.fingerprint, "identify", boom)
    config = Config({"fingerprint_enabled": True})
    assert identity.resolve(config, FakeLyrics({}), "Chan", "Creep", 0, allow_fingerprint=False) is None
    # and that miss was not cached: the next, real lookup still gets to try
    monkeypatch.setattr(identity.fingerprint, "identify", lambda *a, **k: None)
    assert identity.resolve(config, FakeLyrics({("Chan", "Creep"): entry("Chan", "Creep")}), "Chan", "Creep", 200)


@pytest.mark.parametrize(("reported", "duration", "agrees"), [
    (238, 238, True), (238, 241, True), (238, 246, False), (0, 238, True), (238, 0, True), (None, 200, True),
    (300, 305, True), (300, 330, False),
])
def test_recording_lengths_agree_within_a_small_window(reported, duration, agrees):
    assert identity._duration_agrees(reported, duration) is agrees


def test_an_error_in_the_lyrics_provider_does_not_stop_the_search():
    class Flaky(FakeLyrics):
        def lookup(self, artist, title, *a, **k):
            if artist == "Chan":
                raise RuntimeError("down")
            return super().lookup(artist, title, *a, **k)

    lyrics = Flaky({("", "Creep"): entry("Radiohead", "Creep", 238)})
    assert identity.resolve(CONFIG, lyrics, "Chan", "Creep", 238)["artist"] == "Radiohead"

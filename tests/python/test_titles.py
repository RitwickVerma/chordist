# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
#
# SPDX-License-Identifier: MIT

"""Taking apart the titles streaming sites and players hand us."""

from __future__ import annotations

from chordist import titles

JUDAAI = "Judaai - Full Audio Song | Badlapur | Varun Dhawan, Yami Gautam | Rekha Bhardwaj & Arijit Singh"


def test_the_song_leads_in_an_indian_video_title():
    assert titles.song_candidates(JUDAAI)[:2] == ["Judaai", "Badlapur"]


def test_the_whole_title_is_always_a_last_resort():
    assert titles.song_candidates(JUDAAI)[-1] == JUDAAI
    assert titles.song_candidates("Kal Ho Naa Ho") == ["Kal Ho Naa Ho"]


def test_noise_and_credits_are_not_song_names():
    names = titles.song_candidates(JUDAAI)
    assert not any("Full Audio" in n or "Varun" in n or "Arijit" in n for n in names[:-1])


def test_artist_hints_start_with_the_players_artist_then_the_credits():
    hints = titles.artist_hints(JUDAAI, "T-Series")
    assert hints[0] == "T-Series"
    assert "Varun Dhawan" in hints and "Arijit Singh" in hints


def test_the_film_is_an_album_hint():
    assert titles.album_hints(JUDAAI) == ["Badlapur"]


def test_queries_start_with_the_whole_string_then_narrow():
    queries = titles.candidate_queries("T-Series", JUDAAI, album="Badlapur")
    assert queries[0] == f"T-Series {JUDAAI}"
    assert queries[1] == JUDAAI
    assert "Judaai" in queries
    assert len(queries) <= 6


def test_a_clean_title_needs_few_queries():
    queries = titles.candidate_queries("Radiohead", "Creep")
    assert queries == ["Radiohead Creep", "Creep"]


def test_a_tab_is_trusted_only_if_it_adds_no_new_words():
    assert titles.subset("Arijit Singh Judaai Badlapur", "Judaai")
    assert not titles.subset("Judaai", "I Love Ny - Judaai")       # a different film's song
    assert not titles.subset("Judaai", "Judaa")
    assert titles.subset("Creep Radiohead", "Creep (Acoustic)")   # a version word is allowed


def test_a_tab_must_share_a_word_with_the_title():
    assert titles.shares_word("Wonderwall", "Wonderwall (Live)")
    assert not titles.shares_word("Wonderwall", "Champagne Supernova")


def test_a_song_filed_under_its_film():
    assert titles.film_filed("Zinda", "Lootera - Zinda", "Zinda Lootera Sidharth")


def test_tokens_are_lowercase_words_without_punctuation():
    assert titles.tokens("Don't Stop (Believin')") == ["don", "t", "stop", "believin"]
    assert titles.tokens("") == []


def test_split_segments_keeps_order_and_drops_empties():
    assert titles.split_segments("A | B - C /  ") == ["A", "B", "C"]

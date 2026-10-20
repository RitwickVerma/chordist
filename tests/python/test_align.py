# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
#
# SPDX-License-Identifier: MIT

from __future__ import annotations

from chordist import align


def chart(*lyrics):
    return {"sections": [{"name": "", "lines": [{"lyric": text, "chords": []} for text in lyrics]}]}


def timed(*pairs):
    return {"lines": [{"t": t, "text": text} for t, text in pairs]}


def test_rows_are_matched_to_the_lines_they_say():
    times = align.row_times(
        chart("when you were here before", "couldn't look you in the eye"),
        timed((10, "When you were here before"), (15, "Couldn't look you in the eye")),
    )
    assert times == [10, 15]


def test_a_repeated_chorus_takes_each_occurrence_in_order():
    rows = ["la la la dee dah", "hello from the verse", "la la la dee dah"]
    lines = [(5, "la la la dee dah"), (10, "hello from the verse"), (20, "la la la dee dah")]
    assert align.row_times(chart(*rows), timed(*lines)) == [5, 10, 20]


def test_time_never_runs_backwards():
    rows = ["alpha beta gamma delta", "epsilon zeta eta theta", "iota kappa lambda mu"]
    lines = [(30, "iota kappa lambda mu"), (10, "alpha beta gamma delta"), (20, "epsilon zeta eta theta")]
    times = align.row_times(chart(*rows), timed(*sorted(lines)))
    assert times == sorted(times)


def test_a_one_word_row_cannot_anchor_a_line():
    assert align.similarity("haan", "haan tum ho mere") == 0.0
    times = align.row_times(chart("haan", "tum ho mere pyaar mein"), timed((12, "haan tum ho mere pyaar mein")))
    assert times[1] == 12


def test_unmatched_rows_are_spread_between_matched_ones():
    rows = ["one two three four", "mystery words nobody sings", "five six seven eight"]
    times = align.row_times(chart(*rows), timed((10, "one two three four"), (30, "five six seven eight")))
    assert times == [10, 20, 30]


def test_nothing_to_align_is_none_not_a_guess():
    assert align.row_times(chart("a b c d"), timed()) is None
    assert align.row_times(chart(), timed((1, "a b c d"))) is None
    assert align.row_times(chart("one two three four"), timed((1, "completely different words here"))) is None
    assert align.row_times(chart("a b c"), {"lines": [{"t": None, "text": "a b c"}]}) is None


def test_spelling_drift_still_matches():
    assert align.similarity("kahan se aaye ho", "kahaan se aaye ho") >= 0.75


def test_a_long_song_aligns_quickly():
    import time

    rows = [f"row number {i} with some words {i % 9}" for i in range(140)]
    lines = [(i * 2.0, f"row number {i} with some words {i % 9}") for i in range(140)]
    start = time.perf_counter()
    times = align.row_times(chart(*rows), timed(*lines))
    elapsed = time.perf_counter() - start
    assert times == [i * 2.0 for i in range(140)]
    assert elapsed < 1.5, f"{elapsed:.2f}s"

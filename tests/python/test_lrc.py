# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
#
# SPDX-License-Identifier: MIT

"""LRC parsing, plain and enhanced (word-timed)."""

from __future__ import annotations

from chordist import lrc


def test_lines_are_timed_and_sorted():
    lines = lrc.parse("[00:20.00]second\n[00:10.50]first")
    assert [(line["t"], line["text"]) for line in lines] == [(10.5, "first"), (20.0, "second")]


def test_metadata_tags_are_not_lyrics():
    lines = lrc.parse("[ar:Radiohead]\n[ti:Creep]\n[length:3:58]\n[00:01.00]hello")
    assert [line["text"] for line in lines] == ["hello"]


def test_a_line_with_several_stamps_is_repeated():
    lines = lrc.parse("[00:10.00][01:10.00]chorus")
    assert [line["t"] for line in lines] == [10.0, 70.0]
    assert {line["text"] for line in lines} == {"chorus"}


def test_the_offset_tag_shifts_every_line():
    lines = lrc.parse("[offset:500]\n[00:10.00]late")          # +500 ms: the lyric is sung earlier
    assert lines[0]["t"] == 9.5
    assert lrc.parse("[00:10.00]x", offset_ms=1000)[0]["t"] == 9.0


def test_a_shift_never_goes_below_zero():
    assert lrc.parse("[00:00.20]x", offset_ms=1000)[0]["t"] == 0.0


def test_enhanced_lrc_gives_every_word_its_own_time():
    (line,) = lrc.parse("[00:12.34]<00:12.34>and <00:12.51>the <00:12.70>coloured <00:13.02>lights")
    assert line["text"] == "and the coloured lights"
    assert [(w["t"], w["text"]) for w in line["words"]] == [
        (12.34, "and"), (12.51, "the"), (12.7, "coloured"), (13.02, "lights")]


def test_plain_lines_have_no_words():
    assert lrc.parse("[00:01.00]hello")[0]["words"] == []


def test_blank_timed_lines_are_kept_as_gaps():
    lines = lrc.parse("[00:05.00]\n[00:09.00]sung")
    assert [line["text"] for line in lines] == ["", "sung"]


def test_empty_and_unstamped_text_parse_to_nothing():
    assert lrc.parse("") == [] and lrc.parse("just words\nno stamps") == []


def test_plain_lyrics_become_untimed_lines():
    lines = lrc.as_plain_lines("one\ntwo  \n\nthree")
    assert [line["text"] for line in lines] == ["one", "two", "", "three"]
    assert all(line["t"] is None for line in lines)


def test_flattening_to_plain_text_skips_blank_lines():
    assert lrc.to_plain(lrc.parse("[00:01.00]a\n[00:02.00]\n[00:03.00]b")) == "a\nb"

# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
#
# SPDX-License-Identifier: MIT

from __future__ import annotations

from lyricist import chart

UG_CHORDS = """[Intro]
[ch]Am[/ch]  [ch]F[/ch]

[Verse 1]
[tab][ch]Am[/ch]        [ch]F[/ch]
When you were here before[/tab]
"""

STAFF = """[tab]e|-----0-----|
B|---1-------|

G|-0---------|
D|-----------|
A|-----------|
E|-3---------|[/tab]"""


def lines(result):
    return [line for section in result["sections"] for line in section["lines"]]


def test_ug_chord_over_lyric_positions():
    result = chart.parse(UG_CHORDS, fmt="ug")
    verse = next(s for s in result["sections"] if s["name"] == "Verse 1")
    row = verse["lines"][0]
    assert row["lyric"] == "When you were here before"
    assert [(c["pos"], c["name"]) for c in row["chords"]] == [(0, "Am"), (10, "F")]
    assert result["chord_names"] == ["Am", "F"]
    assert result["kind"] == "chords"


def test_instrumental_row_has_no_lyric():
    intro = chart.parse(UG_CHORDS, fmt="ug")["sections"][0]
    assert intro["name"] == "Intro"
    assert intro["lines"][0]["instrumental"] is True


def test_staff_survives_a_blank_line_inside_it():
    result = chart.parse(STAFF, fmt="ug")
    staves = [line["staff"] for line in lines(result)]
    assert len(staves) == 1
    assert staves[0]["labels"] == ["e", "B", "G", "D", "A", "E"]
    assert all(row.startswith("|") for row in staves[0]["rows"])
    assert len({len(row) for row in staves[0]["rows"]}) == 1
    assert result["kind"] == "tab"


def test_two_stacked_staves_are_cut_at_six_rows():
    block = "[tab]" + "\n".join(f"{s}|---{i}---|" for i, s in enumerate("eBGDAE" * 2)) + "[/tab]"
    assert len([line for line in lines(chart.parse(block, fmt="ug")) if "staff" in line]) == 2


def test_four_string_bass_staff():
    block = "[tab]G|--3--|\nD|--0--|\nA|-----|\nE|-----|[/tab]"
    staff = next(line["staff"] for line in lines(chart.parse(block, fmt="ug")) if "staff" in line)
    assert staff["labels"] == ["G", "D", "A", "E"]


def test_prose_that_looks_a_little_like_tab_is_not_a_staff():
    result = chart.parse("[Verse]\nA|b sides\nE: minor key\n", fmt="ug")
    assert not any("staff" in line for line in lines(result))


def test_staff_gets_a_tab_section_and_preamble_stays_apart():
    text = "Tabbed by someone\n" + STAFF
    sections = chart.parse(text, fmt="ug")["sections"]
    assert [s["name"] for s in sections] == ["", "Tab"]


def test_chordpro_roundtrip_keeps_staves_and_chords():
    original = chart.parse(UG_CHORDS + "\n" + STAFF, fmt="ug")
    again = chart.parse(chart.to_chordpro(original))
    assert again["kind"] == "mixed"
    assert again["chord_names"] == original["chord_names"]
    assert [line["staff"] for line in lines(again) if "staff" in line] == [
        line["staff"] for line in lines(original) if "staff" in line
    ]


def test_plain_text_pairs_chord_row_with_lyric():
    result = chart.parse("Am      F\nHello darkness my old friend\n", fmt="plain")
    row = lines(result)[0]
    assert row["lyric"].startswith("Hello") and [c["name"] for c in row["chords"]] == ["Am", "F"]


def test_detect_format():
    assert chart.detect_format("[ch]C[/ch]") == "ug"
    assert chart.detect_format("{title: x}\n[C]hi") == "chordpro"
    assert chart.detect_format("C   G\nhello") == "plain"


def test_empty_chart_is_well_formed():
    result = chart.parse("   ")
    assert result["sections"] == [] and result["kind"] == "chords" and result["chord_names"] == []


def test_chord_normalising():
    assert chart.normalize_chord("B♭maj7") == "Bbmaj7"
    assert chart.normalize_chord("H") == "B"
    assert chart.is_chord("F#m7/C#") and not chart.is_chord("Hello")

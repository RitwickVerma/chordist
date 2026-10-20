from __future__ import annotations

from lyricist import shapes


def test_open_c_is_the_textbook_shape():
    shape = shapes.shape_for("C")
    assert shape["frets"] == [-1, 3, 2, 0, 1, 0] and shape["base"] == 1


def test_barre_chord_has_its_barre_and_finger_numbers():
    shape = shapes.shape_for("F#m")
    assert shape["frets"] == [2, 4, 4, 2, 2, 2] and shape["barre"] == 2 and shape["base"] == 1
    assert shape["fingers"] == [1, 3, 4, 1, 1, 1] and shape["source"] == "chords-db"


def test_database_frets_are_made_absolute_for_higher_positions():
    # chords-db stores the second F voicing relative to its base fret (3).
    higher = shapes.variants_for("F")[1]
    assert higher["base"] == 3 and higher["frets"] == [-1, 3, 3, 5, 6, 5] and higher["barre"] == 3


def test_open_voicings_come_before_barre_voicings():
    for name in ("C", "G", "Am", "E7"):
        bases = [v["base"] for v in shapes.variants_for(name)]
        assert bases[0] == 1, name


def test_spellings_of_one_chord_share_voicings():
    assert shapes.shape_for("A#")["frets"] == shapes.shape_for("Bb")["frets"]
    assert shapes.shape_for("Amin")["frets"] == shapes.shape_for("Am")["frets"]
    assert shapes.shape_for("Dmaj")["frets"] == shapes.shape_for("D")["frets"]


def test_slash_chords_use_their_own_voicing_when_one_exists():
    assert shapes.shape_for("C/E")["frets"] == [0, 3, 2, 0, 1, 0]
    assert shapes.shape_for("C/E")["bass"] == "E"
    # no database entry for this one: the plain chord, tagged with its bass
    assert shapes.shape_for("D/B")["bass"] == "B"


def test_extended_chords_are_found_by_their_own_name():
    assert shapes.shape_for("A7sus4")["frets"] == [-1, 0, 2, 0, 3, 0]
    assert shapes.shape_for("G13") is not None and shapes.shape_for("Fmaj7#5") is not None


def test_a_chord_the_database_lacks_is_derived_not_dropped():
    power = shapes.shape_for("E5")
    assert power["source"] == "derived" and len(power["frets"]) == 6
    assert shapes.shape_for("C#5") is not None


def test_database_loads_and_covers_every_root():
    assert len(shapes._db()) == 12
    assert all(shapes.shape_for(f"{r}m7") for r in ("C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"))


def test_no_chord_has_no_shape():
    assert shapes.shape_for("N.C.") is None and shapes.shape_for("") is None


def test_h_is_b_natural():
    assert shapes.shape_for("Hm")["frets"] == shapes.shape_for("Bm")["frets"]


def test_every_variant_is_six_strings():
    for name in ("C", "Am7", "F#m", "Bbmaj7", "Dsus4", "G/B", "Edim"):
        variants = shapes.variants_for(name)
        assert variants, name
        assert all(len(v["frets"]) == 6 and len(v["fingers"]) == 6 for v in variants)


UG_EM = [
    {"id": "022000", "frets": [0, 0, 0, 2, 2, 0], "fingers": [0, 0, 0, 2, 1, 0]},
    {"id": "dup", "frets": [0, 0, 0, 2, 2, 0], "fingers": [0, 0, 0, 2, 1, 0]},
    {"id": "bad", "frets": [0, 0, 0], "fingers": []},
    "junk",
]


def test_applicature_is_reversed_to_low_e_first_and_keeps_fingers():
    (voicing,) = shapes.from_applicature("Em", UG_EM)
    assert voicing["frets"] == [0, 2, 2, 0, 0, 0]
    assert voicing["fingers"] == [0, 1, 2, 0, 0, 0]
    assert voicing["source"] == "ultimate-guitar" and voicing["base"] == 1


def test_applicature_tolerates_garbage():
    assert shapes.from_applicature("X", None) == []
    assert shapes.from_applicature("X", [{"frets": ["a"] * 6}]) == []


def test_svg_renders():
    assert shapes.svg(shapes.shape_for("G")).startswith("<svg")

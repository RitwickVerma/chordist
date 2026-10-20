from __future__ import annotations

from lyricist import shapes


def test_open_c_is_the_textbook_shape():
    shape = shapes.shape_for("C")
    assert shape["frets"] == [-1, 3, 2, 0, 1, 0] and shape["base"] == 1


def test_barre_chord_is_derived_and_flagged():
    shape = shapes.shape_for("F#m")
    assert shape["frets"] == [2, 4, 4, 2, 2, 2] and shape["barre"] == 2 and shape["base"] == 2


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

# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
#
# SPDX-License-Identifier: MIT

"""Devanagari to Latin: casual romanisation, the way chord sheets spell Hindi."""

from __future__ import annotations

import pytest

from chordist import translit


@pytest.mark.parametrize(
    ("hindi", "latin"),
    [
        ("तुम ही हो", "tum hi ho"),
        ("दिल", "dil"),
        ("ज़िन्दगी", "zindagi"),
        ("क्यों", "kyon"),
        ("हम तुम", "ham tum"),
        ("यहाँ वहाँ", "yahan vahan"),
        ("ख़ुशी", "khushi"),
        ("प्यार १२३", "pyar 123"),
        ("श्री", "shri"),
        ("मेरे पास", "mere pas"),
    ],
)
def test_common_words(hindi, latin):
    assert translit.devanagari_to_latin(hindi) == latin


def test_latin_and_punctuation_pass_through_untouched():
    assert translit.devanagari_to_latin("hello, world! 42") == "hello, world! 42"
    assert translit.devanagari_to_latin("तुम, hello!") == "tum, hello!"
    assert translit.devanagari_to_latin("") == ""


def test_the_final_schwa_can_be_kept():
    assert translit.devanagari_to_latin("दिल", drop_final_schwa=True) == "dil"
    assert translit.devanagari_to_latin("राम", drop_final_schwa=False).endswith("ma")


def test_a_zero_width_joiner_or_bom_does_not_leak_into_the_output():
    assert translit.devanagari_to_latin("\u0915\u094d\u200d\u0937") == translit.devanagari_to_latin("\u0915\u094d\u0937")  # virama + ZWJ
    assert translit.devanagari_to_latin("\ufeff\u0915\u0930") == translit.devanagari_to_latin("\u0915\u0930")
    assert translit.devanagari_to_latin("\u0915\u094d\u200c\u0937").isascii()


def test_script_detection():
    assert translit.has_devanagari("hello तुम")
    assert not translit.has_devanagari("hello")
    assert translit.script_of("तुम ही हो") == "devanagari"
    assert translit.script_of("hello") == "latin"
    assert translit.is_latin("hello world") and not translit.is_latin("तुम ही हो")
    assert translit.needs_romanisation("तुम ही हो hello")
    assert not translit.needs_romanisation("hello world")


def test_ratios_are_fractions_of_the_letters_present():
    assert translit.devanagari_ratio("तुम") == 1.0
    assert translit.devanagari_ratio("abc") == 0.0
    assert translit.latin_ratio("abc") == 1.0
    assert 0 < translit.devanagari_ratio("तुम abc") < 1
    assert translit.devanagari_ratio("") == 0.0

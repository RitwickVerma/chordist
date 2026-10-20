"""Devanagari to Latin transliteration.

Lyrics services often hand back a song's lyrics in its own script while chord
charts come from tab sites that write everything romanised (Hinglish).  That
leaves the same song reading in two different scripts in the same popup.  This
module converts the lyrics to Latin so both halves match.

The romanisation is deliberately the loose, readable kind people actually type
("khwabon", "banaye", "hain"), not a scholarly one: long vowels are written the
same as short ones and a final inherent "a" is dropped, which is what makes
"मेरे ख्वाबों" read as "mere khwabon" rather than "mere khwaabaon".

Stdlib only.  Latin text, punctuation and anything already in another script is
passed through untouched, so it is safe to run over anything.
"""

import re
import unicodedata

__all__ = [
    "devanagari_ratio",
    "devanagari_to_latin",
    "has_devanagari",
    "is_latin",
    "latin_ratio",
    "needs_romanisation",
    "script_of",
]

# Consonants carry an inherent "a" that is written out unless a vowel sign,
# a virama or the end of the word follows.
_CONSONANTS = {
    "क": "k", "ख": "kh", "ग": "g", "घ": "gh", "ङ": "ng",
    "च": "ch", "छ": "chh", "ज": "j", "झ": "jh", "ञ": "ny",
    "ट": "t", "ठ": "th", "ड": "d", "ढ": "dh", "ण": "n",
    "त": "t", "थ": "th", "द": "d", "ध": "dh", "न": "n",
    "प": "p", "फ": "ph", "ब": "b", "भ": "bh", "म": "m",
    "य": "y", "र": "r", "ल": "l", "ळ": "l", "व": "v",
    "श": "sh", "ष": "sh", "स": "s", "ह": "h",
    "ऩ": "n", "ऱ": "r",
}

# The precomposed nukta forms the table above cannot hold portably.
_NUKTA = {
    "क": "q", "ख": "kh", "ग": "gh", "ज": "z",
    "ड": "r", "ढ": "rh", "फ": "f", "य": "y",
}

_VOWELS = {
    "अ": "a", "आ": "a", "इ": "i", "ई": "i", "उ": "u", "ऊ": "u",
    "ऋ": "ri", "ॠ": "ri", "ऌ": "li", "ए": "e", "ऐ": "ai",
    "ओ": "o", "औ": "au", "ऑ": "o", "ऍ": "e", "ऎ": "e", "ऒ": "o",
}

_MATRAS = {
    "ा": "a", "ि": "i", "ी": "i", "ु": "u", "ू": "u",
    "ृ": "ri", "ॄ": "ri", "ॢ": "li", "े": "e", "ै": "ai",
    "ो": "o", "ौ": "au", "ॉ": "o", "ॅ": "e", "ॆ": "e", "ॊ": "o",
}

_MARKS = {
    "ं": "n",   # anusvara
    "ँ": "n",   # candrabindu
    "ः": "h",   # visarga
    "ऽ": "'",   # avagraha
    "ॐ": "om",
    "।": ".",
    "॥": "..",
    "\u0970": ".",  # abbreviation sign
}

_DIGITS = {chr(0x0966 + i): str(i) for i in range(10)}

_VIRAMA = "\u094d"
_NUKTA_SIGN = "\u093c"
_ZWJ = "\u200d"
_ZWNJ = "\u200c"
_BOM = "\ufeff"

_DEVANAGARI_RE = re.compile(r"[\u0900-\u097f]")
_LATIN_RE = re.compile(r"[A-Za-z]")
_VOWEL_LETTERS = "aeiou"


def _is_word_char(ch):
    """True for the characters that continue a word (letters and digits)."""
    return ch.isalnum() or bool(_DEVANAGARI_RE.match(ch))


def devanagari_to_latin(text, drop_final_schwa=True):
    """Romanise Devanagari text.  Anything else is passed through unchanged."""
    if not text:
        return text or ""

    text = unicodedata.normalize("NFC", text)
    out = []
    index = 0
    length = len(text)
    in_cluster = False

    while index < length:
        char = text[index]
        previous_cluster = in_cluster
        in_cluster = False

        if char in (_ZWJ, _ZWNJ, _BOM):
            index += 1
            continue

        if char in _CONSONANTS:
            letters = _CONSONANTS[char]
            # A half consonant is followed by a consonant in the same cluster,
            # where "व" is written "w" ("ख्वाबों" -> "khwabon", not "khvabon").
            if char == "व" and previous_cluster:
                letters = "w"
            index += 1

            if index < length and text[index] == _NUKTA_SIGN:
                letters = _NUKTA.get(char, letters)
                index += 1

            if index < length and text[index] in _MATRAS:
                out.append(letters + _MATRAS[text[index]])
                index += 1
            elif index < length and text[index] == _VIRAMA:
                out.append(letters)
                index += 1
                in_cluster = True
            elif drop_final_schwa and (index >= length or not _is_word_char(text[index])):
                # Word-final inherent vowel: "मेरे ख्वाब" -> "mere khwab".
                out.append(letters)
            else:
                out.append(letters + "a")
            continue

        if char in _VOWELS:
            vowel = _VOWELS[char]
            # A vowel right after a vowel is normally written with a glide:
            # "बनाए" -> "banaye", "गए" -> "gaye" (but "जाओ" stays "jao").
            if (vowel[0] in "ei" and out and out[-1]
                    and out[-1][-1] in _VOWEL_LETTERS):
                vowel = "y" + vowel
            out.append(vowel)
            index += 1
            continue

        if char in _MARKS:
            out.append(_MARKS[char])
            index += 1
            continue

        if char in _DIGITS:
            out.append(_DIGITS[char])
            index += 1
            continue

        out.append(char)
        index += 1

    result = "".join(out)
    # The nominal vowels can leave doubled letters ("merii"); collapse them.
    return re.sub(r"([aeiou])\1+", r"\1", result)


def has_devanagari(text):
    return bool(text) and bool(_DEVANAGARI_RE.search(text))


def devanagari_ratio(text):
    """Share of the letter characters that are Devanagari, 0..1."""
    if not text:
        return 0.0
    devanagari = len(_DEVANAGARI_RE.findall(text))
    latin = len(_LATIN_RE.findall(text))
    total = devanagari + latin
    return devanagari / total if total else 0.0


def latin_ratio(text):
    """Share of the letter characters that are plain Latin, 0..1."""
    if not text:
        return 0.0
    devanagari = len(_DEVANAGARI_RE.findall(text))
    latin = len(_LATIN_RE.findall(text))
    total = devanagari + latin
    return latin / total if total else 0.0


def is_latin(text, threshold=0.9):
    """True when the text is essentially Latin script (or has no letters)."""
    if not text:
        return True
    return latin_ratio(text) >= threshold


def needs_romanisation(text, threshold=0.25):
    """True when the text is substantially in Devanagari."""
    return devanagari_ratio(text) >= threshold


def script_of(text):
    """"devanagari", "latin", "mixed" or "none"."""
    if not text or not text.strip():
        return "none"
    devanagari = devanagari_ratio(text)
    latin = latin_ratio(text)
    if devanagari == 0 and latin == 0:
        return "none"
    if devanagari >= 0.25 and latin >= 0.25:
        return "mixed"
    return "devanagari" if devanagari > latin else "latin"

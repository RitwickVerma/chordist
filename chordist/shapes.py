# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
#
# SPDX-License-Identifier: MIT

"""Chord diagram data.

No images and no network: a chord name is turned into fret/finger positions that
the widget draws itself, so diagrams stay crisp at any DPI and follow the Plasma
colour scheme.

Fingerings come from chords-db (https://github.com/tombatossals/chords-db, MIT,
(c) 2016 David Rubert), vendored in ``data/guitar-chords.json``: real voicings
with finger numbers and barres, several positions per chord, slash chords
included. Chords it lacks (power chords, unusual extensions) are derived from
the standard movable E-shape and A-shape barre forms, transposed to the root.
"""

from __future__ import annotations

import functools
import json
import re
from pathlib import Path
from typing import Any

_DATA = Path(__file__).resolve().parent / "data" / "guitar-chords.json"

NOTE_PC: dict[str, int] = {
    "C": 0, "B#": 0,
    "C#": 1, "Db": 1,
    "D": 2,
    "D#": 3, "Eb": 3,
    "E": 4, "Fb": 4,
    "F": 5, "E#": 5,
    "F#": 6, "Gb": 6,
    "G": 7,
    "G#": 8, "Ab": 8,
    "A": 9,
    "A#": 10, "Bb": 10,
    "B": 11, "Cb": 11,
}

# How chords-db spells its twelve keys.
_DB_KEYS = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
# Our canonical suffixes, in chords-db's words.
_DB_SUFFIX = {
    "": "major", "m": "minor", "7": "7", "maj7": "maj7", "m7": "m7", "6": "6", "m6": "m6",
    "sus4": "sus4", "sus2": "sus2", "dim": "dim", "aug": "aug", "m7b5": "m7b5", "add9": "add9",
    "9": "9", "m9": "m9", "maj9": "maj9",
}

_STRING_ROOT = {"E": 4, "A": 9}

_CHORD_RE = re.compile(r"^([A-G][#b♯♭]?)(.*?)(?:/([A-G][#b♯♭]?))?$")


@functools.lru_cache(maxsize=1)
def _db() -> dict[str, dict[str, list[dict[str, Any]]]]:
    try:
        return json.loads(_DATA.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


# Movable barre forms: suffix -> string-set -> (offsets, fingers)
# Offsets are relative to the root fret on that string; "x" mutes the string.
_MOVABLE: dict[str, dict[str, tuple[str, str]]] = {
    "": {"E": ("022100", "023400"), "A": ("x02210", "x02310")},
    "m": {"E": ("022000", "023400"), "A": ("x02210", "x02310")},
    "7": {"E": ("020100", "020100"), "A": ("x02020", "x02030")},
    "maj7": {"E": ("x02100", "x03210"), "A": ("x02120", "x03240")},
    "m7": {"E": ("020000", "020000"), "A": ("x02010", "x02130")},
    "6": {"E": ("022120", "023140"), "A": ("x02222", "x01234")},
    "m6": {"E": ("022020", "023010"), "A": ("x02212", "x02314")},
    "sus4": {"E": ("022200", "012340"), "A": ("x02230", "x01230")},
    "sus2": {"E": ("024400", "013400"), "A": ("x02200", "x01340")},
    "dim": {"E": ("x12000", "x12000"), "A": ("x01210", "x01320")},
    "aug": {"E": ("032110", "043210"), "A": ("x03221", "x04321")},
    "m7b5": {"E": ("013120", "012430"), "A": ("x01010", "x01020")},
    "5": {"E": ("022xxx", "013xxx"), "A": ("x022xx", "x012xx")},
    "add9": {"E": ("024100", "013400"), "A": ("x02420", "x01340")},
    "9": {"E": ("020102", "020103"), "A": ("x02022", "x03024")},
    "m9": {"E": ("020002", "020003"), "A": ("x02012", "x02013")},
    "maj9": {"E": ("021102", "032104"), "A": ("x02122", "x03214")},
}

# Map the many ways people write a suffix onto the shapes above.
_SUFFIX_ALIASES: dict[str, str] = {
    "major": "", "maj": "", "M": "", "MAJ": "",
    "min": "m", "-": "m", "minor": "m",
    "dom7": "7", "dom": "7",
    "ma7": "maj7", "MA7": "maj7", "M7": "maj7", "Δ": "maj7", "Δ7": "maj7", "major7": "maj7",
    "minor7": "m7", "-7": "m7", "min7": "m7",
    "maj6": "6", "M6": "6",
    "min6": "m6", "-6": "m6",
    "sus": "sus4", "suspended": "sus4", "sus4": "sus4", "sus2": "sus2",
    "dim7": "dim", "o": "dim", "°": "dim", "diminished": "dim",
    "+": "aug", "+5": "aug", "augmented": "aug", "#5": "aug",
    "ø": "m7b5", "m7-5": "m7b5", "min7b5": "m7b5", "halfdim": "m7b5",
    "pow": "5", "no3": "5",
    "add2": "add9", "add9": "add9", "2": "add9",
    "7sus4": "sus4", "7sus": "sus4",
    "11": "7", "13": "7", "7-9": "7", "7b9": "7", "7#9": "7",
    "69": "6", "6/9": "6",
    "m11": "m7", "m13": "m7", "madd9": "m9",
}


def canonical_suffix(raw: str) -> str:
    value = (raw or "").strip().replace("♯", "#").replace("♭", "b")
    if not value:
        return ""
    if value in _SUFFIX_ALIASES:
        return _SUFFIX_ALIASES[value]
    if value in _MOVABLE:
        return value
    return _SUFFIX_ALIASES.get(value, "")


def _expand_fingers(compact: str) -> list[int]:
    return [-1 if ch in "xX" else int(ch) for ch in compact]


def _transpose(compact: str, fret: int) -> list[int]:
    return [-1 if ch in "xX" else fret + int(ch) for ch in compact]


def _base_fret(frets: list[int]) -> int:
    # Any open string means we are at the nut, so the diagram shows the nut.
    if any(fret == 0 for fret in frets):
        return 1
    played = [fret for fret in frets if fret > 0]
    if not played:
        return 1
    lowest = min(played)
    return lowest if lowest > 1 else 1


def _barre_fret(frets: list[int]) -> int | None:
    """The fret of a barre, if the outermost played strings share the lowest fret."""
    played = [index for index, fret in enumerate(frets) if fret > 0]
    if not played:
        return None
    lowest = min(frets[index] for index in played)
    first, last = played[0], played[-1]
    if frets[first] != lowest or frets[last] != lowest:
        return None
    if sum(1 for index in played if frets[index] == lowest) < 2:
        return None
    return lowest



def _parse(name: str) -> tuple[str, str, str, str | None] | None:
    """``(cleaned, root, suffix, bass)`` for a playable chord symbol, else ``None``."""
    cleaned = (name or "").strip().replace("♯", "#").replace("♭", "b")
    if not cleaned or cleaned.upper() in ("N.C.", "NC", "X"):
        return None
    # German charts write B natural as H (and the letter B means B flat there),
    # so Hm is Bm. Only H is rewritten: an English B is a B natural.
    if cleaned[:1] in ("H", "h"):
        cleaned = "B" + cleaned[1:]
    match = _CHORD_RE.match(cleaned)
    if not match or match.group(1) not in NOTE_PC:
        return None
    return cleaned, match.group(1), match.group(2) or "", match.group(3)


def _db_voicings(
    name: str, root: str, suffix_raw: str, bass: str | None
) -> list[dict[str, Any]]:
    """The chords-db voicings of a chord: open shapes first, then up the neck."""
    table = _db().get(_DB_KEYS[NOTE_PC[root]], {})
    raw = {"maj": "major", "M": "major", "min": "minor", "-": "minor"}.get(suffix_raw, suffix_raw)
    suffix = raw if raw in table else _DB_SUFFIX.get(canonical_suffix(suffix_raw))
    if suffix is None or suffix not in table:
        return []
    positions = table[suffix]
    # A slash chord has voicings of its own where chords-db lists them.
    if bass and bass in NOTE_PC and suffix in ("major", "minor"):
        slash = ("m/" if suffix == "minor" else "/") + _DB_KEYS[NOTE_PC[bass]]
        positions = table.get(slash) or positions
    out: list[dict[str, Any]] = []
    for position in positions:
        base = int(position.get("base") or 1)
        # chords-db frets count from the base fret of the box; ours are absolute.
        frets = [f if f <= 0 else f + base - 1 for f in position["frets"]]
        barres = position.get("barres") or []
        voicing = _voicing(name, frets, [int(f) for f in position["fingers"]], bass, None, False)
        voicing["base"] = base
        voicing["barre"] = barres[0] + base - 1 if barres else None
        voicing["source"] = "chords-db"
        out.append(voicing)
    return out


def _movable_voicings(
    name: str, root: str, suffix_raw: str, bass: str | None
) -> list[dict[str, Any]]:
    """Barre shapes derived for chords the database lacks, lowest position first."""
    suffix = canonical_suffix(suffix_raw)
    approx = bool(suffix_raw and suffix == "" and not suffix_raw.isdigit())
    forms = _MOVABLE.get(suffix) or _MOVABLE[""]
    approx = approx or suffix not in _MOVABLE
    out: list[dict[str, Any]] = []
    seen: set[tuple[int, ...]] = set()
    for string_name, root_of_string in _STRING_ROOT.items():
        fret = (NOTE_PC[root] - root_of_string) % 12 or 12
        picked = forms.get(string_name)
        if not picked:
            continue
        frets = _transpose(picked[0], fret)
        if tuple(frets) in seen:
            continue
        seen.add(tuple(frets))
        voicing = _voicing(name, frets, _expand_fingers(picked[1]), bass, 0 if string_name == "E" else 1, approx)
        voicing["source"] = "derived"
        out.append(voicing)
    out.sort(key=lambda shape: (shape["base"] > 1, shape["base"]))
    return out


def variants_for(name: str) -> list[dict[str, Any]]:
    """Every sensible voicing of a chord symbol, easiest first."""
    parsed = _parse(name)
    if not parsed:
        return []
    cleaned, root, suffix_raw, bass = parsed
    return _db_voicings(cleaned, root, suffix_raw, bass) or _movable_voicings(cleaned, root, suffix_raw, bass)


def shape_for(name: str) -> dict[str, Any] | None:
    """The default voicing of a chord symbol, or ``None`` if unplayable."""
    variants = variants_for(name)
    return variants[0] if variants else None


def shapes_for(names: list[str] | None) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for name in names or []:
        if name in result:
            continue
        shape = shape_for(name)
        if shape is not None:
            result[name] = shape
    return result


def _voicing(name: str, frets: list[int], fingers: list[int], bass: str | None,
             root_string: int | None, approx: bool) -> dict[str, Any]:
    return {
        "name": name,
        "frets": frets,
        "fingers": fingers,
        "base": _base_fret(frets),
        "barre": _barre_fret(frets),
        "bass": bass,
        "root_string": root_string,
        "approx": approx,
    }


def from_applicature(name: str, entries: Any) -> list[dict[str, Any]]:
    """Voicings in Ultimate Guitar's own ``applicature`` format, as ours.

    UG lists strings from the high e down to the low E; this module goes low to
    high, so both arrays are reversed. Entries that are not six strings of
    plain integers are dropped rather than guessed at. Finger numbers come
    along, which the hand-written tables above do not know.
    """
    out: list[dict[str, Any]] = []
    seen: set[tuple[int, ...]] = set()
    for entry in entries if isinstance(entries, list) else []:
        if not isinstance(entry, dict):
            continue
        frets, fingers = entry.get("frets"), entry.get("fingers")
        if not (isinstance(frets, list) and len(frets) == 6):
            continue
        if not all(isinstance(f, int) and not isinstance(f, bool) and f >= -1 for f in frets):
            continue
        low_to_high = frets[::-1]
        key = tuple(low_to_high)
        if key in seen:
            continue
        seen.add(key)
        if isinstance(fingers, list) and len(fingers) == 6 and all(isinstance(f, int) for f in fingers):
            finger_row = [max(0, f) for f in fingers[::-1]]
        else:
            finger_row = [0] * 6
        bass = name.split("/", 1)[1] if "/" in name else None
        voicing = _voicing(name, low_to_high, finger_row, bass, None, False)
        voicing["source"] = "ultimate-guitar"
        out.append(voicing)
    out.sort(key=lambda shape: (shape["base"] > 1, shape["base"]))
    return out


def variants_for_names(names: list[str] | None) -> dict[str, list[dict[str, Any]]]:
    result: dict[str, list[dict[str, Any]]] = {}
    for name in names or []:
        if name in result:
            continue
        variants = variants_for(name)
        if variants:
            result[name] = variants
    return result


def svg(shape: dict[str, Any], color: str = "currentColor") -> str:
    """Render a shape as standalone SVG (for the CLI and for docs)."""
    frets = shape["frets"]
    base = shape["base"]
    span = 5
    width, height = 92, 116
    left, top = 14, 16
    gap_x = (width - left * 2) / 5
    gap_y = (height - top * 2 - 10) / span
    parts: list[str] = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" width="{width}" height="{height}">']
    parts.append(f'<g stroke="{color}" fill="none" stroke-width="1.4">')
    for index in range(6):
        x = left + index * gap_x
        parts.append(f'<line x1="{x:.1f}" y1="{top}" x2="{x:.1f}" y2="{top + gap_y * span:.1f}"/>')
    for index in range(span + 1):
        y = top + index * gap_y
        weight = 3 if index == 0 and base == 1 else 1.4
        parts.append(f'<line x1="{left}" y1="{y:.1f}" x2="{left + gap_x * 5:.1f}" y2="{y:.1f}" stroke-width="{weight}"/>')
    parts.append("</g>")
    parts.append(f'<g fill="{color}" font-family="sans-serif" font-size="9" text-anchor="middle">')
    if base > 1:
        parts.append(f'<text x="{left - 6:.1f}" y="{top + gap_y:.1f}">{base}fr</text>')
    for index, fret in enumerate(frets):
        x = left + index * gap_x
        if fret < 0:
            parts.append(f'<text x="{x:.1f}" y="{top - 5:.1f}">x</text>')
        elif fret == 0:
            parts.append(f'<circle cx="{x:.1f}" cy="{top - 7:.1f}" r="3" fill="none" stroke="{color}" stroke-width="1.2"/>')
    parts.append("</g>")
    parts.append(f'<g fill="{color}">')
    for index, fret in enumerate(frets):
        if fret <= 0:
            continue
        row = fret - base + 1
        if row < 1:
            continue
        cx = left + index * gap_x
        cy = top + (row - 0.5) * gap_y
        parts.append(f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{gap_x * 0.28:.1f}"/>')
    parts.append("</g>")
    parts.append("</svg>")
    return "".join(parts)

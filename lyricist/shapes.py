"""Chord diagram data.

No images and no network: a chord name is turned into fret/finger positions
that the widget draws itself, so diagrams stay crisp at any DPI and follow the
Plasma colour scheme automatically.

Open-position voicings are listed explicitly because they are what people
actually play; everything else is derived from the standard movable E-shape and
A-shape barre forms, transposed to the root.
"""

from __future__ import annotations

import re
from typing import Any

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

_STRING_ROOT = {"E": 4, "A": 9}
_NOTES_SHARP = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

_CHORD_RE = re.compile(r"^([A-G][#b♯♭]?)(.*?)(?:/([A-G][#b♯♭]?))?$")

# Exact open voicings, written as fret-per-string from low E to high E.
_OPEN: dict[str, tuple[str, str]] = {
    "C": ("x32010", "x32010"),
    "Cmaj7": ("x32000", "x32000"),
    "C7": ("x32310", "x32310"),
    "C6": ("x32210", "x32210"),
    "Cadd9": ("x32030", "x32030"),
    "C9": ("x32333", "x32333"),
    "D": ("xx0232", "xx0132"),
    "Dm": ("xx0231", "xx0231"),
    "D7": ("xx0212", "xx0213"),
    "Dmaj7": ("xx0222", "xx0122"),
    "Dm7": ("xx0211", "xx0211"),
    "D6": ("xx0202", "xx0203"),
    "Dsus2": ("xx0230", "xx0230"),
    "Dsus4": ("xx0233", "xx0134"),
    "Dadd9": ("xx0230", "xx0130"),
    "E": ("022100", "023100"),
    "Em": ("022000", "023000"),
    "E7": ("020100", "023140"),
    "Emaj7": ("021100", "023140"),
    "Em7": ("020000", "023000"),
    "E6": ("022120", "023140"),
    "Esus4": ("022200", "023400"),
    "Esus2": ("024400", "024400"),
    "A": ("x02220", "x02310"),
    "Am": ("x02210", "x02310"),
    "A7": ("x02020", "x02324"),
    "Amaj7": ("x02120", "x02320"),
    "Am7": ("x02010", "x02313"),
    "A6": ("x02222", "x02344"),
    "Am6": ("x02212", "x02314"),
    "Asus2": ("x02200", "x02300"),
    "Asus4": ("x02230", "x02340"),
    "Aadd9": ("x02420", "x02430"),
    "G": ("320003", "320004"),
    "G7": ("320001", "320001"),
    "Gmaj7": ("320002", "320002"),
    "G6": ("320000", "320000"),
    "Gadd9": ("320203", "320203"),
    "B7": ("x21202", "x21314"),
    "Bm7": ("x20202", "x20203"),
    "Bm7b5": ("x2323x", "x2314x"),
    "Bb": ("x13331", "x13241"),
    "Bbmaj7": ("x13231", "x13241"),
    "Bbm7": ("x13121", "x13121"),
    "F": ("133211", "134211"),
    "Fm": ("133111", "134111"),
    "F7": ("131211", "131214"),
    "Fmaj7": ("xx3210", "xx3210"),
    "Fm7": ("131111", "131411"),
    "Cm7b5": ("x3434x", "x3424x"),
    "Ab": ("431114", "432114"),
    "Abaug": ("432110", "432110"),
    "Eb": ("x65343", "x65344"),
    "Ebmaj7": ("x65333", "x65334"),
    "Ebm7": ("x68676", "x13141"),
    "Db": ("x43121", "x43221"),
    "Dbmaj7": ("x43111", "x43221"),
    "C#m": ("x46654", "x46654"),
    "F#m": ("244222", "244222"),
    "F#m7": ("242222", "243222"),
    "Bm": ("x24432", "x24432"),
    "B": ("x24442", "x24444"),
    "Gm": ("355333", "355333"),
    "Gm7": ("353333", "353333"),
    "Cm": ("x35543", "x35543"),
    "C#m7": ("x46454", "x46454"),
    "F#": ("244322", "244322"),
}

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
    if value in _OPEN:
        return value
    return _SUFFIX_ALIASES.get(value, "")


def _expand(compact: str) -> list[int]:
    return [-1 if ch in "xX" else int(ch) for ch in compact]


def _expand_fingers(compact: str) -> list[int]:
    return [-1 if ch in "xX" else int(ch) for ch in compact]


def _transpose(compact: str, fret: int) -> list[int]:
    out: list[int] = []
    for ch in compact:
        if ch in "xX":
            out.append(-1)
        else:
            out.append(fret + int(ch))
    return out


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


def shape_for(name: str) -> dict[str, Any] | None:
    """Return fret/finger data for a chord symbol, or ``None`` if unplayable."""
    cleaned = (name or "").strip().replace("♯", "#").replace("♭", "b")
    if not cleaned:
        return None
    if cleaned.upper() in ("N.C.", "NC", "X"):
        return None
    # German charts write B natural as H (and the letter B means B flat there),
    # so Hm is Bm. Only H is rewritten: an English B is a B natural.
    if cleaned[:1] in ("H", "h"):
        cleaned = "B" + cleaned[1:]

    match = _CHORD_RE.match(cleaned)
    if not match:
        return None
    root, suffix_raw, bass = match.group(1), match.group(2) or "", match.group(3)
    if root not in NOTE_PC:
        return None

    approx = False
    suffix = canonical_suffix(suffix_raw)

    exact = f"{root}{suffix}"
    if exact in _OPEN:
        frets = _expand(_OPEN[exact][0])
        fingers = _expand_fingers(_OPEN[exact][1])
        return {
            "name": cleaned,
            "frets": frets,
            "fingers": fingers,
            "base": _base_fret(frets),
            "barre": _barre_fret(frets),
            "bass": bass,
            "approx": False,
        }

    if suffix_raw and suffix == "" and not suffix_raw.isdigit():
        approx = True

    forms = _MOVABLE.get(suffix)
    if not forms:
        forms = _MOVABLE[""]
        approx = True

    root_pc = NOTE_PC[root]
    options: list[tuple[str, int]] = []
    for string_name, root_of_string in _STRING_ROOT.items():
        fret = (root_pc - root_of_string) % 12
        if fret == 0:
            fret = 12
        options.append((string_name, fret))
    # Prefer the shape that sits lowest on the neck.
    string_name, fret = min(options, key=lambda item: item[1])

    picked = forms.get(string_name) or forms["E"]
    frets = _transpose(picked[0], fret)

    return {
        "name": cleaned,
        "frets": frets,
        "fingers": _expand_fingers(picked[1]),
        "base": _base_fret(frets),
        "barre": _barre_fret(frets),
        "bass": bass,
        "root_string": 0 if string_name == "E" else 1,
        "approx": approx,
    }


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


def variants_for(name: str) -> list[dict[str, Any]]:
    """Every sensible voicing of a chord symbol, lowest positions first.

    The open shape (when we know one) comes first, then the movable E-shape and
    A-shape placed at the fret that puts the root on that string: the barre and
    shifted alternatives a player reaches for when the open shape will not do.
    """
    cleaned = (name or "").strip().replace("♯", "#").replace("♭", "b")
    if not cleaned or cleaned.upper() in ("N.C.", "NC", "X"):
        return []
    if cleaned[:1] in ("H", "h"):
        cleaned = "B" + cleaned[1:]
    match = _CHORD_RE.match(cleaned)
    if not match:
        return []
    root, suffix_raw, bass = match.group(1), match.group(2) or "", match.group(3)
    if root not in NOTE_PC:
        return []

    suffix = canonical_suffix(suffix_raw)
    approx = bool(suffix_raw and suffix == "" and not suffix_raw.isdigit())

    out: list[dict[str, Any]] = []
    seen: set[tuple[int, ...]] = set()

    def add(frets: list[int], fingers: list[int], root_string: int | None,
            is_approx: bool) -> None:
        key = tuple(frets)
        if key in seen:
            return
        seen.add(key)
        out.append(_voicing(cleaned, frets, fingers, bass, root_string, is_approx))

    exact = f"{root}{suffix}"
    if exact in _OPEN:
        add(_expand(_OPEN[exact][0]), _expand_fingers(_OPEN[exact][1]), None, False)

    forms = _MOVABLE.get(suffix) or _MOVABLE[""]
    root_pc = NOTE_PC[root]
    for string_name, root_of_string in _STRING_ROOT.items():
        fret = (root_pc - root_of_string) % 12
        if fret == 0:
            fret = 12
        picked = forms.get(string_name)
        if not picked:
            continue
        add(_transpose(picked[0], fret), _expand_fingers(picked[1]),
            0 if string_name == "E" else 1, approx)

    # Open shapes first, then the movable ones climbing the neck.
    out.sort(key=lambda shape: (shape["base"] > 1, shape["base"]))
    return out


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

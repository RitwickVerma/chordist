"""Parsing chord charts.

Three input dialects are understood and normalised into one shape, so the
widget never has to care where a chart came from:

* **Ultimate Guitar** - ``[ch]Am[/ch]`` inline markup, ``[tab]...[/tab]``
  blocks that hold a space-aligned chord row above its lyric row, and
  ``[Verse 1]`` style headers.
* **ChordPro** - ``[Am]`` inline brackets plus ``{title:}``/``{comment:}``/
  ``{soc}`` style directives. This is the recommended format for the user's
  own files because it is plain text and pleasant to write by hand.
* **Plain text** - a line of chords followed by the lyric line it belongs to,
  which is how most people type a song out.

The normalised form is::

    {
      "title": str, "artist": str, "key": str, "capo": int, "source": str,
      "sections": [
        {"name": "Verse 1", "lines": [
            {"lyric": "When you were here before",
             "chords": [{"pos": 0, "name": "G"}],
             "mono": False}
        ]}
      ]
    }

``pos`` is a character offset into that line's ``lyric``, so the renderer can
place chord names exactly above the syllable they belong to.
"""

from __future__ import annotations

import html
import re
from typing import Any

CH_OPEN = "[ch]"
CH_CLOSE = "[/ch]"
TAB_TOKENS = ("[tab]", "[/tab]")

# A chord is a root note plus a pile of optional decoration. Deliberately
# permissive (charts are hand-typed) but strict enough that ordinary words do
# not match, which matters when guessing whether a line is a chord row.
_CHORD_RE = re.compile(
    r"^(?:N\.?C\.?|x"
    r"|[A-G][#b♯♭]?(?:maj|min|dim|aug|sus|add|alt|omit|no|m|M"
    r"|[0-9]|\(|\)|/|[A-G]|\+|-|#|b|°|ø|Δ|♯|♭)*)$"
)

_HEADER_RE = re.compile(r"^\[([^\[\]]{1,40})\]$")
_DIRECTIVE_RE = re.compile(r"^\{\s*([a-z_]+)\s*(?::\s*(.*?))?\s*\}$", re.I)
_SECTION_WORDS = {
    "soc": "Chorus",
    "eoc": None,
    "sov": "Verse",
    "eov": None,
    "sob": "Bridge",
    "eob": None,
    "start_of_chorus": "Chorus",
    "end_of_chorus": None,
    "start_of_verse": "Verse",
    "end_of_verse": None,
    "start_of_bridge": "Bridge",
    "end_of_bridge": None,
    "start_of_tab": "Tab",
    "end_of_tab": None,
}

_ACCIDENTAL = {"♯": "#", "♭": "b", "∆": "maj7", "Δ": "maj7", "ø": "m7b5"}


def normalize_chord(name: str) -> str:
    """Tidy a chord symbol without changing what it means."""
    value = (name or "").strip()
    if not value:
        return ""
    for source, target in _ACCIDENTAL.items():
        value = value.replace(source, target)
    value = value.replace("–", "-").replace("—", "-")
    value = re.sub(r"\s+", " ", value)
    # "H" is the German B natural; only rewrite the bare root.
    if re.fullmatch(r"H[#b]?", value):
        value = "B" + value[1:]
    return value


def is_chord(token: str) -> bool:
    return bool(_CHORD_RE.match(normalize_chord(token)))


def _new_section(name: str = "") -> dict[str, Any]:
    return {"name": name, "lines": []}


def scan_chords(line: str) -> tuple[str, str, list[dict[str, Any]], list[dict[str, Any]]]:
    """Split a line into tag-stripped text plus chord positions.

    Returns ``(kept, dropped, marks_kept, marks_dropped)`` where ``kept`` still
    contains the chord names, ``dropped`` has them removed, and the two mark
    lists give each chord's offset into the corresponding string.
    """
    kept: list[str] = []
    kept_len = 0
    dropped: list[str] = []
    dropped_len = 0
    marks_kept: list[dict[str, Any]] = []
    marks_dropped: list[dict[str, Any]] = []

    index = 0
    while True:
        start = line.find(CH_OPEN, index)
        if start < 0:
            tail = line[index:]
            kept.append(tail)
            dropped.append(tail)
            break

        head = line[index:start]
        kept.append(head)
        dropped.append(head)
        kept_len += len(head)
        dropped_len += len(head)

        end = line.find(CH_CLOSE, start)
        if end < 0:
            tail = line[start + len(CH_OPEN):]
            kept.append(tail)
            dropped.append(tail)
            break

        name = normalize_chord(line[start + len(CH_OPEN):end])
        if name:
            marks_kept.append({"pos": kept_len, "name": name})
            marks_dropped.append({"pos": dropped_len, "name": name})
            kept.append(name)
            kept_len += len(name)
        index = end + len(CH_CLOSE)

    return "".join(kept), "".join(dropped), marks_kept, marks_dropped


def scan_brackets(line: str) -> tuple[str, list[dict[str, Any]]]:
    """ChordPro style: ``[Am]lyric`` -> (lyric, marks)."""
    out: list[str] = []
    marks: list[dict[str, Any]] = []
    length = 0
    for part in re.split(r"(\[[^\[\]]*\])", line):
        if not part:
            continue
        if part.startswith("[") and part.endswith("]"):
            name = normalize_chord(part[1:-1])
            if is_chord(name):
                marks.append({"pos": length, "name": name})
                continue
        out.append(part)
        length += len(part)
    return "".join(out), marks


def _line_obj(lyric: str, chords: list[dict[str, Any]], mono: bool = False) -> dict[str, Any]:
    return {
        "lyric": lyric.rstrip(),
        "chords": chords,
        "mono": mono,
        # A chord row with no lyric under it (an intro riff, a turnaround) has
        # nothing for "pos" to point at, so the renderer spaces it evenly.
        "instrumental": bool(chords) and not lyric.strip(),
    }


# One string of a tablature staff: a string label, a bar line or colon, then
# fret numbers, techniques (h p b r / \\ ~ ^ x) and runs of dashes.
_STAFF_ROW_RE = re.compile(r"^\s*([A-Ga-g][#b]?)\s*([|:])(.*)$")
_STAFF_BODY_RE = re.compile(r"^[-0-9a-zA-Z/\\~^()<>.*|+=:\s]*$")
_STAFF_SIZES = (6, 4, 7, 8, 5)


def staff_row(line: str) -> tuple[str, str] | None:
    """``("G", "|--7--|")`` for a tablature row, or ``None`` for anything else."""
    match = _STAFF_ROW_RE.match(line)
    if not match:
        return None
    body = match.group(2) + match.group(3).rstrip()
    rest = match.group(3)
    if "--" not in rest or not _STAFF_BODY_RE.match(rest):
        return None
    ruled = sum(1 for ch in rest if ch in "-|0123456789")
    if ruled < 0.6 * max(1, len(rest.strip())):
        return None
    return match.group(1), body


def _staff_line(labels: list[str], rows: list[str]) -> dict[str, Any]:
    width = max(len(row) for row in rows)
    rows = [row.ljust(width, "-") for row in rows]
    line = _line_obj("\n".join(f"{label}{row}" for label, row in zip(labels, rows, strict=True)), [], mono=True)
    line["staff"] = {"labels": labels, "rows": rows}
    return line


def group_staves(lines: list[str], strings: int = 6) -> list[dict[str, Any] | str]:
    """Split raw text lines into staff line-objects and plain text lines.

    Tablature rows are collected in runs (a stray blank line inside a staff, as
    Ultimate Guitar tabs often have, does not end it) and cut into staves of
    ``strings`` rows - or of 4, 7 or 8 when that is what divides the run. A run
    that does not make sense as a staff is handed back as plain text.
    """
    out: list[dict[str, Any] | str] = []
    run: list[tuple[str, str]] = []

    def flush() -> None:
        nonlocal run
        if not run:
            return
        size = next((n for n in (strings, *_STAFF_SIZES) if len(run) % n == 0), 0)
        if size:
            for start in range(0, len(run), size):
                chunk = run[start:start + size]
                out.append(_staff_line([label for label, _ in chunk], [row for _, row in chunk]))
        else:
            out.extend(f"{label}{row}" for label, row in run)
        run = []

    index = 0
    while index < len(lines):
        line = lines[index]
        row = staff_row(line)
        if row:
            run.append(row)
        elif not line.strip() and run:
            # A blank line only belongs to the staff if more of it follows.
            following = next((candidate for candidate in lines[index + 1:] if candidate.strip()), "")
            if not staff_row(following):
                flush()
                out.append(line)
        else:
            flush()
            out.append(line)
        index += 1
    flush()
    return out


def _split_tab_block(block: str) -> tuple[list[dict[str, Any]], bool]:
    """Turn a ``[tab]`` block into lines.

    Returns ``(lines, is_tablature)``. A block where no chord markup appears at
    all is real tablature (fret numbers), which we keep as monospace text.
    """
    raw_lines = block.split("\n")
    if not any(CH_OPEN in line for line in raw_lines):
        staves: list[dict[str, Any]] = []
        for item in group_staves(raw_lines):
            if isinstance(item, dict):
                staves.append(item)
            elif item.strip():
                staves.append(_line_obj(item.rstrip(), [], mono=True))
        return staves, True

    lines: list[dict[str, Any]] = []
    index = 0
    while index < len(raw_lines):
        _kept, dropped, marks_kept, marks_dropped = scan_chords(raw_lines[index])

        if not dropped.strip():
            # A chord-position row: its columns line up with the row below.
            lyric = ""
            if index + 1 < len(raw_lines):
                _below, below_dropped, below_marks, _ = scan_chords(raw_lines[index + 1])
                if below_dropped.strip() and not below_marks:
                    lyric = below_dropped
                    index += 1
            lines.append(_line_obj(lyric, marks_kept))
        elif marks_dropped:
            lines.append(_line_obj(dropped, marks_dropped))
        elif dropped.strip():
            lines.append(_line_obj(dropped, []))
        index += 1
    return [line for line in lines if line["lyric"].strip() or line["chords"]], False


def _split_chunks(text: str) -> list[tuple[str, str]]:
    """Split raw text into ('raw'|'tab', content) chunks."""
    chunks: list[tuple[str, str]] = []
    in_tab = False
    for part in re.split(r"(\[tab\]|\[/tab\])", text):
        if part == "[tab]":
            in_tab = True
            chunks.append(("tab", ""))
            continue
        if part == "[/tab]":
            in_tab = False
            continue
        if not part:
            continue
        if in_tab and chunks and chunks[-1][0] == "tab":
            chunks[-1] = ("tab", chunks[-1][1] + part)
        else:
            chunks.append(("raw", part))
    return chunks


def _header_name(line: str) -> str | None:
    stripped = line.strip()
    if not stripped:
        return None
    match = _HEADER_RE.match(stripped)
    if match:
        token = match.group(1).strip()
        if token.lower() in ("ch", "/ch", "tab", "/tab") or is_chord(token):
            return None
        return token.rstrip(":")
    # "[Chorus] (play loud)" - a named section with a short note after it.
    match = re.match(r"^\[([^\[\]]{1,40})\]\s*(\([^)]*\))?$", stripped)
    if match:
        token = match.group(1).strip()
        if token.lower() in ("ch", "/ch", "tab", "/tab") or is_chord(token):
            return None
        note = (match.group(2) or "").strip()
        return f"{token.rstrip(':')} {note}".strip()
    match = re.fullmatch(r"(verse|chorus|bridge|intro|outro|pre[- ]?chorus|solo|interlude|instrumental|refrain|tag|ending|breakdown|coda)\s*\d*\s*:?", stripped, re.I)
    if match:
        return stripped.rstrip(":")
    return None


def _parse_ug(text: str, title: str, artist: str) -> dict[str, Any]:
    sections: list[dict[str, Any]] = []
    current = _new_section()

    def flush() -> None:
        nonlocal current
        if current["lines"]:
            sections.append(current)
        current = _new_section()

    for kind, chunk in _split_chunks(text):
        if kind == "tab":
            tab_lines, is_tab = _split_tab_block(chunk)
            if not tab_lines:
                continue
            if is_tab:
                # Preamble text ("Tabbed by ...") is its own section; the staves
                # that follow share one, rather than one section per [tab] block.
                if current["lines"] and not current["name"] and not any("staff" in ln for ln in current["lines"]):
                    flush()
                if not current["name"]:
                    current["name"] = "Tab"
            current["lines"].extend(tab_lines)
            continue

        for item in group_staves(chunk.split("\n")):
            if isinstance(item, dict):
                if not current["name"] and not current["lines"]:
                    current["name"] = "Tab"
                current["lines"].append(item)
                continue
            line = item
            header = _header_name(line)
            if header:
                flush()
                current["name"] = header
                continue

            _kept, dropped, marks_kept, marks_dropped = scan_chords(line)
            if not dropped.strip():
                if marks_kept:
                    current["lines"].append(
                        _line_obj("", [{"pos": index, "name": mark["name"]} for index, mark in enumerate(marks_kept)])
                    )
                continue
            if marks_dropped:
                current["lines"].append(_line_obj(dropped, marks_dropped))
            else:
                current["lines"].append(_line_obj(dropped, []))

    flush()
    return {"sections": sections, "title": title, "artist": artist, "key": "", "capo": 0, "source": "ultimate-guitar"}


def _parse_chordpro(text: str, title: str, artist: str) -> dict[str, Any]:
    sections: list[dict[str, Any]] = []
    current = _new_section()
    meta = {"title": title, "artist": artist, "key": "", "capo": 0}

    def flush() -> None:
        nonlocal current
        if current["lines"]:
            sections.append(current)
        current = _new_section()

    in_tab = False
    tab_rows: list[str] = []

    def flush_tab() -> None:
        nonlocal tab_rows
        for item in group_staves(tab_rows):
            if isinstance(item, dict):
                current["lines"].append(item)
            elif item.strip():
                current["lines"].append(_line_obj(item.rstrip(), [], mono=True))
        tab_rows = []

    for line in text.split("\n"):
        directive = _DIRECTIVE_RE.match(line.strip())
        if in_tab and not (directive and directive.group(1).lower() in ("eot", "end_of_tab")):
            tab_rows.append(line)
            continue
        if directive:
            name = directive.group(1).lower()
            if name in ("sot", "start_of_tab"):
                if not current["name"]:
                    current["name"] = directive.group(2) or "Tab"
                in_tab = True
                continue
            if name in ("eot", "end_of_tab"):
                flush_tab()
                in_tab = False
                continue
            value = (directive.group(2) or "").strip()
            if name in ("title", "t"):
                meta["title"] = value or meta["title"]
            elif name in ("artist", "subtitle", "st", "a"):
                meta["artist"] = value or meta["artist"]
            elif name in ("key", "k"):
                meta["key"] = value
            elif name in ("capo",):
                try:
                    meta["capo"] = int(re.sub(r"[^0-9-]", "", value) or 0)
                except ValueError:
                    meta["capo"] = 0
            elif name in ("comment", "c", "comment_italic", "ci"):
                flush()
                current["name"] = value or "Comment"
            elif name in _SECTION_WORDS:
                flush()
                label = _SECTION_WORDS[name]
                if label is not None:
                    current["name"] = value or label
            continue

        if not line.strip():
            continue
        header = _header_name(line)
        if header:
            flush()
            current["name"] = header
            continue

        kept, dropped, _marks_kept, marks_dropped = scan_chords(line)
        if marks_dropped:
            current["lines"].append(_line_obj(dropped, marks_dropped))
            continue
        lyric, marks = scan_brackets(kept)
        if marks:
            current["lines"].append(_line_obj(lyric, marks))
        else:
            current["lines"].append(_line_obj(lyric, []))

    if in_tab:
        flush_tab()
    flush()
    return {"sections": sections, **meta, "source": "local"}


def _parse_plain(text: str, title: str, artist: str) -> dict[str, Any]:
    sections: list[dict[str, Any]] = []
    current = _new_section()
    pending: list[dict[str, Any]] | None = None

    def flush() -> None:
        nonlocal current, pending
        if pending:
            current["lines"].append(_line_obj("", pending))
            pending = None
        if current["lines"]:
            sections.append(current)
        current = _new_section()

    for line in text.split("\n"):
        if not line.strip():
            if pending:
                current["lines"].append(_line_obj("", pending))
                pending = None
            continue
        header = _header_name(line)
        if header:
            flush()
            current["name"] = header
            continue

        kept, dropped, _marks_kept, _marks_dropped = scan_chords(line)
        lyric, marks = scan_brackets(kept)
        if marks:
            current["lines"].append(_line_obj(lyric, marks))
            continue

        tokens = [t for t in re.split(r"[\s|]+", dropped.strip()) if t]
        if tokens and all(is_chord(t) for t in tokens) and len(tokens) <= 12:
            if pending:
                current["lines"].append(_line_obj("", pending))
            pending = _chord_line_marks(dropped)
            continue

        current["lines"].append(_line_obj(lyric, pending or []))
        pending = None

    flush()
    return {"sections": sections, "title": title, "artist": artist, "key": "", "capo": 0, "source": "plain"}


def _chord_line_marks(line: str) -> list[dict[str, Any]]:
    marks: list[dict[str, Any]] = []
    for match in re.finditer(r"[^\s|]+", line):
        token = match.group(0)
        if is_chord(token):
            marks.append({"pos": match.start(), "name": normalize_chord(token)})
    return marks


def detect_format(text: str) -> str:
    if CH_OPEN in text:
        return "ug"
    if any(line.strip().startswith("{") for line in text.splitlines()):
        return "chordpro"
    if re.search(r"\[[A-G][#b]?[m0-9a-z/()+-]*\]", text):
        return "chordpro"
    return "plain"


def parse(text: str, fmt: str = "auto", title: str = "", artist: str = "") -> dict[str, Any]:
    """Parse chart text into the normalised structure."""
    if not text or not text.strip():
        return {
            "sections": [], "title": title, "artist": artist, "key": "", "capo": 0,
            "source": "none", "kind": "chords", "chord_names": [],
        }

    text = html.unescape(text).replace("\r\n", "\n").replace("\r", "\n").replace("\t", "    ")
    chosen = detect_format(text) if fmt in ("auto", "", None) else fmt
    parser = {"ug": _parse_ug, "chordpro": _parse_chordpro, "plain": _parse_plain}.get(chosen, _parse_plain)
    result = parser(text, title, artist)
    result["format"] = chosen
    all_lines = [line for section in result["sections"] for line in section["lines"]]
    result["chord_names"] = sorted({c["name"] for line in all_lines for c in line["chords"]})
    # What the chart is made of, so the widget knows whether to offer chord
    # diagrams (chords), a tab reader (tab) or both (mixed).
    has_chords = any(line["chords"] for line in all_lines)
    has_staff = any("staff" in line for line in all_lines)
    result["kind"] = "mixed" if has_chords and has_staff else ("tab" if has_staff else "chords")
    return result


def to_chordpro(result: dict[str, Any]) -> str:
    """Render the normalised structure back out as ChordPro text.

    Used when the user pastes an Ultimate Guitar chart and we want to keep a
    tidy local copy they can edit later.
    """
    out: list[str] = []
    if result.get("title"):
        out.append(f"{{title: {result['title']}}}")
    if result.get("artist"):
        out.append(f"{{artist: {result['artist']}}}")
    if result.get("key"):
        out.append(f"{{key: {result['key']}}}")
    if result.get("capo"):
        out.append(f"{{capo: {result['capo']}}}")
    if out:
        out.append("")

    for section in result.get("sections", []):
        if section.get("name"):
            out.append(f"{{comment: {section['name']}}}")
        for line in section.get("lines", []):
            lyric = line.get("lyric", "")
            if line.get("staff"):
                out.append("{start_of_tab}")
                out.extend(lyric.split("\n"))
                out.append("{end_of_tab}")
                continue
            if not line.get("chords"):
                out.append(lyric)
                continue
            pieces: list[str] = []
            cursor = 0
            for chord in sorted(line["chords"], key=lambda c: c["pos"]):
                pos = max(0, min(int(chord["pos"]), len(lyric)))
                if pos > cursor:
                    pieces.append(lyric[cursor:pos])
                    cursor = pos
                pieces.append(f"[{chord['name']}]")
            pieces.append(lyric[cursor:])
            out.append("".join(pieces).rstrip())
        out.append("")
    return "\n".join(out).rstrip() + "\n"

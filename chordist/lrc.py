# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
#
# SPDX-License-Identifier: MIT

"""LRC parsing, including the enhanced (word-level) variant.

LRCLIB returns either plain lyrics, ordinary synced LRC::

    [00:12.34]and the coloured lights

or enhanced LRC where every word carries its own timestamp, which is what lets
the widget do real karaoke-style highlighting::

    [00:12.34]<00:12.34>and <00:12.51>the <00:12.70>coloured <00:13.02>lights
"""

from __future__ import annotations

import contextlib
import re
from typing import Any

_LINE_TS = re.compile(r"\[(\d{1,3}):(\d{1,2}(?:[.:]\d{1,3})?)\]")
_WORD_TS = re.compile(r"<(\d{1,3}):(\d{1,2}(?:[.:]\d{1,3})?)>")
_META = re.compile(r"^\[(ar|ti|al|by|offset|re|ve|length|au|ku|language)\s*:(.*)\]$", re.I)
_WS = re.compile(r"\s+")


def _seconds(minutes: str, rest: str) -> float:
    return int(minutes) * 60.0 + float(rest.replace(":", "."))


def _words(body: str, offset: float) -> list[dict[str, Any]]:
    """Split an enhanced-LRC line into individually timed words."""
    matches = list(_WORD_TS.finditer(body))
    if not matches:
        return []

    words: list[dict[str, Any]] = []
    for index, match in enumerate(matches):
        start = match.end()
        end = matches[index + 1].start() if index + 1 < len(matches) else len(body)
        text = _WS.sub(" ", body[start:end]).strip()
        words.append({"t": max(0.0, _seconds(match.group(1), match.group(2)) + offset), "text": text})
    return words


def parse(text: str, offset_ms: float = 0.0) -> list[dict[str, Any]]:
    """Parse LRC text into ``[{"t": seconds, "text": ..., "words": [...]}]``."""
    if not text:
        return []

    offset = -offset_ms / 1000.0
    lines: list[dict[str, Any]] = []

    for raw in text.splitlines():
        stripped = raw.strip()
        meta = _META.match(stripped)
        if meta:
            if meta.group(1).lower() == "offset":
                with contextlib.suppress(ValueError):
                    offset = -float(meta.group(2).strip()) / 1000.0
            continue

        stamps = _LINE_TS.findall(stripped)
        if not stamps:
            continue

        body = _LINE_TS.sub("", stripped)
        words = _words(body, offset)
        plain = _WS.sub(" ", _WORD_TS.sub("", body)).strip()

        for minutes, rest in stamps:
            lines.append(
                {
                    "t": max(0.0, _seconds(minutes, rest) + offset),
                    "text": plain,
                    "words": words,
                }
            )

    lines.sort(key=lambda item: item["t"])
    return lines


def to_plain(lines: list[dict[str, Any]]) -> str:
    """Flatten parsed lines back into readable plain lyrics."""
    return "\n".join(line["text"] for line in lines if line.get("text"))


def as_plain_lines(text: str) -> list[dict[str, Any]]:
    """Wrap unsynced lyrics so the UI can treat both shapes identically."""
    out: list[dict[str, Any]] = []
    for raw in (text or "").splitlines():
        out.append({"t": None, "text": raw.rstrip(), "words": []})
    return out

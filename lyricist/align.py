# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
#
# SPDX-License-Identifier: MIT

"""Align a chord chart's lyric rows with the timed lyrics of the recording.

A chart and a recording rarely agree line for line: the chart breaks one sung
line across two rows or joins two into one, repeats a chorus a different number
of times, and writes instrumental bars as rows of their own.  Matching each row
on its own therefore goes wrong the moment one row is ambiguous -- the widget's
greedy scan once anchored the one-word row "haan" to any line containing a
similar word and dragged every later row with it.

Sequence alignment is the standard answer.  This module runs Needleman-Wunsch
over (chart row x timed lyric line) using the word-overlap score as the
substitution, so it finds the single best *monotonic* pairing and a weak row
cannot hijack the path.  Gaps are free, which is what lets repeated and
split/joined lines line up.  (See ISMIR 2005, "Multiple Lyrics Alignment:
Automatic Retrieval of Song Lyrics".)
"""

from __future__ import annotations

from typing import Any

from . import titles

# Below this the two lines do not look like the same words at all; leaving them
# unmatched (a free gap) is better than pairing them.
MIN_SIMILARITY = 0.5


def _edit_distance(a: str, b: str) -> int:
    if abs(len(a) - len(b)) > 1:
        return 2
    previous = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        current = [i]
        for j, cb in enumerate(b, 1):
            current.append(min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (ca != cb)))
        previous = current
    return previous[-1]


def _token_match(a: str, b: str) -> bool:
    if a == b:
        return True
    if len(a) >= 3 and len(b) >= 3 and (a.startswith(b) or b.startswith(a)):
        return True
    return _edit_distance(a, b) <= 1


def similarity(row: str, line: str) -> float:
    """How much a chart row and a lyric line look like the same words, 0..1."""
    row_words = titles.tokens(row)
    line_words = titles.tokens(line)
    if not row_words or not line_words:
        return 0.0
    # A one-word row ("haan", instrumental "x4") matches half the song, so it
    # may never anchor a line on its own.
    if len(row_words) < 2:
        return 0.0
    joined_row = " ".join(row_words)
    joined_line = " ".join(line_words)
    if joined_row in joined_line or joined_line in joined_row:
        return 1.0
    hits = 0
    for word in row_words:
        if len(word) < 2:
            continue
        if any(_token_match(word, other) for other in line_words):
            hits += 1
    if hits < 2:
        return 0.0
    return hits / min(len(row_words), len(line_words))


def align(rows: list[str], lines: list[str]) -> list[int | None]:
    """Pair chart rows with lyric lines, monotonically, for best total agreement.

    Returns, for each row, the index of the line it matched, or None.
    """
    n, m = len(rows), len(lines)
    substitution = [[0.0] * m for _ in range(n)]
    for i in range(n):
        for j in range(m):
            score = similarity(rows[i], lines[j])
            substitution[i][j] = score - MIN_SIMILARITY if score >= MIN_SIMILARITY else 0.0

    value = [[0.0] * (m + 1) for _ in range(n + 1)]
    # 1 = diagonal (a real pair), 2 = skip a row, 3 = skip a line
    step = [[0] * (m + 1) for _ in range(n + 1)]
    for i in range(1, n + 1):
        for j in range(1, m + 1):
            pair = value[i - 1][j - 1] + substitution[i - 1][j - 1]
            skip_row = value[i - 1][j]
            skip_line = value[i][j - 1]
            if substitution[i - 1][j - 1] > 0 and pair >= skip_row and pair >= skip_line:
                value[i][j] = pair
                step[i][j] = 1
            elif skip_row >= skip_line:
                value[i][j] = skip_row
                step[i][j] = 2
            else:
                value[i][j] = skip_line
                step[i][j] = 3

    match: list[int | None] = [None] * n
    i, j = n, m
    while i > 0 and j > 0:
        direction = step[i][j]
        if direction == 1:
            match[i - 1] = j - 1
            i -= 1
            j -= 1
        elif direction == 2:
            i -= 1
        else:
            j -= 1
    return match


def row_times(chart: dict[str, Any], lyrics: dict[str, Any] | None, duration: float = 0.0) -> list[float] | None:
    """One time per chart lyric row (in order), interpolating the unmatched ones.

    Returns None when there is nothing to align -- no chart rows, or no timed
    lyrics -- so the caller can leave the widget's own estimate in place.
    """
    rows = [
        line.get("lyric", "")
        for section in (chart.get("sections") or [])
        for line in (section.get("lines") or [])
    ]
    timed = [
        (float(line["t"]), line.get("text", ""))
        for line in ((lyrics or {}).get("lines") or [])
        if line.get("t") is not None
    ]
    if not rows or not timed:
        return None

    match = align(rows, [text for _t, text in timed])
    times: list[float | None] = [None] * len(rows)
    for index, line_index in enumerate(match):
        if line_index is not None:
            times[index] = timed[line_index][0]

    known = [index for index, value in enumerate(times) if value is not None]
    if not known:
        return None

    first, last = known[0], known[-1]
    previous = first
    for index in known[1:]:
        span = index - previous
        for offset in range(1, span):
            times[previous + offset] = times[previous] + (times[index] - times[previous]) * offset / span
        previous = index

    end = max(float(duration or 0.0), float(times[last] or 0.0))
    for index in range(first):
        times[index] = float(times[first] or 0.0) * (index + 1) / (first + 1)
    tail = len(rows) - 1 - last
    for index in range(last + 1, len(rows)):
        times[index] = float(times[last] or 0.0) + (end - float(times[last] or 0.0)) * (index - last) / (tail + 1)
    return times

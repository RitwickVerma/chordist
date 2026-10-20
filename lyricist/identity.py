# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
#
# SPDX-License-Identifier: MIT
"""One canonical identity for whatever is playing.

The metadata Chordist receives is written for people watching a video, not for
a database: the artist field holds the YouTube channel and the title carries an
unread badge, a role word, the film name and the singers. Every provider used
to unravel that for itself, which is why fixing one song left the next one
broken -- the same guessing happened again, in a different module.

This module resolves the raw pair once, and both the lyrics and the chords then
run on the answer, so they cannot disagree about which song is playing. A
candidate is only accepted when the lyrics database agrees on the recording
length, which is what refuses a same-named song from a different release. When
nothing verifies, the audio itself is identified instead (Shazam via SongRec).
"""

from __future__ import annotations

import logging
from typing import Any

from . import fingerprint, titles
from .cache import DiskCache, key_for
from .config import Config

log = logging.getLogger(__name__)

# Bump when the resolution changes so stale answers are not reused.
RESOLVER_VERSION = 4

# The databases round to the second and videos are trimmed, so allow a small
# window; a genuinely different release is usually minutes apart.
_TOLERANCE_SECONDS = 4.0
_TOLERANCE_RATIO = 0.03


def _duration_agrees(reported: Any, duration: float) -> bool:
    """Does the database's recording length match the video we are playing?"""
    try:
        reported = float(reported)
        duration = float(duration)
    except (TypeError, ValueError):
        return True
    if reported <= 0 or duration <= 0:
        # Nothing to compare against; the name match has to stand on its own.
        return True
    return abs(reported - duration) <= max(_TOLERANCE_SECONDS, duration * _TOLERANCE_RATIO)


def _name_agrees(candidate: str, track: Any) -> bool:
    """Does the matched entry's own name look like the song we asked for?

    Duration alone is not enough.  A junk upload named "YOUTUBE" was adopted as
    the identity of "Raabta" merely because its length happened to match, and
    the chords then had nothing real to search for.  The entry has to share a
    meaningful word with the title before it counts.
    """
    return titles.shares_word(candidate, str(track or ""))


def candidates(artist: str, title: str) -> list[tuple[str, str]]:
    """``(artist, song)`` pairs to try, most trustworthy first."""
    pairs: list[tuple[str, str]] = []

    def add(pair_artist: str, pair_title: str) -> None:
        pair = ((pair_artist or "").strip(), (pair_title or "").strip())
        if pair[1] and pair not in pairs:
            pairs.append(pair)

    songs = titles.song_candidates(title) or [title]
    hints = titles.artist_hints(title, artist)

    # The raw pair first: the lyrics provider strips decoration itself, so a
    # clean title resolves on the first try and nothing else is queried.
    add(artist, title)
    # Then drop the channel, because a search by song alone is what finds a
    # track whose artist field was never an artist.
    add("", title)
    # Then an artist named inside the title with the leading song segment, and
    # finally the song segments on their own.
    for hint in hints[:1]:
        for song in songs[:2]:
            add(hint, song)
    for song in songs[:2]:
        add("", song)
    return pairs


def resolve(
    config: Config,
    lyrics: Any,
    artist: str,
    title: str,
    duration: float = 0.0,
    album: str = "",
) -> dict[str, Any] | None:
    """The canonical artist/title/album for what is playing, or ``None``."""
    if not title:
        return None

    ttl = int(config.get("identity_ttl_seconds", 30 * 24 * 3600) or 0)
    cache = DiskCache("identity", ttl=ttl)
    key = key_for("identity", RESOLVER_VERSION, artist, title)
    hit = cache.get(key)
    if isinstance(hit, dict) and "identity" in hit:
        return hit.get("identity") or None

    resolved: dict[str, Any] | None = None
    for pair_artist, pair_title in candidates(artist, title):
        try:
            result = lyrics.lookup(pair_artist, pair_title, album, duration)
        except Exception:  # a provider hiccup must not stop the search
            continue
        if not result or result.get("source") == "none":
            continue
        if not result.get("lines") and not result.get("instrumental"):
            continue
        if not _duration_agrees(result.get("duration"), duration):
            continue
        if not _name_agrees(pair_title, result.get("track")):
            continue
        resolved = {
            "artist": result.get("artist") or pair_artist,
            "title": result.get("track") or pair_title,
            "album": result.get("album") or "",
            "duration": result.get("duration"),
            "source": result.get("source") or "lookup",
            "confidence": "duration",
        }
        break

    from_fingerprint = False
    if resolved is None and config.get("fingerprint_enabled", True):
        found = fingerprint.identify(config, artist, title)
        if found and found.get("title") and _name_agrees(title, found.get("title")):
            resolved = {
                "artist": found.get("artist") or "",
                "title": found["title"],
                "album": found.get("album") or "",
                "duration": None,
                "source": found.get("source") or "fingerprint",
                "confidence": "fingerprint",
            }
            from_fingerprint = True

    if resolved:
        log.info(
            "identity: %s - %s (from %r/%r via %s)",
            resolved.get("artist"),
            resolved.get("title"),
            artist,
            title,
            resolved.get("confidence"),
        )
    # A fingerprint answer describes whatever audio was playing when the capture
    # was taken -- not necessarily the track being asked about, and Shazam can be
    # wrong -- so it is remembered only briefly instead of for the whole TTL.
    cache.set(
        key,
        {"identity": resolved},
        ttl=(ttl if resolved and not from_fingerprint else 300),
    )
    return resolved

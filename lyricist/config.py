# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
#
# SPDX-License-Identifier: MIT

"""Configuration for the Lyricist service.

Loads ``~/.config/lyricist/config.json`` (or ``$XDG_CONFIG_HOME``), falling
back to built-in defaults for anything missing. Writing is always done by
merging over the file that is already on disk so unrelated keys survive.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

APP = "lyricist"

DEFAULTS: dict[str, Any] = {
    # Local HTTP API the Plasma widget talks to.
    "host": "127.0.0.1",
    "port": 8788,
    # Sent to LRCLIB so they can contact you if your client misbehaves.
    # LRCLIB explicitly asks for a real contact address.
    "contact": "",
    # Chord providers, tried in order. "local" and "cache" are always first.
    "chords_sources": ["local", "cache", "ultimate-guitar"],
    "ug_enabled": True,
    # Seconds between requests to the same host. Ultimate Guitar starts
    # returning 502 if you push it, so this is deliberately unhurried.
    "min_request_interval": 1.6,
    # How long a "no chords found" answer is remembered before we look again.
    # Short enough that a newly uploaded tab gets picked up soon.
    "negative_ttl_seconds": 3 * 24 * 3600,
    # Lyrics rarely change; cache essentially forever.
    "lyrics_ttl_seconds": 365 * 24 * 3600,
    "chords_ttl_seconds": 365 * 24 * 3600,
    "request_timeout": 20,
    # Lyrics script. "auto" romanises lyrics that are in a non-Latin script
    # (Devanagari) so they are readable, whether or not the song has a chord
    # chart; the lyrics are left alone when they are already Latin, or when the
    # chart itself is in the song's own script (both halves then read alike).
    # "always" romanises whenever the lyrics are not Latin; "never" leaves the
    # lyrics in their original script.
    "romanise": "auto",
    # Identify the track from its own audio when the browser metadata is junk
    # (channel-as-artist, decorated video titles).  Uses SongRec, an
    # open-source Shazam client; no API key needed.
    "fingerprint_enabled": True,
    "fingerprint_seconds": 6,
    "fingerprint_timeout": 60,
    # A confirmed identity is valid for a month; a miss retries after 5 min.
    "fingerprint_ttl_seconds": 30 * 24 * 3600,
    # Override the SongRec binary if it is not on PATH.
    "songrec_path": "",
    "log_level": "info",
}


def config_home() -> Path:
    base = os.environ.get("XDG_CONFIG_HOME")
    return Path(base) / APP if base else Path.home() / ".config" / APP


def data_home() -> Path:
    base = os.environ.get("XDG_DATA_HOME")
    return Path(base) / APP if base else Path.home() / ".local" / "share" / APP


def cache_home() -> Path:
    base = os.environ.get("XDG_CACHE_HOME")
    return Path(base) / APP if base else Path.home() / ".cache" / APP


def config_path() -> Path:
    return config_home() / "config.json"


def chords_dir() -> Path:
    """Where the user's own ChordPro files live - always the first source."""
    return data_home() / "chords"


def user_agent(contact: str = "") -> str:
    from . import __version__

    agent = f"chordist-lyricist/{__version__} (KDE Plasma widget)"
    if contact:
        agent += f" (contact: {contact})"
    return agent


class Config:
    """A dict-like configuration with dotted-free, plain key access."""

    def __init__(self, values: dict[str, Any] | None = None) -> None:
        self._values = dict(DEFAULTS)
        if values:
            self._values.update({k: v for k, v in values.items() if v is not None})

    def __getitem__(self, key: str) -> Any:
        return self._values.get(key, DEFAULTS.get(key))

    def __setitem__(self, key: str, value: Any) -> None:
        self._values[key] = value

    def get(self, key: str, default: Any = None) -> Any:
        return self._values.get(key, default)

    def as_dict(self) -> dict[str, Any]:
        return dict(self._values)

    @classmethod
    def load(cls) -> Config:
        path = config_path()
        if path.is_file():
            try:
                with path.open(encoding="utf-8") as fh:
                    return cls(json.load(fh))
            except (OSError, json.JSONDecodeError):
                # A broken config must never stop the service from starting.
                return cls()
        return cls()

    def save(self) -> None:
        path = config_path()
        path.parent.mkdir(parents=True, exist_ok=True)
        merged: dict[str, Any] = {}
        if path.is_file():
            try:
                with path.open(encoding="utf-8") as fh:
                    merged = json.load(fh)
            except (OSError, json.JSONDecodeError):
                merged = {}
        merged.update(self._values)
        tmp = path.with_suffix(".json.tmp")
        with tmp.open("w", encoding="utf-8") as fh:
            json.dump(merged, fh, indent=2, sort_keys=True)
            fh.write("\n")
        tmp.replace(path)

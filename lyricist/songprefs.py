"""Per-song memory: lyric timing offset, transpose, capo and pinned picks.

Timing drifts between releases (and between LRCLIB's copy of a song and the one
you are actually playing), chords often need a capo for the way you play them,
and the automatic match sometimes lands on the live version instead of the
studio one. All three are per-song facts, so they are stored per song and come
back the next time that track starts.
"""

from __future__ import annotations

import json
import threading
from pathlib import Path
from typing import Any

from .config import data_home

_FILENAME = "song-prefs.json"
_FIELDS = ("offset", "transpose", "capo", "lyrics_id", "chord_url")
_MAX_ENTRIES = 800


def path() -> Path:
    return data_home() / _FILENAME


def key_for(artist: str, title: str) -> str:
    """One key per song, independent of the service it came from."""
    parts = [part.strip().lower() for part in (artist or "", title or "")]
    return " - ".join(part for part in parts if part)


class SongPrefs:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._data: dict[str, dict[str, Any]] | None = None

    # ------------------------------------------------------------- storage
    def _load(self) -> dict[str, dict[str, Any]]:
        if self._data is None:
            try:
                raw = json.loads(path().read_text("utf-8"))
                self._data = {
                    str(k): {str(f): v for f, v in entry.items()}
                    for k, entry in raw.items()
                    if isinstance(entry, dict)
                }
            except (OSError, ValueError):
                self._data = {}
        return self._data

    def _write(self, data: dict[str, dict[str, Any]]) -> None:
        try:
            target = path()
            target.parent.mkdir(parents=True, exist_ok=True)
            tmp = target.with_name(target.name + ".tmp")
            tmp.write_text(json.dumps(data, indent=2, sort_keys=True), "utf-8")
            tmp.replace(target)
        except OSError:
            pass  # a preference is never worth failing a request over

    # ------------------------------------------------------------ interface
    def get(self, artist: str, title: str) -> dict[str, Any]:
        key = key_for(artist, title)
        if not key:
            return {}
        with self._lock:
            return dict(self._load().get(key, {}))

    def update(self, artist: str, title: str, values: dict[str, Any]) -> dict[str, Any]:
        key = key_for(artist, title)
        if not key or not isinstance(values, dict):
            return {}

        clean: dict[str, Any] = {}
        for field in _FIELDS:
            if field not in values:
                continue
            value = values[field]
            try:
                if field == "offset":
                    clean[field] = round(float(value), 3)
                elif field in ("transpose", "capo"):
                    clean[field] = int(value)
                else:
                    clean[field] = str(value).strip() if value else ""
            except (TypeError, ValueError):
                continue

        with self._lock:
            data = self._load()
            entry = dict(data.get(key, {}))
            entry.update(clean)
            # Drop the fields that were explicitly cleared, but keep zeros:
            # "no offset" and "no transpose" are meaningful choices.
            for field in list(entry):
                if entry[field] == "" or entry[field] is None:
                    del entry[field]
            if entry:
                data[key] = entry
            else:
                data.pop(key, None)
            while len(data) > _MAX_ENTRIES:
                data.pop(next(iter(data)), None)
            self._write(data)
            return dict(entry)

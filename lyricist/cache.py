"""A tiny on-disk JSON cache.

Deliberately dumb: one file per key, written atomically. The widget asks for
the same song over and over (every track change, every retry, every restart of
the compositor), so the whole point is that we never hit the network twice for
the same thing.
"""

from __future__ import annotations

import hashlib
import json
import os
import time
from pathlib import Path
from typing import Any

from .config import cache_home


def key_for(*parts: object) -> str:
    """A stable filename-safe key for a tuple of search terms."""
    raw = "\x1f".join(str(p or "").strip().lower() for p in parts)
    return hashlib.sha1(raw.encode("utf-8")).hexdigest()


class DiskCache:
    def __init__(self, namespace: str, ttl: int = 0) -> None:
        self.dir = cache_home() / namespace
        self.ttl = ttl

    def _path(self, key: str) -> Path:
        return self.dir / f"{key}.json"

    def get(self, key: str) -> Any | None:
        path = self._path(key)
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return None

        stored_at = data.get("_stored_at", 0)
        ttl = data.get("_ttl", self.ttl)
        if ttl and ttl > 0 and (time.time() - stored_at) > ttl:
            return None
        return data.get("value")

    def set(self, key: str, value: Any, ttl: int | None = None) -> None:
        self.dir.mkdir(parents=True, exist_ok=True)
        payload = {
            "_stored_at": time.time(),
            "_ttl": self.ttl if ttl is None else ttl,
            "value": value,
        }
        path = self._path(key)
        tmp = path.with_suffix(".tmp")
        try:
            with tmp.open("w", encoding="utf-8") as fh:
                json.dump(payload, fh, ensure_ascii=False)
            tmp.replace(path)
        except OSError:
            # A read-only or full cache directory must not break playback.
            tmp.unlink(missing_ok=True)

    def stats(self) -> dict[str, Any]:
        try:
            files = list(self.dir.glob("*.json"))
            size = sum(f.stat().st_size for f in files)
        except OSError:
            return {"entries": 0, "bytes": 0, "dir": str(self.dir)}
        return {"entries": len(files), "bytes": size, "dir": str(self.dir)}

    def clear(self) -> int:
        removed = 0
        for path in self.dir.glob("*.json"):
            try:
                os.unlink(path)
                removed += 1
            except OSError:
                pass
        return removed

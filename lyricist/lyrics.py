"""Lyrics lookup against LRCLIB (https://lrclib.net).

LRCLIB is free, needs no key, and - crucially for this widget - returns
*time-synced* LRC rather than a wall of text. It is also a community database,
so the same song often exists several times with different quality; the match
below prefers an exact duration hit and then an entry that actually has synced
lyrics.
"""

from __future__ import annotations

import re
import urllib.parse
from typing import Any

from . import lrc
from .cache import DiskCache, key_for
from .config import Config
from .http import Throttle, fetch_json

BASE = "https://lrclib.net/api"

# Noise that streaming metadata carries but a lyrics database does not. A
# bracket is dropped whenever it mentions any of these, however it is worded:
# "(Official Video)", "(Official Music Video)", "(Lyrical Video)", "[HD]" and
# "(Live at Wembley)" are the same decoration, and no tab or lyrics site lists
# any of them. Matching the keyword anywhere inside the bracket (rather than
# right before the closing one) is what catches the multi-word tags.
_NOISE = re.compile(
    r"""
    \s*[\(\[]\s*[^\)\]]*
    \b(?:official|lyric|lyrics|lyrical|audio|video|visuali[sz]er|hd|hq|4k|mv|m/v|
    remaster(?:ed)?(?:\s*\d{0,4})?|live|radio\s*edit|explicit|clean|mono|stereo|
    bonus\s*track|deluxe|instrumental|karaoke|full\s+video)\b
    [^\)\]]*[\)\]]
    """,
    re.I | re.X,
)
# "... - YouTube" and "... - Official Video" trail a video title and mean
# nothing to a lyrics database.
_TRAILING = re.compile(
    r"\s*[-–—]\s*(?:topic|official(?:\s+\w+)*|audio|lyrics?|video|youtube|"
    r"music\s+video|full\s+video)\s*\.?\s*$",
    re.I,
)
# A bare trailing role word carries no dash, so _TRAILING leaves it behind:
# "... Edge Of Desire lyrics" has to lose the " lyrics" too.
_TRAILING_WORD = re.compile(
    r"\s+(?:(?:official|full|new|music)\s+)?(?:lyrics?|audio|video|mv|hd|hq|4k|8d)\s*$",
    re.I,
)
_FEAT = re.compile(r"\s*[\(\[]?\s*(?:feat|ft|featuring)\.?\s+[^\)\]]*[\)\]]?\s*$", re.I)
# A quoted album or EP tag tacked onto the end of a video title
# ("... "EP NAALAYAK".").
_QUOTED = re.compile(r"\s*[\u201c\u201d\x22\x27][^\u201c\u201d\x22\x27]*[\u201c\u201d\x22\x27]\s*[.\u3002]?\s*$")
# The unread-count badge a browser puts in front of a background tab's title.
_BADGE = re.compile(r"^\s*[\(\[]\s*\d{1,2}\+?\s*[\)\]]\s+")


def clean(text: str) -> str:
    """Strip the streaming-service decoration from a title or artist.

    Streaming metadata is written for people, not databases: it carries an
    unread badge, an "Official music video" tag, the album in quotes and a
    " - YouTube" suffix, none of which exist in a lyrics or tab title.
    """
    if not text:
        return ""
    value = _BADGE.sub("", text)
    value = _FEAT.sub("", value)
    value = _NOISE.sub("", value)
    value = _TRAILING.sub("", value)
    for _ in range(3):
        stripped = _TRAILING_WORD.sub("", value)
        if stripped == value:
            break
        value = stripped
    value = _QUOTED.sub("", value)
    return re.sub(r"\s{2,}", " ", value).strip(" -–—")


def _norm(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", " ", (text or "").lower()).strip()


# A video title joins the song to the movie, the actors and the singers with a
# pipe, a dash or a slash; and streaming metadata puts the *channel* (a YouTube
# uploader) in the artist field, which is not an artist a lyrics database has
# ever heard of. So the plain artist+title search misses, and the title has to
# be taken apart.
_SEP = re.compile(r"\s*(?:\||/|–|—|·)\s*|\s+-\s+")


def _title_variants(title: str) -> list[str]:
    """The whole title, then its first and last segments, deduped in order."""
    out: list[str] = [title]
    parts = [p.strip() for p in _SEP.split(title) if p.strip()]
    if len(parts) > 1:
        out.append(parts[0])
        out.append(parts[-1])
    seen: set[str] = set()
    variants: list[str] = []
    for value in out:
        key = value.casefold()
        if value and key not in seen:
            seen.add(key)
            variants.append(value)
    return variants


def _plausible(entry: dict[str, Any], title: str) -> bool:
    """A fallback hit must name a song that appears in the title we were given."""
    track = _norm(entry.get("trackName", ""))
    if not track:
        return False
    wanted = _norm(title)
    return track in wanted or wanted in track


def _score(entry: dict[str, Any], artist: str, title: str, duration: float) -> float:
    score = 0.0
    if _norm(entry.get("trackName", "")) == _norm(title):
        score += 6.0
    if _norm(entry.get("artistName", "")) == _norm(artist):
        score += 6.0
    if entry.get("syncedLyrics"):
        score += 4.0
    if entry.get("hasWordSync"):
        score += 1.0
    entry_duration = entry.get("duration") or 0
    if duration and entry_duration:
        delta = abs(float(entry_duration) - duration)
        if delta <= 2:
            score += 6.0
        elif delta <= 5:
            score += 3.0
        elif delta <= 15:
            score += 1.0
        else:
            score -= min(delta / 10.0, 4.0)
    if entry.get("instrumental"):
        score -= 0.5
    return score


def _shape(entry: dict[str, Any]) -> dict[str, Any]:
    synced_text = entry.get("syncedLyrics") or ""
    lines = lrc.parse(synced_text) if synced_text else lrc.as_plain_lines(entry.get("plainLyrics") or "")
    return {
        "source": "lrclib",
        "id": entry.get("id"),
        "url": f"https://lrclib.net/lyrics/{entry.get('id')}",
        "track": entry.get("trackName"),
        "artist": entry.get("artistName"),
        "album": entry.get("albumName"),
        "duration": entry.get("duration"),
        "instrumental": bool(entry.get("instrumental")),
        "synced": bool(synced_text),
        "word_synced": bool(entry.get("hasWordSync")),
        "lines": lines,
        "plain": entry.get("plainLyrics") or lrc.to_plain(lines),
    }


class LyricsProvider:
    def __init__(self, config: Config, throttle: Throttle) -> None:
        self.config = config
        self.throttle = throttle
        self.cache = DiskCache("lyrics", ttl=int(config.get("lyrics_ttl_seconds", 0)))
        self.contact = config.get("contact") or ""

    def lookup(
        self,
        artist: str,
        title: str,
        album: str = "",
        duration: float = 0.0,
        lyrics_id: Any = None,
    ) -> dict[str, Any]:
        artist = clean(artist)
        title = clean(title)
        if not title:
            return {"source": "none", "error": "no track title"}

        # A hand-picked entry wins over the automatic match.
        if lyrics_id:
            pinned_key = key_for("pinned", str(lyrics_id))
            cached = self.cache.get(pinned_key)
            if cached is not None:
                cached = dict(cached)
                cached["cached"] = True
                cached["pinned"] = True
                return cached
            pinned = self.by_id(lyrics_id)
            if pinned:
                pinned["pinned"] = True
                self.cache.set(pinned_key, pinned)
                return pinned

        key = key_for(artist, title, album, int(duration or 0) // 5)
        cached = self.cache.get(key)
        if cached is not None:
            cached = dict(cached)
            cached["cached"] = True
            return cached

        result = self._lookup_remote(artist, title, album, duration)
        if result and result.get("source") != "none":
            self.cache.set(key, result)
        return result

    def _lookup_remote(self, artist: str, title: str, album: str, duration: float) -> dict[str, Any]:
        headers = self._headers()

        # 1. The exact-match endpoint. Cheap and precise when it hits.
        params = {"artist_name": artist, "track_name": title}
        if album:
            params["album_name"] = album
        if duration:
            params["duration"] = str(int(round(duration)))
        try:
            entry = fetch_json(
                f"{BASE}/get?{urllib.parse.urlencode(params)}",
                throttle=self.throttle,
                timeout=float(self.config.get("request_timeout", 20)),
                headers=headers,
                retries=1,
            )
            if isinstance(entry, dict) and entry.get("trackName"):
                return _shape(entry)
        except Exception:
            pass

        # 2. Search, then pick the best-scoring candidate ourselves. Streaming
        #    metadata often carries the *channel* as the artist (a YouTube
        #    uploader) and the real artist inside the title, so an artist+title
        #    search can miss completely. Try that first, then the title alone
        #    and its segments - a fallback hit is only accepted when its own
        #    name appears in the title, so a same-named song from somewhere
        #    else cannot sneak in.
        plans: list[tuple[dict[str, str], bool]] = []
        if artist:
            plans.append(({"artist_name": artist, "track_name": title}, False))
        else:
            plans.append(({"q": title}, False))
        plans.append(({"q": title}, True))
        for variant in _title_variants(title):
            if variant == title:
                continue
            plans.append(({"q": variant}, True))
            if artist:
                plans.append(({"artist_name": artist, "track_name": variant}, True))

        seen: set[tuple] = set()
        queries: list[tuple[dict[str, str], bool]] = []
        for params, require_plausible in plans:
            signature = tuple(sorted(params.items()))
            if signature not in seen:
                seen.add(signature)
                queries.append((params, require_plausible))

        timeout = float(self.config.get("request_timeout", 20))
        best: dict[str, Any] | None = None
        best_score = -1e9
        for params, require_plausible in queries:
            try:
                rows = fetch_json(
                    f"{BASE}/search?{urllib.parse.urlencode(params)}",
                    throttle=self.throttle,
                    timeout=timeout,
                    headers=headers,
                    retries=1,
                )
            except Exception:
                continue
            if not isinstance(rows, list):
                continue
            for row in rows[:25]:
                if not isinstance(row, dict):
                    continue
                if require_plausible and not _plausible(row, title):
                    continue
                score = _score(row, artist, title, duration)
                if score > best_score:
                    best_score = score
                    best = row
            if best is not None and best_score >= 14.0:
                break

        if best is None:
            return {"source": "none", "error": "no match"}
        return _shape(best)

    # ------------------------------------------------------------- versions

    def _headers(self) -> dict[str, str]:
        return {"User-Agent": f"lyricist/1.0.0 (contact: {self.contact or 'none'})"}

    def by_id(self, lyrics_id: Any) -> dict[str, Any] | None:
        """One specific LRCLIB entry, for when the automatic match picked wrong."""
        try:
            entry = fetch_json(
                f"{BASE}/get/{int(lyrics_id)}",
                throttle=self.throttle,
                timeout=float(self.config.get("request_timeout", 20)),
                headers=self._headers(),
                retries=1,
            )
        except Exception:
            return None
        if isinstance(entry, dict) and entry.get("trackName"):
            return _shape(entry)
        return None

    def candidates(
        self,
        artist: str,
        title: str,
        album: str = "",
        duration: float = 0.0,
        limit: int = 12,
    ) -> list[dict[str, Any]]:
        """Every plausible LRCLIB entry for a song, best match first.

        The same song is often in the database several times (album, single,
        live, remaster), and for non-Latin songs the script can differ between
        them, so the automatic pick is not always the one somebody wants.
        """
        artist = clean(artist)
        title = clean(title)
        if not title:
            return []
        query = {"artist_name": artist, "track_name": title} if artist else {"q": title}
        try:
            rows = fetch_json(
                f"{BASE}/search?{urllib.parse.urlencode(query)}",
                throttle=self.throttle,
                timeout=float(self.config.get("request_timeout", 20)),
                headers=self._headers(),
                retries=1,
            )
        except Exception:
            return []
        if not isinstance(rows, list):
            return []
        ranked = sorted(
            (row for row in rows if isinstance(row, dict)),
            key=lambda row: _score(row, artist, title, duration),
            reverse=True,
        )
        out: list[dict[str, Any]] = []
        for entry in ranked[: max(1, limit)]:
            out.append(
                {
                    "id": entry.get("id"),
                    "track": entry.get("trackName"),
                    "artist": entry.get("artistName"),
                    "album": entry.get("albumName"),
                    "duration": entry.get("duration"),
                    "instrumental": bool(entry.get("instrumental")),
                    "synced": bool(entry.get("syncedLyrics")),
                    "word_synced": bool(entry.get("hasWordSync")),
                    "score": round(_score(entry, artist, title, duration), 2),
                }
            )
        return out

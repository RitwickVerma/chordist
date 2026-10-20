"""Chord chart lookup: the user's own files first, then the network.

Provider order is deliberate. A chart the user wrote or pasted always wins,
because it is the one that will actually be right for how they play the song.
Only if there is nothing local do we go scraping, and whatever we scrape is
written to disk so Ultimate Guitar is asked about a given song exactly once.
"""

from __future__ import annotations

import html
import json
import logging
import re
import time
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit

from . import chart, shapes, titles
from .cache import DiskCache, key_for
from .config import Config, chords_dir
from .http import HttpError, Throttle, fetch

log = logging.getLogger("lyricist.chords")

UG_BASE = "https://www.ultimate-guitar.com"
# Kinds of tab the widget can show. Chords are tried first; a song nobody has
# charted in chords (an instrumental, a fingerpicked piece) falls back to Tabs.
_PLAYABLE = ("Chords", "Tabs")
UG_SEARCH = UG_BASE + "/search.php?search_type=title&value={query}"

# Bump when the matching rules change so cached picks are re-resolved.
MATCHER_VERSION = 5


def is_ug_url(url: Any) -> bool:
    """Only Ultimate Guitar over https may be fetched on a caller's say-so.

    A pinned tab arrives as a URL in a query string; without this check the
    service would fetch whatever address it was handed (``file://``, a router's
    admin page, a LAN host).
    """
    if not isinstance(url, str):
        return False
    parts = urlsplit(url.strip())
    host = (parts.hostname or "").lower()
    return parts.scheme == "https" and (host == "ultimate-guitar.com" or host.endswith(".ultimate-guitar.com"))


def _cache_key(artist: str, title: str) -> str:
    return key_for(MATCHER_VERSION, "song", artist, title)


def _pinned_key(url: str) -> str:
    return key_for(MATCHER_VERSION, "pinned-chart", url)

_STORE_RE = re.compile(r'class="js-store"[^>]*data-content="(.*?)">\s*</div>', re.S)
_SLUG_RE = re.compile(r"[^a-z0-9]+")


def slug(text: str) -> str:
    return _SLUG_RE.sub("-", (text or "").lower()).strip("-")


def _store(page: str) -> dict[str, Any] | None:
    match = _STORE_RE.search(page)
    if not match:
        return None
    try:
        return json.loads(html.unescape(match.group(1)))
    except json.JSONDecodeError:
        return None


def _norm(text: str) -> str:
    return _SLUG_RE.sub(" ", (text or "").lower()).strip()


# Separators a video title uses between the channel/uploader and the song. The
# bare ones catch titles like "Sahil Samuel-Zakir" where the uploader left out
# the space; the spaced forms are listed first so they win on a tie.
_TITLE_SEPARATORS = (
    " - ", " – ", " — ", " | ", " / ",
    "- ", "– ", "— ", "| ", "/ ",
    "-", "–", "—", "|",
)


def _strumming(tab_view: dict[str, Any]) -> list[dict[str, Any]]:
    """Strumming patterns as UG stores them (``measures`` is UG's own code)."""
    raw = tab_view.get("encode_strummings")
    if isinstance(raw, str) and raw.strip():
        try:
            raw = json.loads(raw)
        except json.JSONDecodeError:
            raw = None
    patterns = raw.get("patterns") if isinstance(raw, dict) else None
    out: list[dict[str, Any]] = []
    for pattern in patterns if isinstance(patterns, list) else []:
        if not isinstance(pattern, dict):
            continue
        try:
            bpm = int(pattern.get("bpm") or 0)
            denominator = int(pattern.get("denuminator") or 0)
        except (TypeError, ValueError):
            continue
        out.append(
            {
                "part": str(pattern.get("part") or ""),
                "bpm": bpm or None,
                "denominator": denominator or None,
                "triplet": bool(pattern.get("is_triplet")),
                "measures": pattern.get("measures") if isinstance(pattern.get("measures"), list) else [],
            }
        )
    return out


def _number(value: Any) -> int | float | None:
    return value if isinstance(value, (int, float)) and not isinstance(value, bool) else None


def ug_meta(data: dict[str, Any], item: dict[str, Any]) -> dict[str, Any]:
    """The guitarist-facing facts on a tab page: tuning, key, difficulty, stats.

    ``data`` is the page's ``store.page.data``; ``item`` is the search result
    that led here (it may be empty for a pinned tab, so every field falls back).
    """
    tab_view = data.get("tab_view") or {}
    tab = data.get("tab") if isinstance(data.get("tab"), dict) else {}
    meta = tab_view.get("meta") or {}
    stats = tab_view.get("stats") or {}
    wiki = tab_view.get("wiki_tab") or {}
    tuning = meta.get("tuning") if isinstance(meta.get("tuning"), dict) else {}
    notes = str(tuning.get("value") or "").split()
    strumming = _strumming(tab_view)
    return {
        "tuning": {"name": str(tuning.get("name") or ""), "notes": notes},
        "difficulty": str(meta.get("difficulty") or tab_view.get("ug_difficulty") or ""),
        "tonality": str(meta.get("tonality") or tab.get("tonality_name") or item.get("tonality_name") or ""),
        "type": str(tab.get("type") or item.get("type") or ""),
        "version": tab.get("version") or item.get("version"),
        "rating": _number(tab.get("rating") if tab.get("rating") is not None else item.get("rating")),
        "votes": _number(tab.get("votes") if tab.get("votes") is not None else item.get("votes")),
        "views": _number(stats.get("view_total")),
        "favorites": _number(stats.get("favorites_count")),
        "author": str(wiki.get("username") or ""),
        "bpm": next((p["bpm"] for p in strumming if p.get("bpm")), None),
        "strumming": strumming,
        "simplified_available": bool(tab_view.get("is_simplify_available")),
    }


def _song_tail(title: str) -> str:
    """The part of a video title after its last separator.

    A song on a video site is titled "Channel / Collaborator - Song", and the
    whole string is not something a tab site can search for. The part after the
    last separator is nearly always the song itself, so it is worth one more
    search when the full title comes back empty.
    """
    index = -1
    width = 0
    for separator in _TITLE_SEPARATORS:
        found = title.rfind(separator)
        if found > index:
            index = found
            width = len(separator)
    if index < 0:
        return ""
    return title[index + width:].strip()


class ChordProvider:
    def __init__(self, config: Config, throttle: Throttle) -> None:
        self.config = config
        self.throttle = throttle
        self.cache = DiskCache("chords", ttl=int(config.get("chords_ttl_seconds", 0)))
        self.negative_ttl = int(config.get("negative_ttl_seconds", 3 * 24 * 3600))
        self.directory = chords_dir()

    # ---------------------------------------------------------------- local

    def local_candidates(self, artist: str, title: str) -> list[Path]:
        keys = []
        if artist and title:
            keys.append(f"{slug(artist)}-{slug(title)}")
        if title:
            keys.append(slug(title))
            if artist:
                keys.append(f"{slug(title)}-{slug(artist)}")
        if artist:
            keys.append(slug(artist))
        found: list[Path] = []
        for key in keys:
            if not key:
                continue
            for suffix in (".chordpro", ".cho", ".pro", ".txt"):
                path = self.directory / f"{key}{suffix}"
                if path.is_file():
                    found.append(path)
        return found

    def load_local(self, artist: str, title: str) -> dict[str, Any] | None:
        for path in self.local_candidates(artist, title):
            try:
                text = path.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            if not text.strip():
                continue
            result = chart.parse(text, fmt="auto", title=title, artist=artist)
            result["source"] = "local"
            result["url"] = None
            result["file"] = str(path)
            result["editable"] = True
            return result
        return None

    def save_local(self, artist: str, title: str, text: str, fmt: str = "auto") -> dict[str, Any]:
        parsed = chart.parse(text, fmt=fmt, title=title, artist=artist)
        stem = f"{slug(artist)}-{slug(title)}" if artist else slug(title)
        if not stem:
            stem = f"untitled-{int(time.time())}"

        self.directory.mkdir(parents=True, exist_ok=True)
        path = self.directory / f"{stem}.chordpro"
        path.write_text(chart.to_chordpro(parsed), encoding="utf-8")

        # A fresh local chart must win immediately over a cached scraped one.
        self.cache.set(_cache_key(artist, title), None, ttl=1)
        parsed["source"] = "local"
        parsed["file"] = str(path)
        parsed["editable"] = True
        return parsed

    def delete_local(self, artist: str, title: str) -> bool:
        removed = False
        for path in self.local_candidates(artist, title):
            try:
                path.unlink()
                removed = True
            except OSError:
                pass
        if removed:
            self.cache.set(_cache_key(artist, title), None, ttl=1)
        return removed

    def list_local(self) -> list[dict[str, Any]]:
        if not self.directory.is_dir():
            return []
        items: list[dict[str, Any]] = []
        for path in sorted(self.directory.glob("*.chordpro")):
            try:
                stat = path.stat()
            except OSError:
                continue
            items.append(
                {
                    "file": str(path),
                    "slug": path.stem,
                    "size": stat.st_size,
                    "modified": stat.st_mtime,
                }
            )
        return items

    # ------------------------------------------------------------ ultimate

    def _ug_search(self, query: str) -> list[dict[str, Any]]:
        """One search request.

        Ultimate Guitar answers a query it cannot handle with a 404 instead of
        an empty page - prepending the artist to a title search does it often -
        so a 404 means "nothing here", not "ask again later".
        """
        url = UG_SEARCH.format(query=re.sub(r"\s+", "+", query.strip()))
        try:
            page = fetch(
                url,
                throttle=self.throttle,
                timeout=float(self.config.get("request_timeout", 20)),
                headers={"Referer": "https://www.google.com/"},
                retries=1,
            )
        except HttpError as exc:
            if exc.status == 404:
                return []
            raise
        store = _store(page)
        if not store:
            return []
        results = store.get("store", {}).get("page", {}).get("data", {}).get("results") or []
        return [item for item in results if isinstance(item, dict) and item.get("tab_url")]

    def _ug_pick_all(
        self,
        results: list[dict[str, Any]],
        artist: str,
        title: str,
        types: tuple[str, ...] | None = ("Chords",),
        guarded_only: bool = True,
        album: str = "",
    ) -> list[tuple[float, dict[str, Any]]]:
        """Every tab for a song, best first, so a wrong pick can be fixed.

        A tab is only trusted when every meaningful word of its name already
        appears in the title or artist we were given (``titles.subset``). That
        is what stops a search for "Judaai" from accepting "I Love Ny - Judaai"
        - a different film's song - or Arijit Singh's "Judaa": those names carry
        words the streamed title never had. A tab may add only version words of
        its own ("Acoustic", "Live", "Remastered").

        Among tabs that match equally well, popularity (votes, modulated by
        rating) decides, so a version with 35 votes at 4.7 beats one with 6
        votes at 4.8. It stays a tie-breaker, far below the match term.

        ``types`` restricts the kinds of tab (``("Chords",)`` for the automatic
        pick); pass ``None`` for every kind. With ``guarded_only=False`` the
        unguarded tabs are kept too, sorted last, so the chooser can still offer
        them when nothing matched well.
        """
        context = f"{artist} {title} {album}".strip()
        picked: list[tuple[dict[str, Any], float, float, float]] = []
        max_votes = 0.0
        for item in results:
            if types is not None and item.get("type") not in types:
                continue
            song_name = item.get("song_name") or ""
            guarded = titles.shares_word(title, song_name) and (
                titles.subset(context, song_name)
                or titles.film_filed(title, song_name, context)
            )
            if guarded_only and not guarded:
                continue
            name_exact = bool(_norm(title)) and _norm(song_name) == _norm(title)
            match = 0.0
            if name_exact:
                match += 8.0
            elif guarded:
                match += 4.0
            artist_exact = bool(artist) and _norm(item.get("artist_name")) == _norm(artist)
            artist_part = artist_exact or (bool(artist) and _norm(artist) in _norm(item.get("artist_name")))
            # The guard already leans on the artist, so this is only a nudge and
            # never enough to lift an unguarded tab above a guarded one.
            if artist_exact:
                match += 1.0
            elif artist_part:
                match += 0.5
            votes = max(float(item.get("votes") or 0), 0.0)
            rating = min(float(item.get("rating") or 0), 5.0)
            max_votes = max(max_votes, votes)
            picked.append((item, match, votes, rating))
        scored: list[tuple[float, dict[str, Any]]] = []
        for item, match, votes, rating in picked:
            # Stays below the smallest match gap (4) so popularity can only
            # reorder tabs that match equally well.
            popularity = 2.9 * (rating / 5.0) * (votes / max_votes) if max_votes else 0.0
            score = match + popularity
            if item.get("tab_access_type") != "public":
                score -= 5.0
            scored.append((score, item))
        scored.sort(key=lambda pair: pair[0], reverse=True)
        return scored

    def _ug_results(self, artist: str, title: str, album: str = "") -> list[dict[str, Any]]:
        """Search the song names hidden in a polluted title, most likely first.

        A streamed title carries the song plus noise; ``titles.candidate_queries``
        hands back the strings worth trying. The first query whose results hold
        a *guarded* match wins, so a search that only turned up somebody else's
        song does not end the hunt. If none match, the first non-empty answer is
        returned anyway, so the version chooser still has something to offer.
        """
        fallback: list[dict[str, Any]] = []
        error: Exception | None = None
        for query in titles.candidate_queries(artist, title, album=album):
            if not query:
                continue
            try:
                results = self._ug_search(query)
            except Exception as exc:  # rate limits and the like: try the next
                error = exc
                continue
            if results:
                if not fallback:
                    fallback = results
                if self._ug_pick_all(
                    results, artist, title, types=_PLAYABLE, guarded_only=True, album=album
                ):
                    return results
        if not fallback and error is not None:
            raise error
        return fallback

    def _ug_pick(
        self,
        results: list[dict[str, Any]],
        artist: str,
        title: str,
        album: str = "",
        types: tuple[str, ...] = ("Chords",),
    ) -> dict[str, Any] | None:
        scored = self._ug_pick_all(results, artist, title, types=types, guarded_only=True, album=album)
        return scored[0][1] if scored and scored[0][0] > 0 else None

    def _ug_fetch(self, item: dict[str, Any]) -> dict[str, Any] | None:
        url = item["tab_url"]
        if not is_ug_url(url):
            log.warning("refusing to fetch a tab from %r", url)
            return None
        page = fetch(
            url,
            throttle=self.throttle,
            timeout=float(self.config.get("request_timeout", 20)),
            headers={"Referer": f"{UG_BASE}/"},
            retries=1,
        )
        store = _store(page)
        if not store:
            return None
        data = store.get("store", {}).get("page", {}).get("data", {})
        tab_view = data.get("tab_view") or {}
        content = (tab_view.get("wiki_tab") or {}).get("content")
        if not content:
            return None

        meta = tab_view.get("meta") or {}
        result = chart.parse(content, fmt="ug", title=item.get("song_name") or "", artist=item.get("artist_name") or "")
        result["source"] = "ultimate-guitar"
        result["url"] = url
        # chart.parse only sets these when the body repeats them; keep the
        # names the search result already gave us so the popup can show them.
        if not result.get("title"):
            result["title"] = item.get("song_name") or ""
        if not result.get("artist"):
            result["artist"] = item.get("artist_name") or ""
        result["key"] = meta.get("tonality") or item.get("tonality_name") or result.get("key") or ""
        try:
            result["capo"] = int(meta.get("capo") or 0)
        except (TypeError, ValueError):
            result["capo"] = 0
        info = ug_meta(data, item)
        result["meta"] = info
        result["rating"] = info["rating"]
        result["votes"] = info["votes"]
        result["version"] = info["version"]
        # UG's own fingerings for exactly the chords on this page. They beat the
        # generic shape tables (A7sus4, slash chords, odd voicings), so they are
        # passed through for the widget to prefer.
        applicature: dict[str, list[dict[str, Any]]] = {}
        raw = tab_view.get("applicature")
        for name, entries in (raw.items() if isinstance(raw, dict) else []):
            voicings = shapes.from_applicature(str(name), entries)
            if voicings:
                applicature[str(name)] = voicings
        result["applicature"] = applicature
        return result

    # ----------------------------------------------------------- candidates

    def candidates(
        self, artist: str, title: str, limit: int = 24, album: str = ""
    ) -> list[dict[str, Any]]:
        """Every tab Ultimate Guitar has for a song, best match first.

        The automatic pick is usually right, but versions (live, acoustic,
        simplified) are common enough that a wrong one needs a manual fix. This
        deliberately includes every kind of tab, not just chord charts, so the
        chooser can offer a fingerstyle arrangement or a bass line too.
        """
        from .lyrics import clean

        artist = clean(artist)
        title = clean(title)
        if not title or not self.config.get("ug_enabled", True):
            return []
        try:
            results = self._ug_results(artist, title, album)
        except Exception:
            return []
        out: list[dict[str, Any]] = []
        # Guarded (matching) tabs sort first; the rest are kept so the chooser
        # can still offer something when the title matched nothing well.
        for score, item in self._ug_pick_all(results, artist, title, types=None, guarded_only=False, album=album)[: max(1, limit)]:
            out.append(
                {
                    "url": item.get("tab_url"),
                    "name": item.get("song_name"),
                    "artist": item.get("artist_name"),
                    "type": item.get("type"),
                    "version": item.get("version"),
                    "rating": item.get("rating"),
                    "votes": item.get("votes"),
                    "tonality": item.get("tonality_name"),
                    "score": round(score, 2),
                }
            )
        return out

    # -------------------------------------------------------------- lookup

    def lookup(
        self,
        artist: str,
        title: str,
        duration: float = 0.0,
        chord_url: str | None = None,
        album: str = "",
    ) -> dict[str, Any]:
        from .lyrics import clean

        artist = clean(artist)
        title = clean(title)
        if not title:
            return {"source": "none", "error": "no track title", "sections": []}

        sources = list(self.config.get("chords_sources") or [])

        if "local" in sources:
            local = self.load_local(artist, title)
            if local and local.get("sections"):
                return local

        if chord_url and not is_ug_url(chord_url):
            log.warning("ignoring pinned tab with a non-Ultimate-Guitar address: %r", chord_url)
            chord_url = None

        # A tab the user picked by hand beats anything we would choose ourselves.
        if chord_url:
            pinned_key = _pinned_key(chord_url)
            cached = self.cache.get(pinned_key)
            if isinstance(cached, dict) and cached.get("sections"):
                cached = dict(cached)
                cached["cached"] = True
                cached["pinned"] = True
                return cached
            pinned = self._ug_fetch({"tab_url": chord_url})
            if pinned and pinned.get("sections"):
                pinned["pinned"] = True
                self.cache.set(pinned_key, pinned)
                return pinned

        key = _cache_key(artist, title)
        if "cache" in sources:
            cached = self.cache.get(key)
            if isinstance(cached, dict) and cached.get("sections"):
                cached = dict(cached)
                cached["cached"] = True
                return cached

        if "ultimate-guitar" in sources and self.config.get("ug_enabled", True):
            try:
                results = self._ug_results(artist, title, album)
                for kinds in (("Chords",), ("Tabs",)):
                    picked = self._ug_pick(results, artist, title, album, types=kinds)
                    result = self._ug_fetch(picked) if picked else None
                    if result and result.get("sections"):
                        self.cache.set(key, result)
                        return result
            except HttpError as exc:
                # Rate limited: remember the miss only briefly so we retry soon.
                self.cache.set(key, {"source": "none", "sections": [], "error": str(exc)}, ttl=900)
                return {"source": "none", "sections": [], "error": str(exc), "retry_in": 900}
            except Exception as exc:  # never let a scrape break the popup
                log.warning("chord lookup for %s - %s failed: %s", artist, title, exc)
                return {"source": "none", "sections": [], "error": str(exc)}

        self.cache.set(key, {"source": "none", "sections": []}, ttl=self.negative_ttl)
        return {"source": "none", "sections": [], "error": "no chords found"}

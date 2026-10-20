# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
#
# SPDX-License-Identifier: MIT

"""The local JSON API the Plasma widget talks to.

Everything slow - HTTP scraping, parsing, disk caching - happens here, behind a
synchronous-looking JSON endpoint, so the QML side never blocks the compositor.
Requests are served on threads, and identical in-flight lookups are collapsed
so a popup opening and closing twice cannot cause a double scrape.
"""

from __future__ import annotations

import contextlib
import ipaddress
import json
import logging
import threading
import time
from collections.abc import Callable, Iterator
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any
from urllib.parse import parse_qs, urlparse

from . import __version__, align, identity, shapes, translit
from .chords import ChordProvider
from .config import Config
from .http import Throttle
from .lyrics import LyricsProvider
from .songprefs import SongPrefs

log = logging.getLogger("chordist.server")


def _as_float(value: Any, default: float = 0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _romanise_request(value: Any) -> bool | None:
    """Parse a caller's "romanise" wish: True, False, or None to follow config."""
    if value is None or value == "":
        return None
    if isinstance(value, bool):
        return value
    text = str(value).strip().lower()
    if text in ("1", "true", "yes", "on", "always"):
        return True
    if text in ("0", "false", "no", "off", "never"):
        return False
    return None


def _lyrics_text(lyrics: dict[str, Any] | None) -> str:
    if not lyrics:
        return ""
    lines = [line.get("text") or "" for line in (lyrics.get("lines") or [])]
    if any(lines):
        return " ".join(lines)
    return lyrics.get("plain") or ""


def _chart_text(chart: dict[str, Any] | None) -> str:
    if not chart:
        return ""
    return " ".join(
        line.get("lyric") or ""
        for section in (chart.get("sections") or [])
        for line in (section.get("lines") or [])
    )


def should_romanise(
    mode: str,
    requested: bool | None,
    lyrics: dict[str, Any] | None,
    chart: dict[str, Any] | None,
) -> bool:
    """Whether this song's lyrics should be romanised.

    What the caller asked for wins; without that the configured mode decides.
    "auto" romanises whenever the lyrics are in a non-Latin script, unless the
    chord chart for the same song is itself in that script — then the lyrics
    stay as they are so the two halves of the popup read in the same script.
    Latin lyrics are never touched.  A chart is not needed for the lyrics to
    become readable.
    """
    text = _lyrics_text(lyrics)
    if not text or not translit.needs_romanisation(text):
        return False
    if requested is not None:
        return requested
    mode = (mode or "auto").lower()
    if mode == "never":
        return False
    if mode == "always":
        return True
    chart_text = _chart_text(chart)
    return not chart_text.strip() or translit.is_latin(chart_text)


def romanise_lyrics(lyrics: dict[str, Any]) -> dict[str, Any]:
    """Copy of the lyrics with every piece of text romanised. Timings are kept."""
    if not lyrics:
        return lyrics
    original_script = translit.script_of(_lyrics_text(lyrics))
    romanised = dict(lyrics)
    romanised["script"] = original_script

    lines = []
    for line in lyrics.get("lines") or []:
        new_line = dict(line)
        new_line["text"] = translit.devanagari_to_latin(line.get("text") or "")
        words = line.get("words") or []
        if words:
            new_line["words"] = [
                {**word, "text": translit.devanagari_to_latin(word.get("text") or "")}
                for word in words
            ]
        lines.append(new_line)
    romanised["lines"] = lines

    if lyrics.get("plain"):
        romanised["plain"] = translit.devanagari_to_latin(lyrics["plain"])
    romanised["romanised"] = True
    return romanised


class KeyedLocks:
    """One lock per key, forgotten as soon as nobody holds or awaits it.

    The service used to keep a lock for every song ever played; this keeps only
    the ones in use.
    """

    def __init__(self) -> None:
        self._guard = threading.Lock()
        self._locks: dict[tuple[str, ...], list[Any]] = {}

    @contextlib.contextmanager
    def hold(self, *key: str) -> Iterator[None]:
        with self._guard:
            entry = self._locks.setdefault(key, [threading.Lock(), 0])
            entry[1] += 1
        try:
            with entry[0]:
                yield
        finally:
            with self._guard:
                entry[1] -= 1
                if entry[1] == 0:
                    self._locks.pop(key, None)


class Service:
    def __init__(self, config: Config) -> None:
        self.config = config
        self.throttle = Throttle(float(config.get("min_request_interval", 0) or 0))
        self.lyrics = LyricsProvider(config, self.throttle)
        self.chords = ChordProvider(config, self.throttle)
        self.prefs = SongPrefs()
        self.started = time.time()
        self._locks = KeyedLocks()

    def health(self) -> dict[str, Any]:
        return {
            "ok": True,
            "version": __version__,
            "port": self.config.get("port"),
            "sources": self.config.get("chords_sources"),
            "ug_enabled": self.config.get("ug_enabled"),
            "contact_configured": bool(self.config.get("contact")),
            "local_charts": len(self.chords.list_local()),
            "uptime_seconds": round(time.time() - self.started),
        }

    def _known_identity(self, artist: str, title: str, album: str = "") -> tuple[str, str, str]:
        """The artist, title and album a song was resolved to, else as given.

        For requests that act on a song (saving a chart, listing versions) and so
        must use the same names its lookups used. Never starts an audio capture.
        """
        found = identity.resolve(self.config, self.lyrics, artist, title, 0.0, album, allow_fingerprint=False)
        if not found:
            return artist, title, album
        return (found.get("artist") or artist, found.get("title") or title, found.get("album") or album)

    def _prepare_lyrics(
        self,
        artist: str,
        title: str,
        album: str,
        duration: float,
        romanise: Any,
        lyrics_id: Any = None,
        chord_url: Any = None,
        refresh: bool = False,
    ) -> tuple[dict[str, Any], dict[str, Any], bool, dict[str, Any] | None]:
        """Lyrics and chart for one song, with the script decision applied.

        The raw streaming metadata is resolved to one canonical identity first,
        and both providers run on that answer, so they can never disagree about
        which song is playing.  When both a lyrics id and a chord url are
        hand-picked they already name the song, so it is not second-guessed.
        """
        with self._locks.hold("song", artist, title, album, str(lyrics_id or ""), str(chord_url or "")):
            if lyrics_id and chord_url:
                canonical: dict[str, Any] | None = None
            else:
                # One pin leaves the other half of the song still to find, and
                # that search wants the real artist and title, not the metadata.
                canonical = identity.resolve(
                    self.config, self.lyrics, artist, title, duration, album
                )

            if canonical:
                l_artist = canonical.get("artist") or artist
                l_title = canonical.get("title") or title
                l_album = canonical.get("album") or album
            else:
                l_artist, l_title, l_album = artist, title, album

            lyrics = self.lyrics.lookup(
                l_artist, l_title, l_album, duration, lyrics_id=lyrics_id, refresh=refresh
            )
            # Soundtracks are often filed under the film name on Ultimate Guitar
            # ("Lootera - Zinda"), so hand the canonical album to the chord
            # search as an extra query hint.
            hint_album = l_album or (lyrics or {}).get("album") or album
            chart = self.chords.lookup(
                l_artist, l_title, duration, chord_url=chord_url, album=hint_album, refresh=refresh
            )
            # Align the chart rows to the lyric timings here, in the backend, so
            # the widget follows one monotonic schedule instead of re-deriving it
            # from a greedy scan (which a stray row like "haan" could hijack).
            # The ORIGINAL lyrics are used: once romanised they no longer look
            # like a Devanagari chart.  row_times is added to a copy so the
            # cached chart is not mutated.
            timing = align.row_times(chart, lyrics, duration)
            if not timing:
                # The chart is usually romanised while the lyrics may still be
                # in Devanagari (or the other way round).  The alignment is
                # text-only, so when the first pass finds nothing at all, retry
                # in Latin -- the same thing the widget used to do by matching
                # the on-screen romanised lines.
                timing = align.row_times(chart, romanise_lyrics(lyrics), duration)
            if timing:
                chart = dict(chart)
                chart["row_times"] = timing

        requested = _romanise_request(romanise)
        if should_romanise(str(self.config.get("romanise", "auto")), requested, lyrics, chart):
            return romanise_lyrics(lyrics), chart, True, canonical
        return lyrics, chart, False, canonical

    def song(
        self,
        artist: str,
        title: str,
        album: str = "",
        duration: float = 0.0,
        romanise: Any = None,
        lyrics_id: Any = None,
        chord_url: Any = None,
        refresh: bool = False,
    ) -> dict[str, Any]:
        if not title:
            return {
                "error": "missing title",
                "lyrics": {"source": "none"},
                "chords": {"source": "none", "sections": []},
                "prefs": {},
            }

        lyrics, chart, romanised, canonical = self._prepare_lyrics(
            artist, title, album, duration, romanise, lyrics_id, chord_url, refresh
        )

        # The canonical identity is what the lyrics and the chart were both
        # looked up under.  Report it when it differs from the raw metadata, so
        # the applet can show what the track was understood to be.
        resolved: dict[str, Any] | None = None
        if canonical:
            r_artist = canonical.get("artist") or artist
            r_title = canonical.get("title") or title
            if (r_artist.strip().lower(), r_title.strip().lower()) != (
                (artist or "").strip().lower(),
                (title or "").strip().lower(),
            ):
                resolved = {
                    "artist": r_artist,
                    "title": r_title,
                    "album": canonical.get("album", ""),
                    "source": canonical.get("source", ""),
                }

        names = chart.get("chord_names") or []
        return {
            "query": {"artist": artist, "title": title, "album": album, "duration": duration},
            "lyrics": lyrics,
            "chords": chart,
            "shapes": shapes.shapes_for(names),
            "variations": shapes.variants_for_names(names),
            "transpose": 0,
            "romanised": romanised,
            "resolved": resolved,
            # What the user chose last time: timing offset, transpose, capo and
            # any hand-picked lyrics entry or tab.
            "prefs": self.prefs.get(artist, title),
        }

    def get_lyrics(
        self,
        artist: str,
        title: str,
        album: str = "",
        duration: float = 0.0,
        romanise: Any = None,
        lyrics_id: Any = None,
    ) -> dict[str, Any]:
        lyrics, _chart, _romanised, _canonical = self._prepare_lyrics(
            artist, title, album, duration, romanise, lyrics_id
        )
        return lyrics

    def versions(self, artist: str, title: str, album: str = "", duration: float = 0.0) -> dict[str, Any]:
        """Every lyrics and chart version on offer, for when the pick is wrong.

        Searched under the identity the automatic pick used, so the list is of
        the same song, not of whatever the raw metadata happens to spell.
        """
        artist, title, album = self._known_identity(artist, title, album)
        return {
            "lyrics": self.lyrics.candidates(artist, title, album, duration),
            "charts": self.chords.candidates(artist, title, album=album),
        }

    def get_prefs(self, artist: str, title: str) -> dict[str, Any]:
        return self.prefs.get(artist, title)

    def set_prefs(self, artist: str, title: str, values: dict[str, Any]) -> dict[str, Any]:
        return self.prefs.update(artist, title, values)

    def delete_local(self, artist: str, title: str) -> bool:
        artist, title, _album = self._known_identity(artist, title)
        return self.chords.delete_local(artist, title)

    def paste(self, artist: str, title: str, text: str, fmt: str = "auto") -> dict[str, Any]:
        # Saved under the song's resolved name: lookups run on it, so a chart
        # saved under a decorated video title would never be found again.
        artist, title, _album = self._known_identity(artist, title)
        parsed = self.chords.save_local(artist, title, text, fmt)
        names = parsed.get("chord_names") or []
        return {
            "chords": parsed,
            "shapes": shapes.shapes_for(names),
            "variations": shapes.variants_for_names(names),
        }


# Settings the widget or a script may change over HTTP. Anything that decides
# which program runs (songrec_path), where the service listens (host, port) or
# where it writes is deliberately absent: those are edited in config.json.
MUTABLE_CONFIG = frozenset(
    {
        "contact",
        "chords_sources",
        "ug_enabled",
        "romanise",
        "fingerprint_enabled",
        "fingerprint_seconds",
        "log_level",
        "min_request_interval",
        "negative_ttl_seconds",
        "request_timeout",
    }
)

MAX_BODY = 1024 * 1024
_LOOPBACK_NAMES = {"localhost", "127.0.0.1", "::1"}


class RequestError(Exception):
    """A request the service refuses, with the status to answer."""

    def __init__(self, status: int, message: str) -> None:
        super().__init__(message)
        self.status = status


def _hostname(value: str) -> str:
    """The host part of a ``Host`` header or an origin, without port or brackets."""
    value = value.strip().lower()
    if value.startswith("["):
        return value[1:].split("]", 1)[0]
    return value.rsplit(":", 1)[0] if value.count(":") == 1 else value


def _is_loopback(host: str) -> bool:
    if host in _LOOPBACK_NAMES:
        return True
    try:
        return ipaddress.ip_address(host).is_loopback
    except ValueError:
        return False


class Handler(BaseHTTPRequestHandler):
    server_version = f"chordistd/{__version__}"
    protocol_version = "HTTP/1.1"

    # Silence the default per-request stderr logging; we log our own way.
    def log_message(self, format: str, *args: Any) -> None:
        log.debug("%s - %s", self.address_string(), format % args)

    # ------------------------------------------------------------ helpers

    @property
    def service(self) -> Service:
        return self.server.service  # type: ignore[attr-defined]

    def _send(self, payload: Any, status: int = 200) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        if self.close_connection:
            self.send_header("Connection", "close")
        # No CORS headers, on purpose. The widget's XMLHttpRequest does not need
        # them, and without them a web page in the browser can neither read an
        # answer from this loopback service nor pass a preflight to change it.
        self.end_headers()
        if self.command != "HEAD":
            with contextlib.suppress(BrokenPipeError, ConnectionResetError):
                # The widget drops the connection whenever it refetches or its
                # popup closes; there is nobody left to receive this.
                self.wfile.write(body)

    def _refuse(self, exc: RequestError) -> None:
        """Answer a refused request, then drop the connection.

        A refusal happens before the body is read, so on a kept-alive connection
        those unread bytes would be parsed as the next request.
        """
        self.close_connection = True
        self._send({"error": str(exc)}, status=exc.status)

    def _query(self) -> dict[str, str]:
        return {key: values[0] for key, values in parse_qs(urlparse(self.path).query).items()}

    def _guard(self, writing: bool) -> None:
        """Refuse requests that did not come from this machine's own software.

        A page open in the browser can aim ``fetch()`` at 127.0.0.1, and DNS
        rebinding can make a hostile name resolve there. Both announce
        themselves: a foreign ``Host`` or an ``Origin`` that is not loopback.
        """
        configured = str(self.service.config.get("host") or "127.0.0.1")
        host = self.headers.get("Host")
        if _is_loopback(_hostname(configured)) and host and not _is_loopback(_hostname(host)):
            raise RequestError(403, "unexpected Host header")
        # The widget's own XMLHttpRequest sends neither Origin nor Sec-Fetch-*; a
        # browser always sends at least one when a page makes the request. "null"
        # is what a sandboxed frame or a data: page sends, so it is refused too.
        origin = self.headers.get("Origin")
        if origin:
            parts = urlparse(origin)
            if parts.scheme not in ("http", "https") or not _is_loopback((parts.hostname or "").lower()):
                raise RequestError(403, "cross-origin requests are not allowed")
        if self.headers.get("Sec-Fetch-Site", "none") not in ("none", "same-origin"):
            raise RequestError(403, "cross-site requests are not allowed")
        if writing and not (self.headers.get("Content-Type") or "").lower().startswith("application/json"):
            # JSON-typed requests cannot be sent cross-site without a preflight.
            raise RequestError(415, "send application/json")

    def _body(self) -> dict[str, Any]:
        try:
            length = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            raise RequestError(400, "bad Content-Length") from None
        if length > MAX_BODY:
            raise RequestError(413, "body too large")
        if length <= 0:
            return {}
        try:
            data = json.loads(self.rfile.read(length).decode("utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError):
            raise RequestError(400, "body is not valid JSON") from None
        return data if isinstance(data, dict) else {}

    def _handle(self, routes: dict[str, Callable[[dict[str, str]], Any]], writing: bool = False) -> None:
        path = urlparse(self.path).path.rstrip("/") or "/"
        try:
            self._guard(writing)
            route = routes.get(path)
            if route is None:
                self._send({"error": "not found", "path": path}, status=404)
                return
            self._send(route(self._query()))
        except RequestError as exc:
            self._refuse(exc)
        except (BrokenPipeError, ConnectionResetError):
            # A client that goes away mid-request is normal here: the widget
            # refetches on every track change and its popup closes freely.
            log.debug("%s %s: client disconnected", self.command, path)
        except Exception as exc:
            log.exception("%s %s failed", self.command, path)
            self._send({"error": str(exc)}, status=500)

    # -------------------------------------------------------------- routes

    def _get_routes(self) -> dict[str, Callable[[dict[str, str]], Any]]:
        svc = self.service

        def song(q: dict[str, str]) -> Any:
            return svc.song(
                q.get("artist", ""), q.get("title", ""), q.get("album", ""),
                _as_float(q.get("duration")), q.get("romanise"), q.get("lyrics_id"), q.get("chord_url"),
                refresh=q.get("refresh") == "1",
            )

        def lyrics(q: dict[str, str]) -> Any:
            return svc.get_lyrics(
                q.get("artist", ""), q.get("title", ""), q.get("album", ""),
                _as_float(q.get("duration")), q.get("romanise"), q.get("lyrics_id"),
            )

        def chords(q: dict[str, str]) -> Any:
            return svc.chords.lookup(
                q.get("artist", ""), q.get("title", ""), _as_float(q.get("duration")), q.get("chord_url")
            )

        def versions(q: dict[str, str]) -> Any:
            return svc.versions(
                q.get("artist", ""), q.get("title", ""), q.get("album", ""), _as_float(q.get("duration"))
            )

        def shape_list(q: dict[str, str]) -> Any:
            names = [n.strip() for n in q.get("names", "").split(",") if n.strip()][:64]
            return {"shapes": shapes.shapes_for(names), "variations": shapes.variants_for_names(names)}

        return {
            "/": lambda _q: svc.health(),
            "/api": lambda _q: svc.health(),
            "/api/health": lambda _q: svc.health(),
            "/api/config": lambda _q: svc.config.as_dict(),
            "/api/song": song,
            "/api/lyrics": lyrics,
            "/api/chords": chords,
            "/api/versions": versions,
            "/api/prefs": lambda q: svc.get_prefs(q.get("artist", ""), q.get("title", "")),
            "/api/shapes": shape_list,
            "/api/local": lambda _q: {"items": svc.chords.list_local()},
        }

    def _post_routes(self, body: dict[str, Any]) -> dict[str, Callable[[dict[str, str]], Any]]:
        svc = self.service

        def config(_q: dict[str, str]) -> Any:
            unknown = sorted(set(body) - MUTABLE_CONFIG)
            if unknown:
                raise RequestError(403, f"not changeable over HTTP: {', '.join(unknown)}")
            for key, value in body.items():
                svc.config[key] = value
            svc.config.save()
            return svc.config.as_dict()

        def paste(_q: dict[str, str]) -> Any:
            if not str(body.get("title", "")).strip():
                raise RequestError(400, "a chart needs the title of the song it is for")
            return svc.paste(
                str(body.get("artist", "")), str(body.get("title", "")),
                str(body.get("text", "")), str(body.get("format", "auto")),
            )

        return {
            "/api/paste": paste,
            "/api/config": config,
            "/api/prefs": lambda _q: svc.set_prefs(
                str(body.get("artist", "")), str(body.get("title", "")), body
            ),
        }

    # -------------------------------------------------------------- verbs

    def do_OPTIONS(self) -> None:
        # Answered without CORS headers, so a browser's preflight fails.
        self._send({"ok": True})

    def do_HEAD(self) -> None:
        self.do_GET()

    def do_GET(self) -> None:
        self._handle(self._get_routes())

    def do_POST(self) -> None:
        try:
            self._guard(True)
            body = self._body()
        except RequestError as exc:
            self._refuse(exc)
            return
        self._handle(self._post_routes(body), writing=True)

    def do_DELETE(self) -> None:
        svc = self.service
        self._handle(
            {
                "/api/local": lambda q: {"removed": svc.delete_local(q.get("artist", ""), q.get("title", ""))}
            }
        )


class Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, config: Config) -> None:
        self.service = Service(config)
        super().__init__((str(config.get("host")), int(config.get("port"))), Handler)


def serve(config: Config | None = None) -> None:
    config = config or Config.load()
    server = Server(config)
    host, port = server.server_address[:2]
    if not _is_loopback(_hostname(str(host))):
        log.warning("listening on %s, not loopback: anything that can reach this port can use it", host)
    log.info("chordistd %s listening on http://%s:%s", __version__, host, port)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()

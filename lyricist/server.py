"""The local JSON API the Plasma widget talks to.

Everything slow - HTTP scraping, parsing, disk caching - happens here, behind a
synchronous-looking JSON endpoint, so the QML side never blocks the compositor.
Requests are served on threads, and identical in-flight lookups are collapsed
so a popup opening and closing twice cannot cause a double scrape.
"""

from __future__ import annotations

import json
import logging
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any
from urllib.parse import parse_qs, urlparse

from . import __version__, align, identity, shapes, translit
from .chords import ChordProvider
from .config import Config
from .http import Throttle
from .lyrics import LyricsProvider
from .songprefs import SongPrefs

log = logging.getLogger("lyricist.server")


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


class Service:
    def __init__(self, config: Config) -> None:
        self.config = config
        self.throttle = Throttle(float(config.get("min_request_interval", 0) or 0))
        self.lyrics = LyricsProvider(config, self.throttle)
        self.chords = ChordProvider(config, self.throttle)
        self.prefs = SongPrefs()
        self._locks: dict[tuple[str, ...], threading.Lock] = {}
        self._guard = threading.Lock()

    def _lock(self, *key: str) -> threading.Lock:
        with self._guard:
            return self._locks.setdefault(tuple(key), threading.Lock())

    def health(self) -> dict[str, Any]:
        return {
            "ok": True,
            "version": __version__,
            "port": self.config.get("port"),
            "sources": self.config.get("chords_sources"),
            "ug_enabled": self.config.get("ug_enabled"),
            "contact_configured": bool(self.config.get("contact")),
            "local_charts": len(self.chords.list_local()),
        }

    def _prepare_lyrics(
        self,
        artist: str,
        title: str,
        album: str,
        duration: float,
        romanise: Any,
        lyrics_id: Any = None,
        chord_url: Any = None,
    ) -> tuple[dict[str, Any], dict[str, Any], bool, dict[str, Any] | None]:
        """Lyrics and chart for one song, with the script decision applied.

        The raw streaming metadata is resolved to one canonical identity first,
        and both providers run on that answer, so they can never disagree about
        which song is playing.  A hand-picked lyrics id or chord url already
        names the version, so the song underneath it is not second-guessed.
        """
        with self._lock("song", artist, title, album, str(lyrics_id or ""), str(chord_url or "")):
            if lyrics_id or chord_url:
                canonical: dict[str, Any] | None = None
            else:
                canonical = identity.resolve(
                    self.config, self.lyrics, artist, title, duration, album
                )

            if canonical:
                l_artist = canonical.get("artist") or artist
                l_title = canonical.get("title") or title
                l_album = canonical.get("album") or album
            else:
                l_artist, l_title, l_album = artist, title, album

            lyrics = self.lyrics.lookup(l_artist, l_title, l_album, duration, lyrics_id=lyrics_id)
            # Soundtracks are often filed under the film name on Ultimate Guitar
            # ("Lootera - Zinda"), so hand the canonical album to the chord
            # search as an extra query hint.
            hint_album = l_album or (lyrics or {}).get("album") or album
            chart = self.chords.lookup(
                l_artist, l_title, duration, chord_url=chord_url, album=hint_album
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
    ) -> dict[str, Any]:
        if not title:
            return {
                "error": "missing title",
                "lyrics": {"source": "none"},
                "chords": {"source": "none", "sections": []},
                "prefs": {},
            }

        lyrics, chart, romanised, canonical = self._prepare_lyrics(
            artist, title, album, duration, romanise, lyrics_id, chord_url
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
        """Every lyrics and chart version on offer, for when the pick is wrong."""
        return {
            "lyrics": self.lyrics.candidates(artist, title, album, duration),
            "charts": self.chords.candidates(artist, title),
        }

    def get_prefs(self, artist: str, title: str) -> dict[str, Any]:
        return self.prefs.get(artist, title)

    def set_prefs(self, artist: str, title: str, values: dict[str, Any]) -> dict[str, Any]:
        return self.prefs.update(artist, title, values)

    def paste(self, artist: str, title: str, text: str, fmt: str = "auto") -> dict[str, Any]:
        parsed = self.chords.save_local(artist, title, text, fmt)
        names = parsed.get("chord_names") or []
        return {
            "chords": parsed,
            "shapes": shapes.shapes_for(names),
            "variations": shapes.variants_for_names(names),
        }


class Handler(BaseHTTPRequestHandler):
    server_version = f"lyricistd/{__version__}"
    protocol_version = "HTTP/1.1"

    # Silence the default per-request stderr logging; we log our own way.
    def log_message(self, fmt: str, *args: Any) -> None:  # noqa: A003
        log.debug("%s - %s", self.address_string(), fmt % args)

    # ------------------------------------------------------------ helpers

    def _send(self, payload: Any, status: int = 200) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        # The widget runs from a file:// QML context, so be permissive here.
        # This service only ever listens on loopback.
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
        self.end_headers()
        if self.command != "HEAD":
            try:
                self.wfile.write(body)
            except (BrokenPipeError, ConnectionResetError):
                # The widget drops the connection whenever it refetches or its
                # popup closes; there is nobody left to receive this.
                pass

    def _query(self) -> dict[str, str]:
        parsed = urlparse(self.path)
        return {key: values[0] for key, values in parse_qs(parsed.query).items()}

    def _body(self) -> dict[str, Any]:
        length = int(self.headers.get("Content-Length") or 0)
        if not length:
            return {}
        try:
            return json.loads(self.rfile.read(length).decode("utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError):
            return {}

    @property
    def service(self) -> Service:
        return self.server.service  # type: ignore[attr-defined]

    # -------------------------------------------------------------- verbs

    def do_OPTIONS(self) -> None:  # noqa: N802
        self._send({"ok": True})

    def do_HEAD(self) -> None:  # noqa: N802
        self.do_GET()

    def do_GET(self) -> None:  # noqa: N802
        path = urlparse(self.path).path.rstrip("/") or "/"
        query = self._query()

        try:
            if path in ("/", "/api"):
                self._send(self.service.health())
            elif path == "/api/health":
                self._send(self.service.health())
            elif path == "/api/config":
                self._send(self.service.config.as_dict())
            elif path == "/api/song":
                self._send(
                    self.service.song(
                        query.get("artist", ""),
                        query.get("title", ""),
                        query.get("album", ""),
                        _as_float(query.get("duration")),
                        query.get("romanise"),
                        query.get("lyrics_id"),
                        query.get("chord_url"),
                    )
                )
            elif path == "/api/lyrics":
                self._send(
                    self.service.get_lyrics(
                        query.get("artist", ""),
                        query.get("title", ""),
                        query.get("album", ""),
                        _as_float(query.get("duration")),
                        query.get("romanise"),
                        query.get("lyrics_id"),
                    )
                )
            elif path == "/api/chords":
                self._send(
                    self.service.chords.lookup(
                        query.get("artist", ""),
                        query.get("title", ""),
                        _as_float(query.get("duration")),
                        query.get("chord_url"),
                    )
                )
            elif path == "/api/versions":
                self._send(
                    self.service.versions(
                        query.get("artist", ""),
                        query.get("title", ""),
                        query.get("album", ""),
                        _as_float(query.get("duration")),
                    )
                )
            elif path == "/api/prefs":
                self._send(
                    self.service.get_prefs(query.get("artist", ""), query.get("title", ""))
                )
            elif path == "/api/shapes":
                names = [n for n in query.get("names", "").split(",") if n.strip()]
                self._send({
                    "shapes": shapes.shapes_for(names),
                    "variations": shapes.variants_for_names(names),
                })
            elif path == "/api/local":
                self._send({"items": self.service.chords.list_local()})
            else:
                self._send({"error": "not found", "path": path}, status=404)
        except (BrokenPipeError, ConnectionResetError):
            # A client that goes away mid-request is normal here: the widget
            # refetches on every track change and its popup closes freely.
            log.debug("GET %s: client disconnected", path)
        except Exception as exc:  # noqa: BLE001 - never take the service down
            log.exception("GET %s failed", path)
            self._send({"error": str(exc)}, status=500)

    def do_POST(self) -> None:  # noqa: N802
        path = urlparse(self.path).path.rstrip("/")
        body = self._body()
        try:
            if path == "/api/paste":
                self._send(
                    self.service.paste(
                        body.get("artist", ""),
                        body.get("title", ""),
                        body.get("text", ""),
                        body.get("format", "auto"),
                    )
                )
            elif path == "/api/config":
                for key, value in body.items():
                    self.service.config[key] = value
                self.service.config.save()
                self._send(self.service.config.as_dict())
            elif path == "/api/prefs":
                self._send(
                    self.service.set_prefs(
                        body.get("artist", ""),
                        body.get("title", ""),
                        body,
                    )
                )
            else:
                self._send({"error": "not found", "path": path}, status=404)
        except (BrokenPipeError, ConnectionResetError):
            log.debug("POST %s: client disconnected", path)
        except Exception as exc:  # noqa: BLE001
            log.exception("POST %s failed", path)
            self._send({"error": str(exc)}, status=500)

    def do_DELETE(self) -> None:  # noqa: N802
        path = urlparse(self.path).path.rstrip("/")
        query = self._query()
        try:
            if path == "/api/local":
                removed = self.service.chords.delete_local(query.get("artist", ""), query.get("title", ""))
                self._send({"removed": removed})
            else:
                self._send({"error": "not found", "path": path}, status=404)
        except (BrokenPipeError, ConnectionResetError):
            log.debug("DELETE %s: client disconnected", path)
        except Exception as exc:  # noqa: BLE001
            log.exception("DELETE %s failed", path)
            self._send({"error": str(exc)}, status=500)


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
    log.info("lyricistd %s listening on http://%s:%s", __version__, host, port)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()

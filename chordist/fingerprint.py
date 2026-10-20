# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
#
# SPDX-License-Identifier: MIT

"""Identify the track that is actually playing, from its audio.

The browser's MPRIS metadata is unreliable: it reports the YouTube channel as
the artist and carries video-title decoration.  When a lookup comes up empty,
this module records a few seconds of the default PipeWire sink's monitor and
asks SongRec (an open-source Shazam client) for the canonical artist, title and
album, which the service then uses for a second, clean lookup.

The capture and recognition need no API key.  Results are cached on disk keyed
by the raw artist/title, so a track is only ever fingerprinted once.
"""

from __future__ import annotations

import json
import logging
import os
import shutil
import subprocess
import tempfile
from typing import Any

from .cache import DiskCache, key_for
from .config import Config

log = logging.getLogger("chordist.fingerprint")


class FingerprintError(RuntimeError):
    """Capture or recognition could not produce an identity."""


def _run(argv: list[str], timeout: float) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(
            argv,
            capture_output=True,
            timeout=timeout,
            check=False,
        )
    except FileNotFoundError as exc:
        raise FingerprintError(f"{argv[0]} not found") from exc
    except subprocess.TimeoutExpired as exc:
        raise FingerprintError(f"{argv[0]} timed out") from exc


def default_monitor() -> str:
    """PipeWire monitor source of the current default sink."""
    pactl = shutil.which("pactl")
    if not pactl:
        raise FingerprintError("pactl not found")
    proc = _run([pactl, "get-default-sink"], 5)
    sink = proc.stdout.decode("utf-8", "replace").strip()
    if proc.returncode != 0 or not sink:
        raise FingerprintError("no default sink")
    return f"{sink}.monitor"


def capture(seconds: float, path: str) -> str:
    """Record ``seconds`` of the default sink's monitor into ``path`` (WAV)."""
    recorder = shutil.which("pw-record")
    if not recorder:
        raise FingerprintError("pw-record not found")
    argv = [
        "timeout", "-s", "INT", str(int(seconds)),
        recorder,
        "--target", default_monitor(),
        "--rate", "16000", "--channels", "1", "--format", "s16",
        path,
    ]
    # ``timeout`` intentionally kills the recorder (SIGINT lets it finalise the
    # WAV header), so a non-zero exit here is the expected path.
    _run(argv, seconds + 10)
    if not os.path.exists(path) or os.path.getsize(path) < 4096:
        raise FingerprintError("capture produced no audio")
    return path


def _songrec(config: Config) -> str:
    configured = str(config.get("songrec_path", "") or "").strip()
    if configured and os.path.exists(configured):
        return configured
    found = shutil.which("songrec")
    if not found:
        raise FingerprintError("songrec not installed")
    return found


def _album(track: dict[str, Any]) -> str:
    for section in track.get("sections") or []:
        for meta in section.get("metadata") or []:
            if str(meta.get("title", "")).strip().lower() == "album":
                return str(meta.get("text", "")).strip()
    return ""


def _canonical(data: dict[str, Any]) -> dict[str, Any] | None:
    track = data.get("track") or {}
    title = str(track.get("title") or "").strip()
    if not title:
        return None
    return {
        "artist": str(track.get("subtitle") or "").strip(),
        "title": title,
        "album": _album(track),
        "source": "shazam",
    }


def recognize(wav: str, config: Config) -> dict[str, Any]:
    """Ask SongRec for the song in ``wav``; returns a canonical identity."""
    timeout = float(config.get("fingerprint_timeout", 60) or 60)
    proc = _run([_songrec(config), "recognize", "--json", wav], timeout)
    text = proc.stdout.decode("utf-8", "replace")
    start = text.find("{")
    if start < 0:
        raise FingerprintError("songrec returned no JSON")
    try:
        data = json.loads(text[start:])
    except json.JSONDecodeError as exc:
        raise FingerprintError("songrec returned invalid JSON") from exc
    identity = _canonical(data)
    if not identity:
        raise FingerprintError("no match")
    return identity


def identify(
    config: Config, *parts: object, seconds: float | None = None
) -> dict[str, Any] | None:
    """Canonical identity for the audio playing now, or ``None``.

    Cached by ``parts`` (the raw artist/title) so the capture only happens once
    per track; a miss is cached briefly so a failed recognition can recover.
    """
    if not config.get("fingerprint_enabled", True):
        return None

    full_ttl = int(config.get("fingerprint_ttl_seconds", 30 * 24 * 3600) or 0)
    cache = DiskCache("fingerprint", ttl=full_ttl)
    key = key_for("identify", *parts)
    hit = cache.get(key)
    if isinstance(hit, dict) and "identity" in hit:
        return hit.get("identity") or None

    identity: dict[str, Any] | None = None
    try:
        secs = float(seconds) if seconds is not None else float(config.get("fingerprint_seconds", 6) or 6)
        with tempfile.TemporaryDirectory(prefix="chordist-fp-") as tmp:
            wav = capture(secs, os.path.join(tmp, "capture.wav"))
            identity = recognize(wav, config)
        log.info(
            "fingerprint matched %s - %s",
            identity.get("artist"),
            identity.get("title"),
        )
    except FingerprintError as exc:
        log.info("fingerprint: %s", exc)
        identity = None

    cache.set(key, {"identity": identity}, ttl=full_ttl if identity else 300)
    return identity

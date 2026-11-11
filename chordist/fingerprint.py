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
import signal
import subprocess
import tempfile
from typing import Any

from .cache import DiskCache, key_for
from .config import Config, clamp_seconds

log = logging.getLogger("chordist.fingerprint")


class FingerprintError(RuntimeError):
    """Capture or recognition could not produce an identity."""


def _run(argv: list[str], timeout: float) -> subprocess.CompletedProcess:
    """Run a program to completion, or kill it, and everything it started, when it overstays ``timeout``.

    It gets a session of its own, so the whole group can be killed: ``subprocess.run`` kills only the direct
    child, and the recorder runs behind ``timeout(1)``, whose own death would leave pw-record recording on.
    """
    try:
        proc = subprocess.Popen(
            argv,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            start_new_session=True,
        )
    except FileNotFoundError as exc:
        raise FingerprintError(f"{argv[0]} not found") from exc
    try:
        stdout, stderr = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            proc.kill()
        proc.communicate()
        raise FingerprintError(f"{argv[0]} timed out") from exc
    return subprocess.CompletedProcess(argv, proc.returncode, stdout, stderr)


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
        # SIGINT lets pw-record finish the WAV header; -k 3 makes sure a recorder that ignores it still dies.
        "timeout", "-k", "3", "-s", "INT", str(clamp_seconds(seconds)),
        recorder,
        "--target", default_monitor(),
        "--rate", "16000", "--channels", "1", "--format", "s16",
        path,
    ]
    # ``timeout`` intentionally interrupts the recorder, so a non-zero exit here is the expected path.
    _run(argv, clamp_seconds(seconds) + 10)
    if not os.path.exists(path) or os.path.getsize(path) < 4096:
        raise FingerprintError("capture produced no audio")
    return path


# A systemd user service starts with a bare PATH, and SongRec is mostly installed with cargo or by hand, which
# puts it in one of these two directories rather than in /usr/bin.
EXTRA_SONGREC_DIRS = ("~/.cargo/bin", "~/.local/bin")


def find_songrec(config: Config) -> str | None:
    """The SongRec to run: ``songrec_path`` if it exists, else the first on PATH, ~/.cargo/bin or ~/.local/bin."""
    configured = str(config.get("songrec_path", "") or "").strip()
    if configured and os.path.exists(configured):
        return configured
    found = shutil.which("songrec")
    if found:
        return found
    for directory in EXTRA_SONGREC_DIRS:
        candidate = os.path.join(os.path.expanduser(directory), "songrec")
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate
    return None


def _songrec(config: Config) -> str:
    found = find_songrec(config)
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
        secs = clamp_seconds(seconds if seconds is not None else config.get("fingerprint_seconds", 6))
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

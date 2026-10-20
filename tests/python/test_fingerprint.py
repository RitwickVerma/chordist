# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
#
# SPDX-License-Identifier: MIT

"""Identifying a track from its audio: every external program is faked."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from chordist import fingerprint
from chordist.config import Config


class Done:
    def __init__(self, stdout=b"", returncode=0):
        self.stdout, self.returncode = stdout, returncode


SONGREC = {"track": {"title": "Creep", "subtitle": "Radiohead",
                     "sections": [{"metadata": [{"title": "Album", "text": "Pablo Honey"}]}]}}


@pytest.fixture
def tools(monkeypatch):
    """pactl, pw-record and songrec present; a recording that holds audio."""
    calls: list[list[str]] = []
    state = {"songrec": json.dumps(SONGREC).encode(), "audio": True}

    def which(name):
        return f"/usr/bin/{name}"

    def run(argv, timeout):
        calls.append(list(argv))
        if "get-default-sink" in argv:
            return Done(b"alsa_output.test\n")
        if argv[0] == "timeout":                    # the recorder, wrapped in timeout(1)
            if state["audio"]:
                Path(argv[-1]).write_bytes(b"\0" * 8192)
            return Done()
        if "recognize" in argv:
            return Done(b"noise before json " + state["songrec"])
        raise AssertionError(argv)

    monkeypatch.setattr(fingerprint.shutil, "which", which)
    monkeypatch.setattr(fingerprint, "_run", run)
    tools.calls, tools.state = calls, state
    return tools


def cfg(**kw):
    return Config({"fingerprint_enabled": True, **kw})


def test_a_recognised_track_comes_back_with_artist_title_and_album(tools):
    got = fingerprint.identify(cfg(), "Chan", "Raw Title")
    assert got == {"artist": "Radiohead", "title": "Creep", "album": "Pablo Honey", "source": "shazam"}


def test_it_records_the_default_sinks_monitor_and_nothing_else(tools):
    fingerprint.identify(cfg(fingerprint_seconds=4), "a", "b")
    record = next(c for c in tools.calls if c[0] == "timeout")
    assert "alsa_output.test.monitor" in record and "4" in record
    assert record.index("--rate") < record.index("--channels")


def test_a_hit_is_cached_so_the_audio_is_captured_once(tools):
    fingerprint.identify(cfg(), "a", "b")
    n = len(tools.calls)
    assert fingerprint.identify(cfg(), "a", "b")["title"] == "Creep"
    assert len(tools.calls) == n


def test_a_miss_is_cached_briefly_too(tools):
    tools.state["songrec"] = b'{"matches": []}'
    assert fingerprint.identify(cfg(), "a", "b") is None
    n = len(tools.calls)
    assert fingerprint.identify(cfg(), "a", "b") is None
    assert len(tools.calls) == n


def test_silence_is_not_a_song(tools):
    tools.state["audio"] = False
    assert fingerprint.identify(cfg(), "a", "b") is None


def test_it_does_nothing_when_switched_off(tools):
    assert fingerprint.identify(cfg(fingerprint_enabled=False), "a", "b") is None
    assert tools.calls == []


def test_a_missing_tool_is_a_quiet_miss_not_a_crash(monkeypatch):
    monkeypatch.setattr(fingerprint.shutil, "which", lambda name: None)
    assert fingerprint.identify(cfg(), "a", "b") is None
    with pytest.raises(fingerprint.FingerprintError, match="pactl"):
        fingerprint.default_monitor()


def test_garbage_from_songrec_is_an_error_not_an_identity(tools):
    tools.state["songrec"] = b"not json at all"
    assert fingerprint.identify(cfg(), "a", "b") is None


def test_the_songrec_path_in_the_config_wins_over_path(monkeypatch, tmp_path):
    binary = tmp_path / "songrec"
    binary.write_text("#!/bin/sh")
    monkeypatch.setattr(fingerprint.shutil, "which", lambda name: None)
    assert fingerprint._songrec(Config({"songrec_path": str(binary)})) == str(binary)
    with pytest.raises(fingerprint.FingerprintError, match="not installed"):
        fingerprint._songrec(Config({"songrec_path": str(tmp_path / "nope")}))


def test_a_program_that_is_not_there_or_hangs_is_reported(monkeypatch):
    import subprocess

    def missing(*a, **k):
        raise FileNotFoundError

    monkeypatch.setattr(subprocess, "run", missing)
    with pytest.raises(fingerprint.FingerprintError, match="not found"):
        fingerprint._run(["nope"], 1)

    def hangs(*a, **k):
        raise subprocess.TimeoutExpired("x", 1)

    monkeypatch.setattr(subprocess, "run", hangs)
    with pytest.raises(fingerprint.FingerprintError, match="timed out"):
        fingerprint._run(["slow"], 1)

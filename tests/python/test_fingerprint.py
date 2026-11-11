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


def test_a_program_that_is_not_there_is_reported():
    with pytest.raises(fingerprint.FingerprintError, match="not found"):
        fingerprint._run(["/nonexistent/program"], 1)


def test_a_program_that_hangs_is_killed_with_everything_it_started(tmp_path):
    """timeout(1) -> pw-record: killing only the direct child would leave the recorder running."""
    import os
    import time

    pidfile = tmp_path / "grandchild.pid"
    script = f"sleep 60 & echo $! > {pidfile}; wait"
    with pytest.raises(fingerprint.FingerprintError, match="timed out"):
        fingerprint._run(["sh", "-c", script], 1)
    pid = int(pidfile.read_text())
    for _ in range(50):
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            break
        time.sleep(0.1)
    else:
        os.kill(pid, 9)
        pytest.fail("the grandchild was left running")


def test_the_recording_length_is_clamped_where_it_is_used(tools):
    fingerprint.identify(cfg(), "a", "b", seconds=0)
    record = next(c for c in tools.calls if c[0] == "timeout")
    assert record[:4] == ["timeout", "-k", "3", "-s"] and record[record.index("INT") + 1] == "1"
    tools.calls.clear()
    fingerprint.identify(cfg(), "c", "d", seconds=600)
    record = next(c for c in tools.calls if c[0] == "timeout")
    assert record[record.index("INT") + 1] == "30"


def test_songrec_is_also_looked_for_in_cargo_and_local_bin(monkeypatch, tmp_path):
    monkeypatch.setattr(fingerprint.shutil, "which", lambda name: None)
    monkeypatch.setenv("HOME", str(tmp_path))
    assert fingerprint.find_songrec(Config()) is None
    for directory in (".local/bin", ".cargo/bin"):
        (tmp_path / directory).mkdir(parents=True)
        binary = tmp_path / directory / "songrec"
        binary.write_text("#!/bin/sh")
        binary.chmod(0o755)
        assert fingerprint.find_songrec(Config()) == str(binary)          # ~/.cargo/bin is tried first
    (tmp_path / ".cargo/bin/songrec").chmod(0o644)                         # not executable: skipped
    assert fingerprint.find_songrec(Config()) == str(tmp_path / ".local/bin/songrec")

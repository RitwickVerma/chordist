# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
#
# SPDX-License-Identifier: MIT

"""The command line: what `chordist ...` prints, driven through main()."""

from __future__ import annotations

import json

import pytest

from chordist import __version__, cli


def run(capsys, *argv):
    code = cli.main(list(argv))
    out = capsys.readouterr()
    return code, out.out, out.err


def test_version(capsys):
    with pytest.raises(SystemExit) as exit_:
        cli.main(["--version"])
    assert exit_.value.code == 0
    assert __version__ in capsys.readouterr().out


def test_shapes_prints_a_fingering_per_chord(capsys):
    code, out, _ = run(capsys, "shapes", "C", "F#m", "N.C.")
    assert code == 0
    assert "C: x 3 2 0 1 0" in out
    assert "F#m: 2 4 4 2 2 2" in out
    assert "N.C.: no fingering known" in out


def test_shapes_as_json_and_svg(capsys):
    _, out, _ = run(capsys, "shapes", "Am", "--json")
    assert json.loads(out)["Am"]["frets"] == [-1, 0, 2, 2, 1, 0]
    _, svg, _ = run(capsys, "shapes", "G", "--svg")
    assert svg.startswith("<svg") and svg.count("<svg") == 1


def test_local_charts_can_be_added_listed_and_removed(capsys, tmp_path):
    chart = tmp_path / "song.txt"
    chart.write_text("{title: Song}\n[Am]hello [F]world\n")
    assert run(capsys, "local", "add", "Artist", "Song", str(chart))[1].strip() == "saved Artist - Song"
    listing = run(capsys, "local", "list")[1]
    assert "artist-song" in listing
    assert run(capsys, "local", "path")[1].strip().endswith("chords")
    assert run(capsys, "local", "rm", "Artist", "Song")[1].strip() == "removed"
    assert run(capsys, "local", "rm", "Artist", "Song")[1].strip() == "nothing matched"


def test_local_add_and_rm_say_how_they_are_used(capsys):
    code, _, err = run(capsys, "local", "add", "only-artist")
    assert code == 2 and "usage" in err
    code, _, err = run(capsys, "local", "rm", "x")
    assert code == 2 and "usage" in err


def test_chords_prints_the_chart_over_the_lyrics(capsys, tmp_path):
    chart = tmp_path / "c.txt"
    chart.write_text("{title: Song}\n[Am]hello [F]world\n")
    run(capsys, "local", "add", "Artist", "Song", str(chart))
    code, out, _ = run(capsys, "chords", "Artist", "Song")
    assert code == 0
    assert "Am    F" in out or "Am     F" in out
    assert "hello world" in out
    _, raw, _ = run(capsys, "chords", "Artist", "Song", "--json")
    assert json.loads(raw)["chord_names"] == ["Am", "F"]


def test_lyrics_prints_timed_lines(capsys, monkeypatch):
    from chordist import lyrics

    entry = {"id": 1, "trackName": "Creep", "artistName": "Radiohead", "duration": 238,
             "syncedLyrics": "[00:10.50]When you were here before\n[00:15.00]Couldn't look you in the eye"}
    monkeypatch.setattr(lyrics, "fetch_json", lambda url, **k: entry)
    code, out, _ = run(capsys, "lyrics", "Radiohead", "Creep")
    assert code == 0
    assert "10.50  When you were here before" in out
    assert "source lrclib  synced True" in out


def test_cache_stats_prune_and_clear_cover_every_namespace(capsys):
    from chordist.cache import DiskCache

    DiskCache("lyrics").set("k", {"a": 1})
    stats = run(capsys, "cache")[1]
    for name in ("lyrics", "chords", "identity", "fingerprint"):
        assert f"{name}:" in stats
    assert "lyrics: 1 entries" in stats
    assert "lyrics: pruned 0 entries" in run(capsys, "cache", "prune")[1]
    assert "lyrics: cleared 1 entries" in run(capsys, "cache", "clear")[1]


def test_config_prints_effective_values_and_the_file(capsys):
    code, out, err = run(capsys, "config")
    assert code == 0 and json.loads(out)["port"] == 8788
    assert "config.json" in err


def test_health_and_doctor_report_a_service_that_is_not_running(capsys, monkeypatch):
    from chordist.config import Config

    monkeypatch.setattr(Config, "load", classmethod(lambda cls: cls({"port": 1, "fingerprint_enabled": False})))
    code, _, err = run(capsys, "health")
    assert code == 1 and "is not answering" in err
    code, out, _ = run(capsys, "doctor")
    assert code == 1 and "FAIL" in out and "service answering" in out
    assert "disabled in the config" in out


def test_no_command_means_serve(monkeypatch):
    served = []
    monkeypatch.setattr("chordist.server.serve", lambda config: served.append(config))
    assert cli.main([]) == 0 and len(served) == 1

# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
#
# SPDX-License-Identifier: MIT

"""The move from the pre-2.0 "lyricist" names, run against a throwaway home."""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parents[2] / "tools" / "migrate-from-lyricist.sh"


@pytest.fixture
def home(tmp_path):
    """A home that looks like an installed lyricist 1.x."""
    (tmp_path / ".config" / "lyricist").mkdir(parents=True)
    (tmp_path / ".config" / "lyricist" / "config.json").write_text('{"contact": "me@example.org"}')
    (tmp_path / ".local" / "share" / "lyricist" / "chords").mkdir(parents=True)
    (tmp_path / ".local" / "share" / "lyricist" / "chords" / "a-b.chordpro").write_text("[Am]hi")
    (tmp_path / ".local" / "share" / "lyricist" / "song-prefs.json").write_text('{"a - b": {"capo": 2}}')
    (tmp_path / ".cache" / "lyricist" / "lyrics").mkdir(parents=True)
    (tmp_path / ".cache" / "lyricist" / "lyrics" / "x.json").write_text("{}")
    (tmp_path / ".config" / "systemd" / "user").mkdir(parents=True)
    (tmp_path / ".config" / "systemd" / "user" / "lyricistd.service").write_text("[Service]")
    (tmp_path / ".local" / "bin").mkdir(parents=True)
    (tmp_path / ".local" / "bin" / "lyricistd").write_text("#!/bin/sh")
    (tmp_path / ".local" / "lib" / "lyricist" / "lyricist").mkdir(parents=True)
    return tmp_path


def run(home: Path, mode: str = "data") -> subprocess.CompletedProcess[str]:
    env = {
        "HOME": str(home), "PATH": os.environ["PATH"], "SYSTEMCTL": "true", "RESTART_SHELL": "no",
        "KPT": "true", "XDG_CONFIG_HOME": str(home / ".config"), "XDG_DATA_HOME": str(home / ".local/share"),
        "XDG_CACHE_HOME": str(home / ".cache"),
    }
    return subprocess.run(["bash", str(SCRIPT), mode], env=env, capture_output=True, text=True, check=True)


def test_everything_the_user_owns_moves_over(home):
    run(home)
    assert (home / ".config/chordist/config.json").read_text() == '{"contact": "me@example.org"}'
    assert (home / ".local/share/chordist/chords/a-b.chordpro").read_text() == "[Am]hi"
    assert (home / ".local/share/chordist/song-prefs.json").is_file()
    assert (home / ".cache/chordist/lyrics/x.json").is_file()
    for old in (".config/lyricist", ".local/share/lyricist", ".cache/lyricist"):
        assert not (home / old).exists()


def test_the_old_service_files_are_removed(home):
    run(home)
    assert not (home / ".config/systemd/user/lyricistd.service").exists()
    assert not (home / ".local/bin/lyricistd").exists()
    assert not (home / ".local/lib/lyricist").exists()


def test_running_it_twice_changes_nothing_more(home):
    run(home)
    again = run(home)
    assert again.stdout.strip() == ""
    assert (home / ".config/chordist/config.json").is_file()


def test_a_fresh_install_with_nothing_old_is_a_quiet_no_op(tmp_path):
    assert run(tmp_path).stdout.strip() == ""


def test_an_empty_new_directory_does_not_block_the_move(home):
    (home / ".config/chordist").mkdir()
    run(home)
    assert (home / ".config/chordist/config.json").is_file()


def test_data_in_both_places_is_never_overwritten(home):
    (home / ".config/chordist").mkdir()
    (home / ".config/chordist/config.json").write_text('{"contact": "new"}')
    out = run(home).stdout
    assert (home / ".config/chordist/config.json").read_text() == '{"contact": "new"}'
    assert (home / ".config/lyricist/config.json").is_file()      # the old one is left for the user
    assert "already has content" in out


APPLETSRC = """[Containments][138][Applets][140]
immutability=1
plugin=luisbocanegra.panel.colorizer

[Containments][138][Applets][140][Configuration][General]
panelWidgets=[{"id":144,"name":"com.ritwick.lyricist"}]

[Containments][138][Applets][144]
immutability=1
plugin=com.ritwick.lyricist

[Containments][138][Applets][144][Configuration][General]
defaultTab=chords
fontSizeOffset=4
openAsWindow=true

[Containments][138][Applets][150]
plugin=org.kde.plasma.digitalclock
"""


@pytest.mark.skipif(shutil.which("kwriteconfig6") is None, reason="needs KDE's kwriteconfig6")
def test_the_panel_slot_moves_to_the_new_widget_and_keeps_its_settings(home):
    rc = home / ".config/plasma-org.kde.plasma.desktop-appletsrc"
    rc.write_text(APPLETSRC)
    out = run(home, "panel").stdout
    text = rc.read_text()
    assert "[Containments][138][Applets][144]\nimmutability=1\nplugin=com.ritwick.chordist" in text
    # its settings sit in subgroups of the same group, so they come along untouched
    assert "fontSizeOffset=4" in text and "openAsWindow=true" in text
    # other widgets are left alone, and a backup was taken
    assert "plugin=org.kde.plasma.digitalclock" in text and "plugin=luisbocanegra.panel.colorizer" in text
    assert list(home.glob(".config/plasma-org.kde.plasma.desktop-appletsrc.bak-chordist-*"))
    assert "container 138 applet 144" in out


def test_a_panel_without_the_old_widget_is_left_alone(home):
    rc = home / ".config/plasma-org.kde.plasma.desktop-appletsrc"
    rc.write_text("[Containments][1][Applets][2]\nplugin=org.kde.plasma.digitalclock\n")
    out = run(home, "panel").stdout
    assert rc.read_text() == "[Containments][1][Applets][2]\nplugin=org.kde.plasma.digitalclock\n"
    assert "nothing to migrate" in out
    assert not list(home.glob(".config/*.bak-chordist-*"))


def test_install_moves_the_data_before_the_service_starts_even_under_make_j(home):
    """With -j, make would run the steps at once and start the service on empty defaults."""
    spy = home / "systemctl-spy"
    spy.write_text(
        "#!/bin/sh\n"
        'case "$*" in\n'
        '  *disable*) sleep 1 ;;\n'          # stopping the old service takes a moment
        '  *restart*) if [ -f "$HOME/.config/chordist/config.json" ]; then echo ready; else echo EMPTY; fi'
        ' > "$HOME/at-restart" ;;\n'
        "esac\n"
    )
    spy.chmod(0o755)
    env = {
        "HOME": str(home), "PATH": os.environ["PATH"], "XDG_CONFIG_HOME": str(home / ".config"),
        "XDG_DATA_HOME": str(home / ".local/share"), "XDG_CACHE_HOME": str(home / ".cache"),
    }
    repo = SCRIPT.parents[1]
    subprocess.run(
        ["make", "-j8", "install", f"PREFIX={home}/.local", f"UNIT_DIR={home}/.config/systemd/user",
         f"SYSTEMCTL={spy}", "KPT=true"],
        cwd=repo, env=env, capture_output=True, text=True, check=True,
    )
    assert (home / "at-restart").read_text().strip() == "ready"

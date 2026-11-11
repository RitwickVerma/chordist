# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
#
# SPDX-License-Identifier: MIT

"""What `make install`, `make deps` and the Qt lookups do on a machine that is not the author's."""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
pytestmark = pytest.mark.skipif(shutil.which("make") is None, reason="needs make")


def make(*args: str, env: dict[str, str] | None = None, check: bool = True) -> subprocess.CompletedProcess[str]:
    full = {"PATH": os.environ["PATH"], "HOME": "/nonexistent-home"} | (env or {})
    return subprocess.run(["make", *args], cwd=ROOT, env=full, capture_output=True, text=True, check=check)


@pytest.fixture
def prefix(tmp_path):
    return tmp_path / "pfx"


def install_service(prefix: Path, systemctl: str = "true", **extra: str) -> subprocess.CompletedProcess[str]:
    return make(
        "install-service", f"PREFIX={prefix}", f"UNIT_DIR={prefix}/units", f"SYSTEMCTL={systemctl}",
        env={"XDG_CONFIG_HOME": str(prefix / "cfg"), "XDG_DATA_HOME": str(prefix / "data"), **extra},
    )


def test_the_unit_runs_the_launcher_where_it_was_installed(prefix):
    install_service(prefix)
    unit = (prefix / "units/chordistd.service").read_text()
    assert f"\nExecStart={prefix}/bin/chordistd serve\n" in unit
    assert "%h/.local/bin" not in unit
    shipped = (ROOT / "packaging/chordistd.service").read_text().splitlines()
    installed = unit.splitlines()
    assert [a for a, b in zip(shipped, installed, strict=True) if a != b] == ["ExecStart=%h/.local/bin/chordistd serve"]
    assert (prefix / "units/chordistd.service").stat().st_mode & 0o777 == 0o644


def test_a_percent_sign_in_the_prefix_is_not_a_systemd_specifier(tmp_path):
    prefix = tmp_path / "50%"
    install_service(prefix)
    assert f"ExecStart={tmp_path}/50%%/bin/chordistd serve" in (prefix / "units/chordistd.service").read_text()


def test_a_systemd_that_will_not_answer_leaves_the_install_done_and_says_what_to_run(prefix):
    done = install_service(prefix, systemctl="false")
    assert done.returncode == 0
    assert (prefix / "bin/chordistd").is_file() and (prefix / "units/chordistd.service").is_file()
    assert "false enable --now chordistd.service" in done.stdout


def test_the_widget_is_installed_before_the_service():
    plan = make("-n", "install", "KPT=kpt-stub", "SYSTEMCTL=systemctl-stub").stdout
    assert plan.index("kpt-stub -t Plasma/Applet") < plan.index("install -m 755 bin/chordistd")
    assert "kquitapp6 plasmashell" in plan          # the hint names the fallback for a shell that is not a systemd unit


def test_status_uses_the_systemctl_it_was_given():
    assert "my-systemctl --no-pager" in make("-n", "status", "SYSTEMCTL=my-systemctl").stdout


def test_qt_tools_and_modules_are_taken_from_what_was_given_or_found(tmp_path):
    given = make("-n", "lint-qml", "QT_BIN=/x/bin", "QT_QML=/x/qml").stdout
    assert "/x/bin/qmllint -I /x/qml " in given
    fake = tmp_path / "bin"
    fake.mkdir()
    qtpaths = fake / "qtpaths6"
    qtpaths.write_text(
        "#!/bin/sh\ncase \"$1\" in --binaries-dir) echo /found/bin ;; --query) echo /found/qml ;; esac\n"
    )
    qtpaths.chmod(0o755)
    found = make("-n", "lint-qml", env={"PATH": f"{fake}:{os.environ['PATH']}"}).stdout
    assert "/found/bin/qmllint -I /found/qml " in found


@pytest.mark.parametrize("knows", [True, False])
def test_the_block_scope_switch_is_only_passed_to_a_qmllint_that_has_it(tmp_path, knows):
    qmllint = tmp_path / "qmllint"
    qmllint.write_text(
        "#!/bin/sh\n" + ('echo "  --block-scope-var-declaration <level>"\n' if knows else 'echo "Usage: qmllint"\n')
    )
    qmllint.chmod(0o755)
    plan = make("-n", "lint-qml", f"QT_BIN={tmp_path}", "QT_QML=/q").stdout
    assert ("--block-scope-var-declaration disable" in plan) is knows


OS_RELEASES = {
    "arch": ("arch", "pacman -S --needed", ["kpackage", "pipewire-audio", "libpulse", "kconfig"]),
    "debian": ("debian", "apt install", ["kpackagetool6", "pipewire-bin", "pulseaudio-utils", "libkf6config-bin"]),
    "ubuntu": ("ubuntu\nID_LIKE=debian", "apt install", ["kpackagetool6", "pipewire-bin", "pulseaudio-utils"]),
    "fedora": ("fedora", "dnf install", ["kf6-kpackage", "pipewire-utils", "pulseaudio-utils", "kf6-kconfig"]),
    "opensuse-tumbleweed": ("opensuse-tumbleweed", "zypper install", ["kf6-kpackage", "pipewire-tools", "kf6-kconfig"]),
}


@pytest.fixture
def bare_path(tmp_path):
    """A PATH with only what deps.sh itself needs, so every tool it looks for is missing."""
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    for tool in ("sort", "tr", "id", "cat"):
        shutil.copy(shutil.which(tool), bin_dir / tool)
    return bin_dir


def deps(bare_path: Path, os_id: str, mode: str = "runtime") -> subprocess.CompletedProcess[str]:
    release = bare_path.parent / "os-release"
    release.write_text(f"ID={os_id}\n")
    env = {"PATH": str(bare_path), "HOME": str(bare_path.parent), "DEPS_OS_RELEASE": str(release)}
    return subprocess.run(
        [shutil.which("bash"), str(ROOT / "tools/deps.sh"), mode], env=env, capture_output=True, text=True, check=False
    )


@pytest.mark.parametrize("name", OS_RELEASES)
def test_deps_prints_the_install_line_of_the_distribution_it_runs_on(bare_path, name):
    os_id, installer, packages = OS_RELEASES[name]
    done = deps(bare_path, os_id)
    assert done.returncode == 1                                    # python3 and kpackagetool6 are required
    line = next(ln for ln in done.stdout.splitlines() if installer in ln)
    for package in packages:
        assert package in line.split()


def test_deps_says_where_songrec_comes_from_when_the_distribution_does_not_package_it(bare_path):
    assert "github.com/marin-m/SongRec" in deps(bare_path, "debian").stdout
    assert "github.com/marin-m/SongRec" not in deps(bare_path, "arch").stdout
    assert "songrec" in next(ln for ln in deps(bare_path, "arch").stdout.splitlines() if "pacman" in ln).split()


def test_deps_wants_python_3_12(bare_path):
    (bare_path / "python3").write_text("#!/bin/sh\necho 3.11.4\nexit 1\n")
    (bare_path / "python3").chmod(0o755)
    done = deps(bare_path, "debian")
    assert "needs 3.12 or newer" in done.stdout and done.returncode == 1


def test_deps_dev_also_lists_the_test_and_lint_tools(bare_path):
    out = deps(bare_path, "debian", "dev").stdout
    for tool in ("qt6-declarative-dev-tools", "qml6-module-qttest", "shellcheck", "reuse", "libplasma6"):
        assert tool in out
    assert "uv is not packaged" in out


def test_deps_reports_all_present_when_nothing_is_missing(tmp_path):
    for tool in ("kpackagetool6", "systemctl", "pw-record", "pactl", "kwriteconfig6", "songrec", "python3"):
        stub = tmp_path / tool
        stub.write_text(f"#!/bin/sh\n{'exec ' + sys.executable + ' \"$@\"' if tool == 'python3' else 'exit 0'}\n")
        stub.chmod(0o755)
    shutil.copy(shutil.which("sort"), tmp_path / "sort")
    release = tmp_path / "os-release"
    release.write_text("ID=arch\n")
    env = {"PATH": str(tmp_path), "HOME": str(tmp_path), "DEPS_OS_RELEASE": str(release)}
    done = subprocess.run(
        [shutil.which("bash"), str(ROOT / "tools/deps.sh")], env=env, capture_output=True, text=True, check=False
    )
    assert done.returncode == 0 and done.stdout.strip() == "all present"


def test_the_launcher_finds_an_installed_copy_and_survives_a_missing_home(tmp_path):
    """Neither next to a checkout nor under a prefix: the default ~/.local/lib/chordist, with or without $HOME."""
    launcher = tmp_path / "elsewhere" / "chordistd"
    launcher.parent.mkdir()
    shutil.copy(ROOT / "bin/chordistd", launcher)
    home = tmp_path / "home"
    shutil.copytree(ROOT / "chordist", home / ".local/lib/chordist/chordist", ignore=shutil.ignore_patterns("__pycache__"))
    bash = shutil.which("bash")
    with_home = subprocess.run(
        [bash, str(launcher), "--version"], env={"PATH": os.environ["PATH"], "HOME": str(home)},
        capture_output=True, text=True, check=False,
    )
    assert with_home.returncode == 0 and with_home.stdout.startswith("chordist ")
    no_home = subprocess.run(
        [bash, str(launcher), "--version"], env={"PATH": os.environ["PATH"]}, capture_output=True, text=True, check=False
    )
    assert "unbound variable" not in no_home.stderr

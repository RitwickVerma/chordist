#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
#
# SPDX-License-Identifier: MIT
#
# deps.sh [runtime|dev]
#
# What this machine is missing, and the install line for its distribution. `runtime` is what installing and
# running Chordist needs (`make deps`); `dev` is what the tests and linters need on top (`make deps-dev`).
# The package names were each looked up in the distribution's own file index (pacman -F, apt-file,
# dnf repoquery, zypper search --provides), not guessed. Exit status 1 when something required is missing.
#
# DEPS_QT_BIN names the directory with qmllint and qmltestrunner (the Makefile passes the one it found);
# DEPS_OS_RELEASE replaces /etc/os-release, for the tests.
set -u

mode="${1:-runtime}"
case "$mode" in runtime | dev) ;; *) echo "usage: deps.sh [runtime|dev]" >&2; exit 2 ;; esac

# ---- which distribution --------------------------------------------------------------------------------------
family=""
os_release="${DEPS_OS_RELEASE:-/etc/os-release}"
if [[ -r "$os_release" ]]; then
    # shellcheck disable=SC1090
    ids="$(. "$os_release" && echo "${ID:-} ${ID_LIKE:-}")"
    for id in $ids; do
        case "$id" in
            arch | cachyos | manjaro | endeavouros) family=arch ;;
            debian | ubuntu | linuxmint | pop | kali) family=debian ;;
            fedora | rhel | centos | nobara) family=fedora ;;
            opensuse* | suse | sles) family=suse ;;
            *) continue ;;
        esac
        break
    done
fi

# pkg <tool> -> the package that provides it on this family; empty when it is not packaged.
pkg() {
    case "$family:$1" in
        arch:python3) echo python ;;
        arch:kpackagetool6) echo kpackage ;;
        arch:kwriteconfig6) echo kconfig ;;
        arch:kquitapp6) echo kdbusaddons ;;
        arch:kstart) echo kde-cli-tools ;;
        arch:pw-record) echo pipewire-audio ;;
        arch:pactl) echo libpulse ;;
        arch:songrec) echo songrec ;;
        arch:uv) echo uv ;;
        arch:node) echo nodejs ;;
        arch:shellcheck) echo shellcheck ;;
        arch:reuse) echo reuse ;;
        arch:qmllint | arch:qmltestrunner) echo qt6-declarative ;;
        arch:qml-modules) echo "plasma-workspace libplasma kirigami kcmutils qqc2-desktop-style" ;;

        debian:python3) echo python3 ;;
        debian:kpackagetool6) echo kpackagetool6 ;;
        debian:kwriteconfig6) echo libkf6config-bin ;;
        debian:kquitapp6) echo libkf6dbusaddons-bin ;;
        debian:kstart) echo kde-cli-tools ;;
        debian:pw-record) echo pipewire-bin ;;
        debian:pactl) echo pulseaudio-utils ;;
        debian:node) echo nodejs ;;
        debian:shellcheck) echo shellcheck ;;
        debian:reuse) echo reuse ;;
        debian:qmllint | debian:qmltestrunner) echo "qt6-declarative-dev-tools qml6-module-qttest" ;;
        debian:qml-modules) echo "plasma-workspace libplasma6 qml6-module-org-kde-kirigami qml6-module-org-kde-kcmutils qml6-module-org-kde-desktop" ;;

        fedora:python3) echo python3 ;;
        fedora:kpackagetool6) echo kf6-kpackage ;;
        fedora:kwriteconfig6) echo kf6-kconfig ;;
        fedora:kquitapp6) echo kf6-kdbusaddons ;;
        fedora:kstart) echo kde-cli-tools ;;
        fedora:pw-record) echo pipewire-utils ;;
        fedora:pactl) echo pulseaudio-utils ;;
        fedora:uv) echo uv ;;
        fedora:node) echo nodejs ;;
        fedora:shellcheck) echo ShellCheck ;;
        fedora:reuse) echo reuse ;;
        fedora:qmllint | fedora:qmltestrunner) echo qt6-qtdeclarative-devel ;;
        fedora:qml-modules) echo "plasma-workspace libplasma kf6-kirigami kf6-kcmutils kf6-qqc2-desktop-style" ;;

        suse:python3) echo python3 ;;
        suse:kpackagetool6) echo kf6-kpackage ;;
        suse:kwriteconfig6) echo kf6-kconfig ;;
        suse:kquitapp6) echo kf6-kdbusaddons-tools ;;
        suse:kstart) echo kde-cli-tools6 ;;
        suse:pw-record) echo pipewire-tools ;;
        suse:pactl) echo pulseaudio-utils ;;
        suse:uv) echo python313-uv ;;
        suse:node) echo nodejs-default ;;
        suse:shellcheck) echo ShellCheck ;;
        suse:reuse) echo reuse ;;
        suse:qmllint | suse:qmltestrunner) echo qt6-declarative-tools ;;
        suse:qml-modules) echo "plasma6-workspace qt6-declarative-imports kf6-kirigami-imports kf6-kcmutils-imports kf6-qqc2-desktop-style" ;;
    esac
}

installer() {
    case "$family" in
        arch) echo "sudo pacman -S --needed" ;;
        debian) echo "sudo apt install" ;;
        fedora) echo "sudo dnf install" ;;
        suse) echo "sudo zypper install" ;;
    esac
}

missing_required=0
install_pkgs=()
unpackaged=()

# need <tool> <required|optional> <why>: report it when absent, and remember the package that provides it.
need() {
    local tool="$1" level="$2" why="$3" p
    if command -v "$tool" >/dev/null 2>&1; then
        return
    fi
    echo "missing: $tool ($why${level:+, $level})"
    [[ "$level" = required ]] && missing_required=1
    p="$(pkg "$tool")"
    if [[ -n "$p" ]]; then
        # shellcheck disable=SC2206 # a package list, split on purpose
        install_pkgs+=($p)
    else
        unpackaged+=("$tool")
    fi
}

need_file() {   # a tool that lives outside PATH (Qt's bin directory)
    local path="$1" tool="$2" why="$3" p
    [[ -x "$path" ]] && return
    echo "missing: $path ($why, required)"
    missing_required=1
    p="$(pkg "$tool")"
    # shellcheck disable=SC2206
    [[ -n "$p" ]] && install_pkgs+=($p)
}

# ---- runtime ------------------------------------------------------------------------------------------------
if command -v python3 >/dev/null 2>&1; then
    if ! python3 -c 'import sys; sys.exit(sys.version_info < (3, 12))'; then
        echo "python3 is $(python3 -c 'import platform; print(platform.python_version())'); Chordist needs 3.12 or newer"
        missing_required=1
    fi
else
    need python3 required "the service"
fi
need kpackagetool6 required "installs the widget"
need systemctl required "runs the service (systemd user session)"
need pw-record optional "listens to the audio when a song's metadata is junk"
need pactl optional "finds the default output for that"
need kwriteconfig6 optional "only make migrate-panel, for an old lyricist install"

if ! command -v songrec >/dev/null 2>&1 && [[ ! -x "$HOME/.cargo/bin/songrec" && ! -x "$HOME/.local/bin/songrec" ]]; then
    echo "missing: songrec (identifies a song from its audio, optional)"
    p="$(pkg songrec)"
    if [[ -n "$p" ]]; then
        install_pkgs+=("$p")
    else
        unpackaged+=(songrec)
        echo "  songrec is not packaged for this distribution; see https://github.com/marin-m/SongRec#installation"
        echo "  (cargo install songrec puts it in ~/.cargo/bin, which Chordist looks in)"
    fi
fi

# ---- development --------------------------------------------------------------------------------------------
if [[ "$mode" = dev ]]; then
    need make required "the Makefile"
    need uv required "runs pytest, ruff, vulture and builds the wheel"
    need node required "the JS tests (Node 20 or newer)"
    need shellcheck required "lint-shell"
    need reuse required "lint-reuse"
    qt_bin="${DEPS_QT_BIN:-/usr/lib/qt6/bin}"
    need_file "$qt_bin/qmllint" qmllint "qt6 qmllint"
    need_file "$qt_bin/qmltestrunner" qmltestrunner "qt6 qmltestrunner"
    modules="$(pkg qml-modules)"
    if [[ -n "$modules" ]]; then
        echo "note: qmllint and the components test also need Plasma's and Kirigami's QML modules: $modules"
        # shellcheck disable=SC2206
        install_pkgs+=($modules)
    fi
fi

# ---- the answer ---------------------------------------------------------------------------------------------
if [[ ${#install_pkgs[@]} -eq 0 && ${#unpackaged[@]} -eq 0 && $missing_required -eq 0 ]]; then
    echo "all present"
    exit 0
fi

if [[ -z "$family" ]]; then
    echo "unrecognised distribution (see /etc/os-release): install the tools above with its package manager"
elif [[ ${#install_pkgs[@]} -gt 0 ]]; then
    echo
    echo "$(installer) $(printf '%s\n' "${install_pkgs[@]}" | sort -u | tr '\n' ' ')"
fi
for tool in "${unpackaged[@]}"; do
    case "$tool" in
        uv) echo "uv is not packaged for this distribution: https://docs.astral.sh/uv/getting-started/installation/" ;;
        songrec) ;;
        *) echo "$tool is not packaged for this distribution" ;;
    esac
done
exit "$missing_required"

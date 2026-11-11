#!/usr/bin/env bash
#
# Chordist was called "lyricist" before 2.0 (the widget com.ritwick.lyricist, the
# service lyricistd, ~/.config|.local/share|.cache/lyricist). This moves an
# existing install over to the new names without losing anything.
#
#   migrate-from-lyricist.sh [data]   stop and remove the old service, move your
#                                     config, saved charts, per-song settings and
#                                     caches (idempotent; `make install` runs it)
#   migrate-from-lyricist.sh panel    point the panel at the new widget id, keeping
#                                     its position and every setting. Stops and
#                                     restarts plasmashell, so it is a step you run
#                                     yourself: `make migrate-panel`
#
# Environment: SYSTEMCTL (default "systemctl --user"), PREFIX (default ~/.local),
# UNIT_DIR, KPT (kpackagetool6), KWRITECONFIG, RESTART_SHELL (yes/no) and the XDG_* variables, so a
# test can aim it at a throwaway home.
#
# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
#
# SPDX-License-Identifier: MIT
set -euo pipefail

OLD_ID="com.ritwick.lyricist"
NEW_ID="com.ritwick.chordist"
PREFIX="${PREFIX:-$HOME/.local}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
UNIT_DIR="${UNIT_DIR:-$CONFIG_HOME/systemd/user}"
SYSTEMCTL="${SYSTEMCTL:-systemctl --user}"
KPT="${KPT:-kpackagetool6}"
KWRITECONFIG="${KWRITECONFIG:-kwriteconfig6}"
# "no" leaves plasmashell alone: for tests, which must never stop the real one.
RESTART_SHELL="${RESTART_SHELL:-yes}"

say() { printf '%s\n' "$*"; }

migrate_data() {
    # The old service still holds the port and writes to the old directories.
    if [[ -e "$UNIT_DIR/lyricistd.service" ]]; then
        say "stopping and removing the old service (lyricistd)"
        # shellcheck disable=SC2086  # SYSTEMCTL is a command with its own arguments
        $SYSTEMCTL disable --now lyricistd.service 2>/dev/null || true
        rm -f "$UNIT_DIR/lyricistd.service"
        # shellcheck disable=SC2086
        $SYSTEMCTL daemon-reload || true
    fi
    rm -f "$PREFIX/bin/lyricistd"
    rm -rf "$PREFIX/lib/lyricist"

    local base old new
    for base in "$CONFIG_HOME" "$DATA_HOME" "$CACHE_HOME"; do
        old="$base/lyricist"
        new="$base/chordist"
        [[ -d "$old" ]] || continue
        if [[ -d "$new" ]] && [[ -z "$(ls -A "$new")" ]]; then
            rmdir "$new"
        fi
        if [[ -e "$new" ]]; then
            say "keeping $old: $new already has content (merge by hand if you want both)"
            continue
        fi
        mv "$old" "$new"
        say "moved $old -> $new"
    done
}

# plasmashell has to be stopped while its configuration is edited (it rewrites the file on exit), and it must
# come back whatever happens in between, including a failing kwriteconfig6 or Ctrl-C: a missing panel is worse
# than an unmigrated widget. Where the shell is a systemd user unit (the default since Plasma 5.26, often with
# Restart=always) it is stopped through systemd, or systemd would start it again behind our back.
SHELL_STOPPED=""
SHELL_VIA=""
stop_shell() {
    say "stopping plasmashell (it rewrites its configuration on exit)"
    # shellcheck disable=SC2086
    if $SYSTEMCTL is-active --quiet plasma-plasmashell.service 2>/dev/null; then
        SHELL_VIA=systemd
        # shellcheck disable=SC2086
        $SYSTEMCTL stop plasma-plasmashell.service || true
    else
        SHELL_VIA=kde
        kquitapp6 plasmashell 2>/dev/null || true
    fi
    SHELL_STOPPED=yes
    trap 'start_shell' EXIT
    trap 'start_shell; exit 130' INT TERM
    for _ in $(seq 1 50); do pgrep -x plasmashell >/dev/null || break; sleep 0.2; done
}

start_shell() {
    [[ -n "$SHELL_STOPPED" ]] || return 0
    SHELL_STOPPED=""
    say "starting plasmashell"
    if [[ "$SHELL_VIA" == systemd ]]; then
        # shellcheck disable=SC2086
        $SYSTEMCTL start plasma-plasmashell.service || true
    else
        (kstart plasmashell >/dev/null 2>&1 &)
    fi
}

migrate_panel() {
    local rc="$CONFIG_HOME/plasma-org.kde.plasma.desktop-appletsrc"
    [[ -f "$rc" ]] || { say "no panel configuration at $rc: nothing to migrate"; return 0; }

    # Which applet groups name the old widget: [Containments][N][Applets][M] with plugin=OLD.
    local found
    found="$(python3 - "$rc" "$OLD_ID" <<'PY'
import re, sys
group = None
for line in open(sys.argv[1], encoding="utf-8"):
    line = line.rstrip("\n")
    header = re.fullmatch(r"\[Containments\]\[(\d+)\]\[Applets\]\[(\d+)\]", line)
    if header:
        group = header.groups()
    elif line.startswith("["):
        group = None
    elif group and line == f"plugin={sys.argv[2]}":
        print(*group)
PY
)"
    if [[ -z "$found" ]]; then
        say "the panel does not use $OLD_ID: nothing to migrate"
    else
        # Before anything is stopped: finding out afterwards that the tool is missing leaves the user with no panel.
        if ! command -v "$KWRITECONFIG" >/dev/null 2>&1; then
            say "$KWRITECONFIG not found (libkf6config-bin on Debian and Ubuntu, kf6-kconfig on Fedora and openSUSE): nothing was changed"
            return 1
        fi
        local backup
        backup="$rc.bak-chordist-$(date +%Y%m%d-%H%M%S)"
        if [[ "$RESTART_SHELL" == yes ]]; then
            stop_shell
        fi
        cp -p "$rc" "$backup"
        say "backup: $backup"
        while read -r container applet; do
            "$KWRITECONFIG" --file "$rc" --group Containments --group "$container" --group Applets \
                --group "$applet" --key plugin "$NEW_ID"
            say "panel: container $container applet $applet now uses $NEW_ID"
        done <<<"$found"
        start_shell
    fi
    "$KPT" -t Plasma/Applet -r "$OLD_ID" 2>/dev/null && say "removed the old widget package" || true
}

case "${1:-data}" in
    data) migrate_data ;;
    panel) migrate_panel ;;
    *) say "usage: $0 [data|panel]" >&2; exit 2 ;;
esac

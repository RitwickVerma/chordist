#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: MIT
#
# Render the widget's real QML against the fixture service, headless, and write
# one PNG per scenario into OUT (default: build/shots).
#
#   tests/qml/run.sh [OUT] [scenario ...]
#
# Scenarios: chords ug lefty tab lyrics versions empty. `name@12` renders that scenario with
# the song 12 seconds in, to out/name-t12.png (for the demo animation).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out="${1:-$root/build/shots}"
shift || true
scenarios=("$@")
[[ ${#scenarios[@]} -gt 0 ]] || scenarios=(chords ug lefty tab lyrics versions empty)
port=$((20000 + RANDOM % 20000))
work="$(mktemp -d)"
# Kill the service only if it was started: an unset pid made this `kill 0`, which on an early exit (the shim
# failing, say) killed the caller's whole process group: make, a CI job, the ssh session that ran it.
trap '[[ -z ${svc:-} ]] || kill "$svc" 2>/dev/null; rm -rf "$work"' EXIT

mkdir -p "$out"
failed=0

# The widget uses KDE's i18n(), which only the Plasma shell provides; swap in a
# shim that substitutes %1... so every string still renders.
# shellcheck source=/dev/null
source "$root/tests/qml/harness/shim.sh"
shim_applet "$root" "$work"
cp "$root/tests/qml/harness/Shots.qml" "$work/Shots.qml"

python3 -I "$root/tests/qml/fixture_service.py" "$port" "$work/state" >"$work/service.log" 2>&1 &
svc=$!
for _ in $(seq 1 50); do grep -q '^ready' "$work/service.log" && break; sleep 0.1; done
grep -q '^ready' "$work/service.log" || { cat "$work/service.log"; exit 1; }

for spec in "${scenarios[@]}"; do
    name="${spec%@*}"
    label="$name"
    at=9
    [[ $name == tab ]] && at=3
    if [[ $spec == *@* ]]; then
        at="${spec#*@}"
        label="$name-t$(printf '%02d' "$at")"
    fi
    QT_QUICK_CONTROLS_STYLE="${QT_QUICK_CONTROLS_STYLE:-org.kde.desktop}" QT_QPA_PLATFORM=offscreen timeout 60 qml6 "$work/Shots.qml" -- "$name" "$out/$label.png" "$port" "$at" \
        >"$work/$label.log" 2>&1 && status=0 || status=$?
    if [[ $status -eq 0 && -s "$out/$label.png" ]]; then
        echo "ok    $label"
    else
        echo "FAIL  $label (exit $status)"; failed=1
        # || true: no matching line (grep 1) or more than five (head closing the pipe) must not end the run
        # under set -e and pipefail, before the service log and the remaining shots.
        grep -E "^qml: FAIL|Error|error:" "$work/$label.log" | sort -u | head -5 || true
        tail -n 5 "$work/service.log"
    fi
    grep -E "Error|error:|TypeError|ReferenceError|is not|Cannot" "$work/$label.log" | sort -u | head -8 || true
done
exit "$failed"

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
trap 'kill "${svc:-0}" 2>/dev/null || true; rm -rf "$work"' EXIT

mkdir -p "$out"
failed=0

# The widget uses KDE's i18n(), which only the Plasma shell provides; swap in a
# shim that substitutes %1... so every string still renders.
cp -r "$root/applet" "$work/applet"
cp "$root/tests/qml/harness/i18nshim.js" "$work/applet/contents/ui/"
while IFS= read -r file; do
    sed -i -e 's/\bi18n(/I18N.t(/g' -e '0,/^import QtQuick$/s//import QtQuick\nimport "i18nshim.js" as I18N/' "$file"
done < <(grep -rl 'i18n(' "$work/applet/contents/ui")
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
        grep -E "^qml: FAIL|Error|error:" "$work/$label.log" | sort -u | head -5
        tail -n 5 "$work/service.log"
    fi
    grep -E "Error|error:|TypeError|ReferenceError|is not|Cannot" "$work/$label.log" | sort -u | head -8 || true
done
exit "$failed"

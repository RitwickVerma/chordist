#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: MIT
#
# Render the widget's real QML against the fixture service, headless, and write
# one PNG per scenario into OUT (default: build/shots).
#
#   tests/qml/run.sh [OUT] [scenario ...]
#
# Scenarios: chords ug lefty tab lyrics versions empty
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

for name in "${scenarios[@]}"; do
    at=9
    [[ $name == tab ]] && at=3
    QT_QPA_PLATFORM=offscreen timeout 60 qml6 "$work/Shots.qml" -- "$name" "$out/$name.png" "$port" "$at" \
        >"$work/$name.log" 2>&1 || true
    if [[ -s "$out/$name.png" ]]; then echo "ok    $name"; else echo "FAIL  $name"; sed -n 1,20p "$work/$name.log"; fi
    grep -E "Error|error:|TypeError|ReferenceError|is not|Cannot" "$work/$name.log" | sort -u | head -8 || true
done

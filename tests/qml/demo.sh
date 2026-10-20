#!/usr/bin/env bash
#
# Render the Stage following a song and assemble docs/images/demo.gif.
#
#   tests/qml/demo.sh [OUT.gif]
#
# Uses the same headless harness as `make shots` (a fixture service and the real
# QML), at ten points through a public-domain song, then ffmpeg for the GIF.
#
# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
#
# SPDX-License-Identifier: MIT
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out="${1:-$root/docs/images/demo.gif}"
command -v ffmpeg >/dev/null || { echo "ffmpeg is needed to assemble the GIF" >&2; exit 1; }

frames="$(mktemp -d)"
trap 'rm -rf "$frames"' EXIT

specs=()
for at in 4 7 10 13 16 19 22 25 28 31; do specs+=("ug@$at"); done
"$root/tests/qml/run.sh" "$frames" "${specs[@]}"

mkdir -p "$(dirname "$out")"
ffmpeg -loglevel error -y -framerate 0.9 -pattern_type glob -i "$frames/ug-t*.png" \
    -vf "scale=460:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=96[p];[b][p]paletteuse=dither=bayer:bayer_scale=4" \
    -loop 0 "$out"
echo "$out ($(du -h "$out" | cut -f1))"

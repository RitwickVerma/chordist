#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
#
# SPDX-License-Identifier: MIT
# The `fedora-install` job: `make install` into a throwaway home, then check the layout, run what was installed, and
# uninstall. Run from the repo root with kpackagetool6 and make available. systemctl is stubbed (`true`):
# there is no user manager in a container, and the unit is checked as a file.
set -euo pipefail

home=$(mktemp -d)
export HOME=$home XDG_CONFIG_HOME=$home/.config XDG_DATA_HOME=$home/.local/share XDG_CACHE_HOME=$home/.cache
unset PYTHONPATH CHORDIST_LIB
version=$(cat VERSION)

make install SYSTEMCTL=true

want=(
    "$home/.local/bin/chordistd"
    "$home/.local/lib/chordist/chordist/__init__.py"
    "$home/.local/lib/chordist/chordist/data/guitar-chords.json"
    "$home/.config/systemd/user/chordistd.service"
    "$home/.local/share/icons/hicolor/scalable/apps/chordist.svg"
    "$home/.local/share/plasma/plasmoids/com.ritwick.chordist/metadata.json"
    "$home/.local/share/plasma/plasmoids/com.ritwick.chordist/contents/ui/main.qml"
    "$home/.config/chordist"
    "$home/.local/share/chordist"
)
for path in "${want[@]}"; do
    [ -e "$path" ] || { echo "make install did not create $path" >&2; exit 1; }
done
[ -L "$home/.local/bin/chordist" ]

# The installed launcher, from somewhere that is not the checkout, finds the library under its own prefix.
cd "$home"
[ "$("$home/.local/bin/chordist" --version)" = "chordist $version" ]
"$home/.local/bin/chordist" shapes --help >/dev/null
python3 --version

cd - >/dev/null
make uninstall SYSTEMCTL=true
left=$(find "$home/.local" -name '*chordist*' -not -path "$home/.local/share/chordist" | sort)
[ -z "$left" ] || { echo "make uninstall left behind:" >&2; echo "$left" >&2; exit 1; }
echo "fedora-install: ok"

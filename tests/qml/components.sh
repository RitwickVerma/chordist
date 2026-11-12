#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: MIT
#
# Create every component of the widget (contents/ui/*.qml, ui/config/*.qml, config/config.qml) on the Qt and KDE
# stack that is installed, and fail when one does not load or when loading it prints a warning. This is what catches
# an API that only newer Kirigami or Plasma has: the popup of 2.0.0 was dead on Kirigami 6.13 (Debian 13) while
# every other check, run on the newest stack, passed. See tst_components.qml for what it may skip.
#
#   tests/qml/components.sh            QMLTEST (default qmltestrunner) must be Qt 6's
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# shellcheck source=/dev/null
source "$root/tests/qml/harness/shim.sh"
shim_applet "$root" "$work"

# QML cannot list a directory or read a file, so the test is handed the list, and which of the properties the
# shell hands a component (`applet`, `host`, `config`) each one declares.
{
    echo ".pragma library"
    echo "var files = ["
    while IFS= read -r file; do
        flags=""
        for name in applet host config; do
            if grep -q "^    property var $name\\b" "$work/$file"; then flags="$flags $name: true,"; else flags="$flags $name: false,"; fi
        done
        echo "    { file: \"$file\",$flags },"
    done < <(cd "$work" && ls applet/contents/ui/*.qml applet/contents/ui/config/*.qml applet/contents/config/*.qml)
    echo "]"
} >"$work/files.js"
cp "$root/tests/qml/tst_components.qml" "$work/"

status=0
# The style Plasma itself runs widgets with (qqc2-desktop-style); left to itself Qt picks Fusion, for which Kirigami
# has no platform plugin and says so, a warning no Plasma user ever sees.
QT_QUICK_CONTROLS_STYLE="${QT_QUICK_CONTROLS_STYLE:-org.kde.desktop}" QT_QPA_PLATFORM=offscreen \
    "${QMLTEST:-qmltestrunner}" -input "$work/tst_components.qml" >"$work/out.log" 2>&1 || status=$?
cat "$work/out.log"
# A warning while a component loads (a binding that threw, a property that is not there) is a failure too, except
# for the noise KDE's code makes when there is no session to talk to: no display or window system, no icon theme
# configured (qqc2-desktop-style resolves icons through KIconThemes), no spell-checking dictionary installed (its
# text fields ask Sonnet for one). Each pattern is that and nothing broader (fixed strings, not patterns).
# The last four are libplasma 6.3's (Debian 13) own SpinBox: its background is a Loader, and the control reads
# `item.leftMargin` and the other three before the Loader has an item (SpinBox.qml lines 149 to 152 in 6.3.5),
# which throws once per property while the capo box loads, then binds correctly. Plasma 6.8 does not do it. The
# line numbers are part of the string on purpose: another Plasma's SpinBox is not excused by this.
noise=(
    'kf.windowsystem: Could not find any platform plugin'
    'Failed to create wl_display'
    'QObject::installEventFilter(): Cannot filter events for objects in a different thread'
    'kf.iconthemes: Icon theme "breeze-internal" not found.'
    'kf.sonnet.core: Sonnet: No speller backends available!'
    "qrc:/qt/qml/org/kde/plasma/components/SpinBox.qml:149: TypeError: Cannot read property 'leftMargin' of null"
    "qrc:/qt/qml/org/kde/plasma/components/SpinBox.qml:150: TypeError: Cannot read property 'rightMargin' of null"
    "qrc:/qt/qml/org/kde/plasma/components/SpinBox.qml:151: TypeError: Cannot read property 'topMargin' of null"
    "qrc:/qt/qml/org/kde/plasma/components/SpinBox.qml:152: TypeError: Cannot read property 'bottomMargin' of null"
)
printf '%s\n' "${noise[@]}" >"$work/noise.txt"
if grep -E '^(QWARN|QCRITICAL|QFATAL)' "$work/out.log" | grep -v -F -f "$work/noise.txt" >"$work/warnings.log"; then
    echo "components.sh: loading the components printed warnings:" >&2
    cat "$work/warnings.log" >&2
    status=1
fi
exit "$status"

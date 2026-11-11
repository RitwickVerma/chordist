# shellcheck shell=bash
#
# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
#
# SPDX-License-Identifier: MIT
#
# Sourced by tests/qml/run.sh and tests/qml/components.sh.

# shim_applet ROOT WORK: copy ROOT/applet to WORK/applet with KDE's i18n(), which only the Plasma shell provides,
# swapped for the shim in harness/i18nshim.js, so every string still renders and every file still loads.
shim_applet() {
    local root="$1" work="$2" file
    cp -r "$root/applet" "$work/applet"
    while IFS= read -r file; do
        cp "$root/tests/qml/harness/i18nshim.js" "$(dirname "$file")/"
        sed -i -e 's/\bi18n(/I18N.t(/g' -e '0,/^import QtQuick$/s//import QtQuick\nimport "i18nshim.js" as I18N/' "$file"
    done < <(grep -rl 'i18n(' "$work/applet/contents" --include='*.qml')
}

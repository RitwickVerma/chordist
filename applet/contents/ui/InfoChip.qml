// SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
//
// SPDX-License-Identifier: MIT

import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

// A Kirigami chip that can say more on hover: "Key Am", "Capo 2", "Novice".
// Static unless `clickable` is set; `highlighted` marks it as the one to look at.
//
// `clickable` is ours and `Kirigami.Chip.interactive` is not used by name: that property only exists from
// KDE Frameworks 6.16, and naming it in a binding is a load error on older Kirigami (Debian 13 ships 6.13), which
// takes the whole popup down with it.
Kirigami.Chip {
    id: chip

    property string tip: ""
    property bool highlighted: false
    // Whatever the owner wants back when this chip is found again (a section).
    property var payload: null

    closable: false
    checkable: false
    // Set programmatically: a highlighted chip looks selected without being a toggle.
    checked: highlighted
    property bool clickable: false

    // Chips with a tooltip need hover even when they do nothing on click.
    hoverEnabled: clickable || tip.length > 0
    Accessible.name: tip.length > 0 ? tip : text

    // Where Kirigami has the property, a clickable chip is its interactive one (hover, press feedback). Looked up
    // by name, as a string, so that a Kirigami without it is not an error.
    function syncInteractive() {
        if (typeof chip["interactive"] !== "undefined") chip["interactive"] = chip.clickable
    }
    onClickableChanged: syncInteractive()
    Component.onCompleted: syncInteractive()

    PlasmaComponents3.ToolTip { text: chip.tip; visible: chip.tip.length > 0 && chip.hovered }
}

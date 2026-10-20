// SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
//
// SPDX-License-Identifier: MIT

import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

// A Kirigami chip that can say more on hover: "Key Am", "Capo 2", "Novice".
// Static unless `interactive` is set; `highlighted` marks it as the one to look at.
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
    // Chips with a tooltip need hover even when they do nothing on click.
    hoverEnabled: interactive || tip.length > 0
    Accessible.name: tip.length > 0 ? tip : text

    PlasmaComponents3.ToolTip { text: chip.tip; visible: chip.tip.length > 0 && chip.hovered }
}

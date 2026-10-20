// SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
//
// SPDX-License-Identifier: MIT

import QtQuick
import QtQuick.Controls as QQC
import org.kde.plasma.components as PlasmaComponents3

// A toolbar button that is labelled for screen readers and has a tooltip.
// With an icon it shows only the icon; `tip` (or the text) is what it says.
PlasmaComponents3.ToolButton {
    id: button

    property string tip: ""

    display: icon.name.length > 0 ? QQC.AbstractButton.IconOnly : QQC.AbstractButton.TextOnly
    Accessible.name: tip.length > 0 ? tip : text

    PlasmaComponents3.ToolTip { text: button.tip.length > 0 ? button.tip : button.text }
}

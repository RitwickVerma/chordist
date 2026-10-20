// SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
//
// SPDX-License-Identifier: MIT

import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: scroller

    property string text: ""
    property bool scrolling: true
    property bool scrollingPaused: false
    property real maximumWidth: Kirigami.Units.gridUnit * 12
    property alias color: label.color
    property alias font: label.font
    property alias horizontalAlignment: label.horizontalAlignment

    implicitWidth: Math.min(label.implicitWidth, maximumWidth)
    implicitHeight: label.implicitHeight
    clip: true

    Text {
        id: label
        text: scroller.text
        color: scroller.color
        font: scroller.font
        anchors.verticalCenter: parent.verticalCenter
        x: 0
    }

    readonly property real overflow: Math.max(0, label.implicitWidth - scroller.width)
    readonly property bool needsScroll: scroller.scrolling && overflow > Kirigami.Units.smallSpacing

    onNeedsScrollChanged: if (!needsScroll) label.x = 0

    SequentialAnimation {
        running: scroller.needsScroll && !scroller.scrollingPaused && scroller.visible
        loops: Animation.Infinite
        PauseAnimation { duration: 2000 }
        NumberAnimation {
            target: label
            property: "x"
            to: -scroller.overflow
            duration: Math.max(1500, scroller.overflow * 30)
        }
        PauseAnimation { duration: 1200 }
        NumberAnimation { target: label; property: "x"; to: 0; duration: 500 }
    }
}

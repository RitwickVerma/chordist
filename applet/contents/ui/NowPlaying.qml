// SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
//
// SPDX-License-Identifier: MIT

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import "../js/util.js" as Util

// What is playing, the transport, practice speed and a seekable progress bar.
Item {
    id: header

    property var applet
    property color accentColor: Kirigami.Theme.highlightColor

    readonly property real ratio: applet && applet.lengthSec > 0
        ? Math.max(0, Math.min(1, applet.positionSec / applet.lengthSec)) : 0
    readonly property bool hasPlayer: !!(applet && applet.player)

    implicitHeight: layout.implicitHeight + Kirigami.Units.smallSpacing * 2

    ColumnLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        anchors.leftMargin: Kirigami.Units.largeSpacing
        anchors.rightMargin: Kirigami.Units.largeSpacing
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing

            Rectangle {
                Layout.preferredWidth: Kirigami.Units.iconSizes.large
                Layout.preferredHeight: Kirigami.Units.iconSizes.large
                radius: Kirigami.Units.smallSpacing
                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08)
                clip: true

                Image {
                    id: art
                    anchors.fill: parent
                    source: header.applet ? header.applet.artUrl : ""
                    sourceSize.width: 192
                    sourceSize.height: 192
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: status === Image.Ready
                }
                PlasmaComponents3.Label {
                    anchors.centerIn: parent
                    visible: !art.visible
                    text: "♫"
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.6
                    opacity: 0.5
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    text: header.applet && header.applet.ready ? header.applet.track : i18n("Nothing playing")
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    opacity: 0.7
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    text: {
                        if (!header.applet) return ""
                        var parts = []
                        if (header.applet.artist) parts.push(header.applet.artist)
                        if (header.applet.album) parts.push(header.applet.album)
                        return parts.join("  ·  ")
                    }
                }
            }

            // Practice speed: only offered when the player allows it.
            ToolbarButton {
                visible: !!(header.applet && header.applet.canChangeRate)
                text: header.applet ? Number(header.applet.playbackRate.toFixed(2)) + "×" : ""
                tip: i18n("Playback speed, for slowing a passage down to learn it")
                onClicked: speedMenu.open()

                PlasmaComponents3.Menu {
                    id: speedMenu
                    y: parent.height
                    Repeater {
                        model: [0.5, 0.75, 0.9, 1.0, 1.1, 1.25]
                        delegate: PlasmaComponents3.MenuItem {
                            required property real modelData
                            text: modelData + "×"
                            checkable: true
                            checked: header.applet && Math.abs(header.applet.playbackRate - modelData) < 0.01
                            onTriggered: header.applet.setRate(modelData)
                        }
                    }
                }
            }

            ToolbarButton {
                icon.name: "media-skip-backward"
                tip: i18n("Previous track")
                enabled: header.hasPlayer && header.applet.player.canGoPrevious
                onClicked: header.applet.previousTrack()
            }
            ToolbarButton {
                icon.name: header.applet && header.applet.playing ? "media-playback-pause" : "media-playback-start"
                tip: header.applet && header.applet.playing ? i18n("Pause") : i18n("Play")
                enabled: header.hasPlayer && header.applet.player.canPlay
                onClicked: header.applet.togglePlay()
            }
            ToolbarButton {
                icon.name: "media-skip-forward"
                tip: i18n("Next track")
                enabled: header.hasPlayer && header.applet.player.canGoNext
                onClicked: header.applet.nextTrack()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents3.Label {
                text: Util.time(header.applet ? header.applet.positionSec : 0)
                opacity: 0.6
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }

            Item {
                id: track
                Layout.fillWidth: true
                implicitHeight: Kirigami.Units.gridUnit

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 4
                    radius: 2
                    color: Kirigami.Theme.textColor
                    opacity: 0.15
                }
                // The section being looped, so the practice loop is visible on the bar.
                Rectangle {
                    visible: !!(header.applet && header.applet.loopSpan && header.applet.lengthSec > 0)
                    anchors.verticalCenter: parent.verticalCenter
                    x: visible ? parent.width * header.applet.loopSpan.start / header.applet.lengthSec : 0
                    width: visible ? parent.width * (header.applet.loopSpan.end - header.applet.loopSpan.start) / header.applet.lengthSec : 0
                    height: 8
                    radius: 2
                    color: header.accentColor
                    opacity: 0.3
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.round(parent.width * header.ratio)
                    height: 4
                    radius: 2
                    color: header.accentColor
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: !!(header.applet && header.applet.canSeek && header.applet.lengthSec > 0)
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: function (mouse) {
                        header.applet.seekTo((mouse.x / width) * header.applet.lengthSec)
                    }
                }
            }

            PlasmaComponents3.Label {
                text: Util.time(header.applet ? header.applet.lengthSec : 0)
                opacity: 0.6
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }
        }
    }
}

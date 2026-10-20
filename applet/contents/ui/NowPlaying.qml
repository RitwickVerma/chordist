import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import "../js/util.js" as Util

Item {
    id: header
    property var applet
    property var accentColor: Kirigami.Theme.highlightColor

    readonly property real ratio: applet && applet.lengthSec > 0
        ? Math.max(0, Math.min(1, applet.positionSec / applet.lengthSec))
        : 0

    implicitHeight: layout.implicitHeight + Kirigami.Units.largeSpacing * 2

    ColumnLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.smallSpacing

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
                    text: "\u266b"
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 2
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
                    text: header.applet ? header.applet.artist : ""
                    opacity: 0.75
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    opacity: 0.5
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    text: {
                        if (!header.applet) return ""
                        var parts = []
                        if (header.applet.album) parts.push(header.applet.album)
                        if (header.applet.identity) parts.push(header.applet.identity)
                        return parts.join("  \u00b7  ")
                    }
                }
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Kirigami.Units.largeSpacing

            PlasmaComponents3.ToolButton {
                icon.name: "media-skip-backward"
                enabled: header.applet && header.applet.player && header.applet.player.canGoPrevious
                onClicked: header.applet.previousTrack()
            }
            PlasmaComponents3.ToolButton {
                icon.name: header.applet && header.applet.playing ? "media-playback-pause" : "media-playback-start"
                enabled: header.applet && header.applet.player && header.applet.player.canPlay
                onClicked: header.applet.togglePlay()
            }
            PlasmaComponents3.ToolButton {
                icon.name: "media-skip-forward"
                enabled: header.applet && header.applet.player && header.applet.player.canGoNext
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
                implicitHeight: Math.max(6, Kirigami.Units.smallSpacing)

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 4
                    radius: 2
                    color: Kirigami.Theme.textColor
                    opacity: 0.15
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
                    cursorShape: Qt.PointingHandCursor
                    onClicked: function (mouse) {
                        if (header.applet && header.applet.lengthSec > 0)
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

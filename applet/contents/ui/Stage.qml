import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import "../js/theory.js" as Theory

// The guitar companion's centrepiece: the chord you should be playing right now,
// large, with its fingering, its notes and its place in the key; and the one
// coming next with a countdown, so your hand is already moving when it lands.
Rectangle {
    id: stage

    property var applet
    // Off while another tab is showing.
    property bool active: true

    readonly property string now: applet ? applet.nowChord : ""
    readonly property string next: applet ? applet.nextChord : ""
    readonly property real nextIn: applet ? applet.nextIn : -1
    readonly property var nowShape: now ? applet.voicingFor(now) : null
    readonly property var nextShape: next ? applet.voicingFor(next) : null
    readonly property var tones: now ? Theory.chordTones(now) : []
    readonly property string roman: now && applet ? (applet.romanFor(now) || "") : ""
    readonly property int voicingCount: now && applet ? applet.variantsFor(now).length : 0
    // About to change: the next card lights up for the last second.
    readonly property bool imminent: next.length > 0 && nextIn >= 0 && nextIn < 1.2

    visible: active && !!(applet && applet.showStage && applet.hasChordNames && (now.length > 0 || next.length > 0))
    implicitHeight: visible ? Kirigami.Units.gridUnit * 7.4 : 0
    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.05)

    RowLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.largeSpacing

        // ---- now
        Item {
            Layout.preferredWidth: nowDiagram.implicitWidth
            Layout.fillHeight: true

            ChordDiagram {
                id: nowDiagram
                anchors.centerIn: parent
                showName: false
                zoom: 1.45
                shape: stage.nowShape
                mirrored: !!(stage.applet && stage.applet.leftHanded)
                showFingers: !!(stage.applet && stage.applet.showFingers)
                opacity: stage.now.length > 0 ? 1 : 0.25
            }
            MouseArea {
                anchors.fill: parent
                enabled: stage.voicingCount > 1
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: stage.applet.cycleVoicing(stage.now, 1)
                onWheel: function (wheel) {
                    if (stage.voicingCount > 1) stage.applet.cycleVoicing(stage.now, wheel.angleDelta.y > 0 ? 1 : -1)
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            Item { Layout.fillHeight: true }

            RowLayout {
                spacing: Kirigami.Units.smallSpacing
                PlasmaComponents3.Label {
                    text: stage.now.length > 0 ? stage.now : "–"
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 2.6
                    font.weight: Font.Bold
                    color: Kirigami.Theme.highlightColor
                }
                InfoChip {
                    visible: stage.roman.length > 0
                    Layout.alignment: Qt.AlignVCenter
                    text: stage.roman
                    tip: i18n("This chord's job in the key")
                }
            }
            PlasmaComponents3.Label {
                visible: stage.tones.length > 0
                text: stage.tones.join("  ·  ")
                opacity: 0.8
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                Accessible.name: i18n("Notes: %1", stage.tones.join(", "))
            }
            PlasmaComponents3.Label {
                visible: stage.voicingCount > 1
                text: i18n("Fingering %1 of %2 — click to change",
                           (stage.applet ? (stage.applet.voicingPick[stage.now] || 0) : 0) + 1, stage.voicingCount)
                opacity: 0.5
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }

            Item { Layout.fillHeight: true }

            // Time left on this chord.
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 4
                radius: 2
                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
                visible: stage.next.length > 0

                Rectangle {
                    height: parent.height
                    radius: 2
                    width: parent.width * (stage.applet ? stage.applet.chordProgress : 0)
                    color: stage.imminent ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.highlightColor
                }
            }
            PlasmaComponents3.Label {
                visible: stage.next.length > 0 && stage.nextIn >= 0
                text: stage.now.length > 0
                    ? i18n("%1 in %2 s", stage.next, stage.nextIn.toFixed(1))
                    : i18n("Starts with %1 in %2 s", stage.next, stage.nextIn.toFixed(1))
                opacity: 0.6
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                Layout.topMargin: Kirigami.Units.smallSpacing / 2
            }
        }

        // ---- next
        Rectangle {
            Layout.preferredWidth: nextColumn.implicitWidth + Kirigami.Units.largeSpacing
            Layout.fillHeight: true
            visible: stage.next.length > 0
            radius: Kirigami.Units.smallSpacing
            color: "transparent"
            border.width: stage.imminent ? 2 : 1
            border.color: stage.imminent ? Kirigami.Theme.neutralTextColor
                : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.18)
            Behavior on border.color { ColorAnimation { duration: 150 } }

            ColumnLayout {
                id: nextColumn
                anchors.centerIn: parent
                spacing: 0
                PlasmaComponents3.Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: i18n("NEXT")
                    opacity: 0.5
                    font.pointSize: Kirigami.Theme.smallFont.pointSize * 0.85
                    font.letterSpacing: 1
                }
                ChordDiagram {
                    Layout.alignment: Qt.AlignHCenter
                    zoom: 0.95
                    shape: stage.nextShape
                    mirrored: !!(stage.applet && stage.applet.leftHanded)
                    opacity: stage.imminent ? 1 : 0.75
                }
            }
        }
    }
}

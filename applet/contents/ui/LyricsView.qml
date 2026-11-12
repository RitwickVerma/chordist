// SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
//
// SPDX-License-Identifier: MIT

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import "../js/util.js" as Util

// Synced lyrics, with the line being sung highlighted and, when the database
// has word timings, karaoke-style word colouring.
Item {
    id: view

    property var applet
    property bool follow: true

    readonly property var lines: (applet && applet.lyrics && applet.lyrics.lines) ? applet.lyrics.lines : []
    readonly property bool synced: !!(applet && applet.lyricsSynced)
    readonly property bool hasLyrics: lines.length > 0
    readonly property int activeIndex: applet ? applet.lyricActive : -1
    readonly property int fontDelta: applet ? applet.fontSizeOffset : 0

    // A QML font is a value type: build a fresh one so the size setting applies.
    readonly property font bodyFont: Qt.font({
        family: Kirigami.Theme.defaultFont.family,
        pointSize: Math.max(1, Kirigami.Theme.defaultFont.pointSize + fontDelta)
    })

    function nudge(dy) { list.nudge(dy) }
    function scrollToTop() { list.scrollToTop() }

    FollowList {
        id: list
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        visible: view.hasLyrics
        model: view.lines
        spacing: Kirigami.Units.smallSpacing
        followIndex: view.activeIndex
        follow: view.follow
        playing: !!view.applet && view.applet.playing
        glideMs: 320

        delegate: Item {
            id: row
            required property int index
            required property var modelData
            width: ListView.view.width
            implicitHeight: textItem.implicitHeight + Kirigami.Units.smallSpacing * 2
            height: implicitHeight

            readonly property bool current: index === view.activeIndex
            readonly property bool seekable: view.synced && modelData.t !== null && modelData.t !== undefined

            Rectangle {
                anchors.fill: parent
                radius: Kirigami.Units.smallSpacing / 2
                color: Kirigami.Theme.highlightColor
                opacity: row.current ? 0.16 : 0
                Behavior on opacity { NumberAnimation { duration: 150 } }
            }

            Text {
                id: textItem
                x: Kirigami.Units.smallSpacing
                width: parent.width - Kirigami.Units.smallSpacing * 2
                anchors.verticalCenter: parent.verticalCenter
                wrapMode: Text.Wrap
                textFormat: Text.RichText
                font: view.bodyFont
                text: row.displayText
                color: row.current ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
                opacity: row.current ? 1 : 0.8
            }

            MouseArea {
                anchors.fill: parent
                enabled: row.seekable && !!view.applet && view.applet.canSeek
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: view.applet.seekToLyricTime(row.modelData.t)
            }

            // Word-by-word karaoke for the current line when the database has
            // word timings that actually spell the same line.
            readonly property string displayText: {
                var text = modelData.text || ""
                var words = modelData.words
                if (!row.current || !words || !words.length) return Util.escapeHtml(text)
                var joined = ""
                for (var i = 0; i < words.length; i++) joined += (words[i].text || "")
                if (Util.normalize(joined) !== Util.normalize(text)) return Util.escapeHtml(text)
                var position = view.applet.playbackPosition - view.applet.syncLag
                var sung = Util.colorHex(Kirigami.Theme.highlightColor)
                var pending = Util.colorHex(Kirigami.Theme.textColor)
                var html = ""
                for (var w = 0; w < words.length; w++) {
                    var done = words[w].t !== null && words[w].t !== undefined && words[w].t <= position
                    html += '<span style="color:' + (done ? sung : pending) + '">' + Util.escapeHtml(words[w].text || "") + "</span>"
                }
                return html
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        visible: !view.hasLyrics
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            opacity: 0.75
            text: view.applet && view.applet.loading ? i18n("Looking for lyrics…") : i18n("No lyrics found for this track")
        }
        PasteSheet {
            Layout.fillWidth: true
            Layout.fillHeight: true
            applet: view.applet
            hint: i18n("Nothing found? Paste a chord sheet or lyrics below and it will be saved for this track.")
        }
    }
}

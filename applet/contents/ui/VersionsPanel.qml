import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

/** "This is the wrong version" - pick the lyrics entry or the tab you want.
 *
 * Lyrics databases and tab sites both carry several versions of the same song
 * (album, single, live, acoustic, simplified), and the automatic pick is not
 * always the one somebody wants. This lists everything the service can find and
 * pins the choice for that song.
 */
Item {
    id: panel

    property var applet

    readonly property var lyricsVersions: applet && applet.versions ? (applet.versions.lyrics || []) : []
    readonly property var chartVersions: applet && applet.versions ? (applet.versions.charts || []) : []
    readonly property bool loading: !applet || !applet.versions

    // Charts first: this applet is for playing along, so the tabs are what the
    // chooser is really about; the lyrics entries follow underneath.
    readonly property var rows: {
        var out = []
        for (var j = 0; j < panel.chartVersions.length; j++) {
            var chart = panel.chartVersions[j]
            var bits = []
            if (chart.type) bits.push(chart.type)
            if (chart.version) bits.push(i18n("version %1", chart.version))
            if (chart.tonality) bits.push(chart.tonality)
            if (chart.rating) bits.push("\u2605 " + chart.rating)
            if (chart.votes) bits.push(chart.votes + " " + i18n("votes"))
            out.push({
                kind: "chords",
                item: chart,
                title: (chart.name || i18n("Untitled")) + (chart.artist ? " \u2014 " + chart.artist : ""),
                subtitle: bits.join("  \u00b7  ")
            })
        }
        for (var i = 0; i < panel.lyricsVersions.length; i++) {
            var entry = panel.lyricsVersions[i]
            var detail = []
            if (entry.album) detail.push(entry.album)
            if (entry.duration) detail.push(Math.round(entry.duration) + "s")
            detail.push(entry.synced ? i18n("synced") : i18n("plain"))
            if (entry.instrumental) detail.push(i18n("instrumental"))
            out.push({
                kind: "lyrics",
                item: entry,
                title: (entry.track || i18n("Untitled")) + (entry.artist ? " \u2014 " + entry.artist : ""),
                subtitle: detail.join("  \u00b7  ")
            })
        }
        return out
    }

    Rectangle {
        anchors.fill: parent
        color: Kirigami.Theme.backgroundColor
        opacity: panel.applet ? panel.applet.backgroundOpacity : 1
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: i18n("Other versions")
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            ToolbarButton {
                visible: !!(panel.applet && (panel.applet.pinnedLyricsId || panel.applet.pinnedChordUrl))
                icon.name: "edit-delete"
                tip: i18n("Go back to picking automatically")
                onClicked: if (panel.applet) panel.applet.clearPins()
            }
            ToolbarButton {
                icon.name: "dialog-close"
                tip: i18n("Close")
                onClicked: if (panel.applet) panel.applet.closeVersions()
            }
        }

        // A tab found by hand: paste its Ultimate Guitar address.
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            QQC.TextField {
                id: address
                Layout.fillWidth: true
                placeholderText: i18n("Or paste an Ultimate Guitar tab address\u2026")
                selectByMouse: true
                onAccepted: if (panel.applet && panel.applet.pinChartUrl(text)) text = ""
            }
            PlasmaComponents3.Button {
                text: i18n("Use")
                enabled: /^https:\/\/([a-z0-9-]+\.)?ultimate-guitar\.com\/\S+$/i.test(address.text.trim())
                onClicked: if (panel.applet && panel.applet.pinChartUrl(address.text)) address.text = ""
            }
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            visible: panel.loading
            opacity: 0.7
            wrapMode: Text.WordWrap
            text: i18n("Looking for other versions\u2026")
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            visible: !panel.loading && panel.rows.length === 0
            opacity: 0.6
            wrapMode: Text.WordWrap
            text: i18n("No other versions of this song were found.")
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: panel.rows.length > 0
            clip: true
            model: panel.rows
            boundsBehavior: Flickable.StopAtBounds
            spacing: Kirigami.Units.smallSpacing

            delegate: Item {
                id: row
                width: ListView.view.width
                implicitHeight: content.implicitHeight + Kirigami.Units.smallSpacing * 2
                height: implicitHeight

                readonly property var entry: modelData
                readonly property bool current: entry.kind === "lyrics"
                    ? String(entry.item.id) === String(panel.applet ? panel.applet.pinnedLyricsId : "")
                    : (entry.item.url || "") === (panel.applet ? panel.applet.pinnedChordUrl : "")

                Rectangle {
                    anchors.fill: parent
                    radius: Kirigami.Units.smallSpacing / 2
                    color: Kirigami.Theme.highlightColor
                    opacity: row.current ? 0.16 : (rowMouse.containsMouse ? 0.08 : 0)
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }

                ColumnLayout {
                    id: content
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: Kirigami.Units.smallSpacing
                    spacing: 0

                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: row.entry.title
                        font.weight: row.current ? Font.DemiBold : Font.Normal
                    }
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        opacity: 0.6
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        text: row.current ? i18n("%1  \u00b7  in use", row.entry.subtitle) : row.entry.subtitle
                    }
                }

                // The whole row is the button; a separate control would only add
                // clutter next to a two-line description.
                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: !row.current
                    onClicked: if (panel.applet) panel.applet.chooseVersion(row.entry.kind, row.entry.item)
                }
            }
        }
    }
}

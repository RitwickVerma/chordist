import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import "../js/theory.js" as Theory

// The chart: chords over lyrics, tablature staves, and the strip of fingerings
// for the section being played. Timing, chord state and voicings all come from
// the model; this only draws them and forwards clicks.
Item {
    id: view

    property var applet
    // Highlight and follow the row being played.
    property bool follow: false
    property bool showDiagrams: true

    readonly property var rows: applet ? applet.chartRows : []
    readonly property bool hasChart: rows.length > 0
    readonly property int semitones: applet ? applet.effectiveTranspose : 0
    readonly property bool simplify: applet ? applet.simplifyChords : false
    readonly property var chordNames: applet ? applet.displayChords : []
    readonly property int activeRow: applet ? applet.activeRow : -1
    readonly property int fontDelta: applet ? applet.fontSizeOffset : 0
    readonly property bool tabOnly: !!(applet && applet.chartKind === "tab")

    // A QML font is a value type: mutating a copy of a theme font is thrown away
    // before it reaches the Text, so build a fresh one.
    readonly property font chartFont: Qt.font({
        family: Kirigami.Theme.fixedWidthFont.family,
        pointSize: Math.max(1, Kirigami.Theme.fixedWidthFont.pointSize + fontDelta)
    })
    TextMetrics { id: charMetrics; font: view.chartFont; text: "0" }

    function nudge(dy) { list.nudge(dy) }
    function scrollToTop() { list.scrollToTop() }

    // The chords of the section being played, so the strip shows what is
    // relevant now rather than the first two dozen of the whole song. Kept as
    // an index so the strip only rebuilds when the song moves to a new section.
    readonly property int sectionStart: {
        if (view.activeRow < 0 || !view.rows.length) return -1
        var start = -1
        for (var i = 0; i <= view.activeRow && i < view.rows.length; i++)
            if (view.rows[i].kind === "section") start = i
        return start
    }
    readonly property var sectionChords: {
        if (view.sectionStart < 0) return view.chordNames
        var names = []
        for (var j = view.sectionStart + 1; j < view.rows.length; j++) {
            var row = view.rows[j]
            if (row.kind === "section") break
            for (var k = 0; k < row.chords.length; k++) {
                var name = Theory.chordName(row.chords[k].name, view.semitones, view.simplify)
                if (names.indexOf(name) < 0) names.push(name)
            }
        }
        return names.length >= 2 ? names : view.chordNames
    }

    // Which diagram is called out after a click on a chord name.
    property string highlightChord: ""
    Timer { id: highlightTimer; interval: 2500; onTriggered: view.highlightChord = "" }
    function showChord(name) {
        if (!name) return
        view.highlightChord = name
        var index = view.sectionChords.indexOf(name)
        var item = index < 0 ? null : diagramRow.children[index]
        if (!item) return
        diagramFlick.contentX = Math.max(0, Math.min(diagramFlick.contentWidth - diagramFlick.width,
                                                    item.x - diagramFlick.width / 2 + item.width / 2))
        highlightTimer.restart()
    }
    // Which chord sits under a character of a row's chord line.
    function chordAt(chords, charIndex) {
        var columns = Theory.chordColumns(chords, view.semitones, view.simplify)
        for (var i = 0; i < columns.length; i++)
            if (charIndex >= columns[i].col && charIndex <= columns[i].col + columns[i].len) return columns[i].name
        return ""
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        visible: view.hasChart

        Rectangle {
            id: diagramStrip
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? Kirigami.Units.gridUnit * 4.4 : 0
            // The Stage already draws the fingerings, large; the strip is for when it is off.
            visible: view.showDiagrams && view.chordNames.length > 0 && !view.tabOnly && !(view.applet && view.applet.showStage)
            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.05)

            Flickable {
                id: diagramFlick
                anchors.fill: parent
                anchors.margins: Kirigami.Units.smallSpacing
                contentWidth: diagramRow.width
                contentHeight: height
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                Row {
                    id: diagramRow
                    spacing: Kirigami.Units.largeSpacing
                    Repeater {
                        model: view.sectionChords
                        // One slot per chord showing the voicing in use; the others
                        // wait behind it (click or wheel to cycle, as in the Stage).
                        delegate: Item {
                            id: chordGroup
                            required property string modelData
                            readonly property int variantCount: view.applet ? view.applet.variantsFor(modelData).length : 0

                            visible: variantCount > 0
                            width: visible ? diagram.implicitWidth : 0
                            height: diagramStrip.height - Kirigami.Units.smallSpacing * 2

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: -Kirigami.Units.smallSpacing / 2
                                radius: Kirigami.Units.smallSpacing / 2
                                color: Kirigami.Theme.highlightColor
                                opacity: view.highlightChord === chordGroup.modelData || (view.applet && view.applet.nowChord === chordGroup.modelData) ? 0.22 : 0
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                            }
                            ChordDiagram {
                                id: diagram
                                anchors.fill: parent
                                anchors.bottomMargin: chordGroup.variantCount > 1 ? Kirigami.Units.smallSpacing * 1.4 : 0
                                shape: view.applet ? view.applet.voicingFor(chordGroup.modelData) : null
                                mirrored: !!(view.applet && view.applet.leftHanded)
                            }
                            Row {
                                visible: chordGroup.variantCount > 1
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                spacing: Kirigami.Units.smallSpacing / 2
                                Repeater {
                                    model: chordGroup.variantCount
                                    delegate: Rectangle {
                                        width: Kirigami.Units.smallSpacing
                                        height: width
                                        radius: width / 2
                                        color: Kirigami.Theme.textColor
                                        opacity: index === (view.applet ? (view.applet.voicingPick[chordGroup.modelData] || 0) : 0) ? 1 : 0.3
                                    }
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: chordGroup.variantCount > 1 ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: view.applet.cycleVoicing(chordGroup.modelData, 1)
                                // MouseArea's own wheel signal: WheelHandler has no
                                // `accepted`, and assigning one is a load-time error.
                                onWheel: function (wheel) {
                                    if (chordGroup.variantCount < 2) return
                                    view.applet.cycleVoicing(chordGroup.modelData, wheel.angleDelta.y > 0 ? 1 : -1)
                                    wheel.accepted = true
                                }
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            visible: diagramStrip.visible
            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
        }

        FollowList {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: view.rows
            followIndex: view.activeRow
            follow: view.follow
            holdMs: 4000
            // The reading scroll takes over whenever the view is not following the
            // song: lyric sync off, or a tab, which has no timings to follow.
            readingSpeed: view.applet && view.applet.autoScroll ? view.applet.scrollSpeed : 0

            delegate: Item {
                id: row
                required property int index
                required property var modelData
                width: ListView.view.width
                implicitHeight: content.implicitHeight + Kirigami.Units.smallSpacing * 1.5
                height: implicitHeight

                readonly property var entry: modelData
                readonly property bool isSection: entry.kind === "section"
                readonly property bool isStaff: !!entry.staff
                readonly property bool active: !isSection && index === view.activeRow
                readonly property real rowTime: view.applet ? view.applet.rowTimes[index] : null
                readonly property bool seekable: !isSection && rowTime !== null && rowTime !== undefined

                readonly property var columns: isSection || isStaff || !entry.chords.length ? []
                    : Theory.chordColumns(entry.chords, view.semitones, view.simplify)
                readonly property string chordText: {
                    if (!columns.length) return ""
                    if (entry.instrumental) return columns.map(function (c) { return c.name }).join("    ")
                    return Theory.chordLine(entry.chords, view.semitones, view.simplify)
                }
                // The chord being played right now, drawn on its own letters.
                readonly property int playingChord: view.applet && view.applet.activeChordRow === index
                    ? view.applet.activeChordIndex : -1

                Rectangle {
                    anchors.fill: parent
                    radius: Kirigami.Units.smallSpacing / 2
                    color: Kirigami.Theme.highlightColor
                    opacity: row.active ? 0.14 : 0
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                }

                Column {
                    id: content
                    x: Kirigami.Units.smallSpacing
                    width: parent.width - Kirigami.Units.smallSpacing * 2
                    spacing: 0

                    // Clicking a section name jumps to it.
                    PlasmaComponents3.Label {
                        visible: row.isSection
                        width: parent.width
                        topPadding: row.isSection && row.index > 0 ? Kirigami.Units.smallSpacing : 0
                        text: row.isSection ? row.entry.name : ""
                        font.weight: Font.DemiBold
                        font.pointSize: Math.max(1, Kirigami.Theme.smallFont.pointSize + view.fontDelta)
                        color: Kirigami.Theme.highlightColor
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    // Tablature
                    StaffView {
                        visible: row.isStaff
                        width: parent.width
                        staff: row.isStaff ? row.entry.staff : null
                        font: view.chartFont
                        charWidth: charMetrics.width
                    }

                    // Chord row; the chord being played is marked by a pill behind it.
                    Item {
                        visible: !row.isSection && !row.isStaff && row.chordText.length > 0
                        width: parent.width
                        height: chordRow.implicitHeight

                        Rectangle {
                            visible: row.playingChord >= 0 && row.playingChord < row.columns.length
                            x: visible ? row.columns[row.playingChord].col * charMetrics.width - 2 : 0
                            width: visible ? row.columns[row.playingChord].len * charMetrics.width + 4 : 0
                            height: parent.height
                            radius: Kirigami.Units.smallSpacing / 2
                            color: Kirigami.Theme.highlightColor
                            opacity: 0.35
                        }
                        Text {
                            id: chordRow
                            width: parent.width
                            text: row.chordText
                            font: view.chartFont
                            color: Kirigami.Theme.highlightColor
                            wrapMode: Text.NoWrap
                            elide: Text.ElideRight
                        }
                        // Clicking a chord name brings its diagram into view.
                        MouseArea {
                            anchors.fill: parent
                            enabled: !row.entry.instrumental
                            cursorShape: Qt.PointingHandCursor
                            onClicked: function (mouse) {
                                if (charMetrics.width > 0)
                                    view.showChord(view.chordAt(row.entry.chords, Math.floor(mouse.x / charMetrics.width)))
                            }
                        }
                    }

                    // Lyric line; clicking it sends the song to that line.
                    Text {
                        visible: !row.isSection && !row.isStaff && text.length > 0
                        width: parent.width
                        text: row.isSection || row.isStaff ? "" : (row.entry.lyric || "")
                        font: view.chartFont
                        color: row.active ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
                        opacity: row.active ? 1 : 0.85
                        wrapMode: row.entry.mono ? Text.NoWrap : Text.WrapAnywhere
                        elide: row.entry.mono ? Text.ElideRight : Text.ElideNone
                    }
                }

                // The whole row seeks, below the chord-name clicks above.
                MouseArea {
                    anchors.fill: parent
                    z: -1
                    enabled: row.seekable && !!view.applet
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: view.applet.seekTo(row.rowTime)
                }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        visible: !view.hasChart
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            opacity: 0.75
            text: view.applet && view.applet.loading ? i18n("Looking for chords…") : i18n("No chords found for this track")
        }
        PlasmaComponents3.Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            opacity: 0.5
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            visible: !!view.applet && view.applet.statusMessage === "offline"
            text: i18n("The Chordist service is not running.")
        }
        PasteSheet {
            Layout.fillWidth: true
            Layout.fillHeight: true
            applet: view.applet
            hint: i18n("Paste a chord sheet or tab below (Ultimate Guitar format, ChordPro or plain text), or the address of an Ultimate Guitar tab. It is saved for this track and always wins over the internet.")
        }
    }
}

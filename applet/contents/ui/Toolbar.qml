import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

// Two short rows instead of one long one. The first is what you do to a chart
// while playing it (key, capo, easy chords, text size); the second is how the
// view behaves (follow, scroll, loop) and a menu for everything occasional.
ColumnLayout {
    id: bar

    property var applet
    // The view on show, for "back to top".
    property var view: null
    property bool lyricsTab: false

    readonly property bool hasChords: !!(applet && applet.hasChordNames)
    spacing: 0

    // ---------------------------------------------------------------- chart
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.smallSpacing
        Layout.rightMargin: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing
        visible: bar.hasChords && !bar.lyricsTab

        ToolbarButton {
            text: "−"
            tip: i18n("Transpose down a semitone")
            onClicked: bar.applet.transpose = bar.applet.transpose - 1
        }
        PlasmaComponents3.Label {
            text: !bar.applet || bar.applet.transpose === 0 ? i18n("Key ±0")
                : (bar.applet.transpose > 0 ? i18n("Key +%1", bar.applet.transpose) : i18n("Key %1", bar.applet.transpose))
            horizontalAlignment: Text.AlignHCenter
            Layout.minimumWidth: Kirigami.Units.gridUnit * 3.2
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            MouseArea {
                anchors.fill: parent
                enabled: !!bar.applet && bar.applet.transpose !== 0
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: bar.applet.transpose = 0
            }
            PlasmaComponents3.ToolTip { text: i18n("Transposition. Click to reset."); visible: parent.enabled && hover.hovered }
            HoverHandler { id: hover }
        }
        ToolbarButton {
            text: "+"
            tip: i18n("Transpose up a semitone")
            onClicked: bar.applet.transpose = bar.applet.transpose + 1
        }

        Item { Layout.preferredWidth: Kirigami.Units.smallSpacing }

        PlasmaComponents3.Label {
            text: i18n("Capo")
            font.pointSize: Kirigami.Theme.smallFont.pointSize
        }
        PlasmaComponents3.ComboBox {
            model: ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]
            currentIndex: bar.applet ? bar.applet.capo : 0
            onActivated: bar.applet.capo = index
            Accessible.name: i18n("Capo fret")
        }

        Item { Layout.preferredWidth: Kirigami.Units.smallSpacing }

        ToolbarButton {
            text: i18n("Easy")
            checkable: true
            checked: !!bar.applet && bar.applet.simplifyChords
            onClicked: bar.applet.toggle("simplifyChords")
            tip: i18n("Simplify every chord to an easy shape")
        }
        ToolbarButton {
            text: "A−"
            tip: i18n("Smaller text")
            onClicked: bar.applet.adjustFontSize(-1)
        }
        ToolbarButton {
            text: "A+"
            tip: i18n("Larger text")
            onClicked: bar.applet.adjustFontSize(1)
        }
        Item { Layout.fillWidth: true }
    }

    // ----------------------------------------------------------- lyrics timing
    // Timings from a database drift by a second or two between releases: nudge
    // them, or pull the nearest line onto what is playing now.
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing
        visible: !!(bar.applet && bar.applet.lyrics && bar.lyricsTab)

        PlasmaComponents3.Label {
            text: i18n("Lyrics timing")
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            opacity: 0.6
        }
        ToolbarButton { text: "−0.5"; onClicked: bar.applet.nudgeOffset(-0.5); tip: i18n("Lyrics half a second earlier") }
        PlasmaComponents3.Label {
            text: bar.applet ? bar.applet.offsetLabel : ""
            horizontalAlignment: Text.AlignHCenter
            Layout.preferredWidth: Kirigami.Units.gridUnit * 3
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            opacity: 0.7
        }
        ToolbarButton { text: "+0.5"; onClicked: bar.applet.nudgeOffset(0.5); tip: i18n("Lyrics half a second later") }
        ToolbarButton {
            icon.name: "view-refresh"
            tip: i18n("Line the lyrics up with what is playing now")
            onClicked: bar.applet.syncOffset()
        }
        Item { Layout.fillWidth: true }
    }

    // ----------------------------------------------------------------- view
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.smallSpacing
        Layout.rightMargin: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing
        visible: !!(bar.applet && bar.applet.ready)

        ToolbarButton {
            icon.name: "view-media-lyrics"
            checkable: true
            checked: !!bar.applet && bar.applet.lyricSync
            onClicked: bar.applet.toggle("lyricSync")
            tip: i18n("Follow the song and highlight the line being sung")
        }
        ToolbarButton {
            icon.name: "arrow-down"
            checkable: true
            checked: !!bar.applet && bar.applet.autoScroll
            onClicked: bar.applet.toggle("autoScroll")
            tip: i18n("Scroll the view to keep up with the song")
        }
        PlasmaComponents3.Slider {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 5
            visible: !!bar.applet && bar.applet.autoScroll
            from: 1
            to: 10
            stepSize: 1
            value: bar.applet ? bar.applet.scrollSpeed : 5
            onMoved: bar.applet.setScrollSpeed(value)
            Accessible.name: i18n("Scroll speed")
            PlasmaComponents3.ToolTip { text: i18n("Scroll speed") }
        }
        ToolbarButton {
            icon.name: "go-top"
            tip: i18n("Back to the top of the song")
            onClicked: if (bar.view && bar.view.scrollToTop) bar.view.scrollToTop()
        }

        Item { Layout.fillWidth: true }

        ToolbarButton {
            icon.name: "edit-find"
            tip: i18n("Wrong version? Pick another")
            onClicked: bar.applet.openVersions()
        }
        ToolbarButton {
            icon.name: "view-more-symbolic"
            tip: i18n("More")
            onClicked: more.open()

            PlasmaComponents3.Menu {
                id: more
                y: parent.height

                PlasmaComponents3.MenuItem {
                    text: i18n("Ask again")
                    icon.name: "view-refresh"
                    onTriggered: bar.applet.fetchSong()
                }
                PlasmaComponents3.MenuItem {
                    visible: !!(bar.applet && bar.applet.lyricsNonLatin)
                    height: visible ? implicitHeight : 0
                    text: i18n("Romanise the lyrics")
                    checkable: true
                    checked: !!bar.applet && bar.applet.lyricsRomanised
                    onTriggered: bar.applet.toggleRomanise()
                }
                PlasmaComponents3.MenuSeparator {}
                PlasmaComponents3.MenuItem {
                    text: i18n("Now and next chord stage")
                    checkable: true
                    checked: !!bar.applet && bar.applet.showStage
                    onTriggered: bar.applet.toggle("showStage")
                }
                PlasmaComponents3.MenuItem {
                    text: i18n("Fingering strip (when the stage is off)")
                    checkable: true
                    checked: !!bar.applet && bar.applet.showChordDiagrams
                    onTriggered: bar.applet.toggle("showChordDiagrams")
                }
                PlasmaComponents3.MenuItem {
                    text: i18n("Finger numbers")
                    checkable: true
                    checked: !!bar.applet && bar.applet.showFingers
                    onTriggered: bar.applet.toggle("showFingerNumbers")
                }
                PlasmaComponents3.MenuItem {
                    text: i18n("Left-handed diagrams")
                    checkable: true
                    checked: !!bar.applet && bar.applet.leftHanded
                    onTriggered: bar.applet.toggle("leftHanded")
                }
                PlasmaComponents3.MenuSeparator {}
                PlasmaComponents3.MenuItem {
                    text: i18n("Open in a window")
                    icon.name: "window-new"
                    onTriggered: bar.applet.windowRequested()
                }
            }
        }
    }
}

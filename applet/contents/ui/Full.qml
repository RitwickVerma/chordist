import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

Item {
    id: full

    property var applet

    // Exposed so a test harness (and anything else) can drive the tab.
    property alias currentTab: tabs.currentIndex

    // Plasma builds the popup once and keeps it alive afterwards, so
    // Component.onCompleted is not enough to land on the configured tab. The
    // applet bumps openCount every time the popup or the floating window opens,
    // which puts the tab back on the default (Chords).
    readonly property int openCount: (full.applet && full.applet.openCount !== undefined) ? full.applet.openCount : -1
    // The applet is chord-first: with no lyrics there is no Lyrics tab to land
    // on, so opening always falls through to the Chords tab.
    onOpenCountChanged: {
        var target = full.applet ? full.applet.defaultTabIndex : 0
        if (!full.lyricsAvailable && target === 0) target = 1
        tabs.currentIndex = target
    }

    readonly property bool lyricsAvailable: !!(applet && applet.lyricsAvailable)
    onLyricsAvailableChanged: if (!full.lyricsAvailable && tabs.currentIndex === 0) tabs.currentIndex = 1

    readonly property bool hasChart: !!(applet && applet.chart
        && (applet.chart.sections || []).length > 0)

    readonly property string sourceLabel: {
        if (!applet) return ""
        var parts = []
        if (applet.lyrics && applet.lyrics.source) parts.push("LRCLIB")
        if (applet.chart && applet.chart.source) {
            var source = applet.chart.source
            if (source === "ultimate-guitar") parts.push("Ultimate Guitar")
            else if (source === "local") parts.push(i18n("Saved locally"))
            else if (source !== "none") parts.push(source)
        }
        return parts.join("  \u00b7  ")
    }

    readonly property string message: {
        var value = applet ? applet.statusMessage : ""
        if (value === "offline") return i18n("The Chordist service is not running.")
        if (value === "nothing") return ""
        return value
    }

    // True while a text field has focus (the paste box), so the single-key
    // shortcuts below stand down while somebody is typing.
    readonly property bool typing: {
        var item = Window.activeFocusItem
        return !!(item && item.selectedText !== undefined)
    }

    /** scroll the visible tab, for Up/Down */
    function nudgeView(direction) {
        var view = tabs.currentIndex === 0 ? lyricsView : chordsView
        if (view && view.nudge) view.nudge(direction * Kirigami.Units.gridUnit * 3)
    }

    implicitWidth: Kirigami.Units.gridUnit * 30
    implicitHeight: Kirigami.Units.gridUnit * 26

    // Plasma sizes the popup from these when the representation sits in a
    // layout (as plasmMusic's Full.qml does), so keep them in sync.
    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: implicitHeight
    Layout.minimumWidth: implicitWidth
    Layout.minimumHeight: implicitHeight


    // Backing for the text. The Plasma popup background is translucent (and a
    // glassy theme makes it worse), which washes the lyrics out, so draw our
    // own; the opacity is a setting so it can go back to glass.
    Rectangle {
        anchors.fill: parent
        color: Kirigami.Theme.backgroundColor
        opacity: full.applet ? full.applet.backgroundOpacity : 1
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        NowPlaying {
            applet: full.applet
            Layout.fillWidth: true
        }

        PlasmaComponents3.TabBar {
            id: tabs
            Layout.fillWidth: true
            Component.onCompleted: currentIndex = full.applet ? full.applet.defaultTabIndex : 0

            PlasmaComponents3.TabButton {
                text: i18n("Lyrics")
                visible: full.lyricsAvailable
            }
            PlasmaComponents3.TabButton { text: i18n("Chords") }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.smallSpacing
            Layout.rightMargin: Kirigami.Units.smallSpacing
            Layout.topMargin: Kirigami.Units.smallSpacing
            Layout.bottomMargin: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing
            visible: full.applet ? full.applet.ready : false

            // Transposing and capo mean nothing without a chart, so they come
            // and go with one.
            RowLayout {
                visible: full.hasChart
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents3.ToolButton {
                    text: "\u2212"
                    onClicked: if (full.applet) full.applet.transpose = full.applet.transpose - 1
                }
                PlasmaComponents3.Label {
                    text: {
                        if (!full.applet || full.applet.transpose === 0) return i18n("No transpose")
                        return full.applet.transpose > 0 ? "+" + full.applet.transpose : String(full.applet.transpose)
                    }
                    horizontalAlignment: Text.AlignHCenter
                    Layout.minimumWidth: full.applet && full.applet.transpose !== 0
                        ? Kirigami.Units.gridUnit * 5 : Kirigami.Units.gridUnit * 2
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }
                PlasmaComponents3.ToolButton {
                    text: "+"
                    onClicked: if (full.applet) full.applet.transpose = full.applet.transpose + 1
                }

                Item { Layout.preferredWidth: Kirigami.Units.smallSpacing }

                PlasmaComponents3.Label {
                    text: i18n("Capo")
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }
                PlasmaComponents3.ComboBox {
                    model: ["0", "1", "2", "3", "4", "5", "6", "7"]
                    currentIndex: full.applet ? full.applet.capo : 0
                    onActivated: if (full.applet) full.applet.capo = index
                }

                Item { Layout.preferredWidth: Kirigami.Units.smallSpacing }

                // Text size and the diagram strip: what Ultimate Guitar keeps on
                // the toolbar of every tab. They sit beside transpose and capo
                // because all four only mean something to a chord chart.
                PlasmaComponents3.ToolButton {
                    text: "A\u2212"
                    onClicked: if (full.applet) full.applet.adjustFontSize(-1)
                    PlasmaComponents3.ToolTip {
                        text: i18n("Smaller chord text")
                    }
                }
                PlasmaComponents3.ToolButton {
                    text: "A+"
                    onClicked: if (full.applet) full.applet.adjustFontSize(1)
                    PlasmaComponents3.ToolTip {
                        text: i18n("Larger chord text")
                    }
                }
                PlasmaComponents3.ToolButton {
                    icon.name: "view-grid"
                    checkable: true
                    checked: full.applet ? full.applet.showChordDiagrams : true
                    onClicked: if (full.applet) full.applet.toggleChordDiagrams()
                    PlasmaComponents3.ToolTip {
                        text: i18n("Show the fingerings for this song's chords")
                    }
                }
                // The last two controls UG puts on a tab: an easy-chord switch
                // and the pace of the auto-scroll.
                PlasmaComponents3.ToolButton {
                    text: i18n("Easy")
                    checkable: true
                    checked: full.applet ? full.applet.simplifyChords : false
                    onClicked: if (full.applet) full.applet.toggleSimplifyChords()
                    PlasmaComponents3.ToolTip {
                        text: i18n("Simplify every chord to an easy shape")
                    }
                }
                PlasmaComponents3.Slider {
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 5
                    visible: full.applet ? full.applet.autoScroll : true
                    from: 1
                    to: 10
                    stepSize: 1
                    value: full.applet ? full.applet.scrollSpeed : 5
                    onMoved: if (full.applet) full.applet.setScrollSpeed(value)
                    PlasmaComponents3.ToolTip {
                        text: i18n("Auto-scroll speed")
                    }
                }
            }

            Item { Layout.fillWidth: true }

            PlasmaComponents3.Label {
                text: full.sourceLabel
                opacity: 0.5
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                elide: Text.ElideRight
            }
            PlasmaComponents3.ToolButton {
                icon.name: "edit-find"
                onClicked: if (full.applet) full.applet.openVersions()
                PlasmaComponents3.ToolTip {
                    text: i18n("Wrong version? Pick another")
                }
            }
            PlasmaComponents3.ToolButton {
                icon.name: "view-refresh"
                onClicked: if (full.applet) full.applet.fetchSong()
                PlasmaComponents3.ToolTip {
                    text: i18n("Ask again")
                }
            }
            PlasmaComponents3.ToolButton {
                text: "\u0905\u2192A"
                checkable: true
                checked: full.applet ? full.applet.lyricsRomanised : false
                onClicked: if (full.applet) full.applet.toggleRomanise()
                PlasmaComponents3.ToolTip {
                    text: i18n("Switch the lyrics between their own script and a romanised reading")
                }
            }
            PlasmaComponents3.ToolButton {
                icon.name: "view-media-lyrics"
                checkable: true
                checked: full.applet ? full.applet.lyricSync : true
                onClicked: if (full.applet) full.applet.toggleLyricSync()
                PlasmaComponents3.ToolTip {
                    text: i18n("Follow the song and highlight the line being sung")
                }
            }
            PlasmaComponents3.ToolButton {
                icon.name: "arrow-down"
                checkable: true
                checked: full.applet ? full.applet.autoScroll : true
                onClicked: if (full.applet) full.applet.toggleAutoScroll()
                PlasmaComponents3.ToolTip {
                    text: i18n("Scroll the view to keep up with the song")
                }
            }
            PlasmaComponents3.ToolButton {
                icon.name: "go-top"
                onClicked: {
                    var view = tabs.currentIndex === 0 ? lyricsView : chordsView
                    if (view && view.scrollToTop) view.scrollToTop()
                }
                PlasmaComponents3.ToolTip {
                    text: i18n("Jump back to the top of the song")
                }
            }
            PlasmaComponents3.ToolButton {
                icon.name: "window-new"
                onClicked: if (full.applet) full.applet.toggleWindow()
                PlasmaComponents3.ToolTip {
                    text: i18n("Open in a window of its own, above other windows")
                }
            }
        }

        // Lyrics timing gets its own line: the timings a database hands back
        // drift by a second or two between releases. Nudge them, or press the
        // circular arrow to pull the nearest line onto what is playing now.
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.smallSpacing
            Layout.rightMargin: Kirigami.Units.smallSpacing
            Layout.topMargin: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing
            visible: !!(full.applet && full.applet.ready && full.applet.lyrics
                && tabs.currentIndex === 0)

            PlasmaComponents3.Label {
                text: i18n("Lyrics timing")
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                opacity: 0.5
            }
            PlasmaComponents3.ToolButton {
                text: "\u22120.5"
                onClicked: if (full.applet) full.applet.nudgeOffset(-0.5)
            }
            PlasmaComponents3.Label {
                text: full.applet ? full.applet.offsetLabel : ""
                horizontalAlignment: Text.AlignHCenter
                Layout.preferredWidth: Kirigami.Units.gridUnit * 3
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                opacity: 0.7
            }
            PlasmaComponents3.ToolButton {
                text: "+0.5"
                onClicked: if (full.applet) full.applet.nudgeOffset(0.5)
            }
            PlasmaComponents3.ToolButton {
                text: "\u21bb"
                onClicked: if (full.applet) full.applet.syncOffset()
                PlasmaComponents3.ToolTip {
                    text: i18n("Line the lyrics up with what is playing now")
                }
            }
            Item { Layout.fillWidth: true }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            StackLayout {
                id: stack
                anchors.fill: parent
                currentIndex: tabs.currentIndex

                LyricsView {
                    id: lyricsView
                    applet: full.applet
                    follow: full.applet ? full.applet.lyricSync : true
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                }
                ChordsView {
                    id: chordsView
                    applet: full.applet
                    follow: full.applet ? full.applet.lyricSync : true
                    showDiagrams: full.applet ? full.applet.showChordDiagrams : true
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                }
            }

            VersionsPanel {
                anchors.fill: parent
                visible: !!(full.applet && full.applet.versionsOpen)
                applet: full.applet
            }
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.smallSpacing
            Layout.rightMargin: Kirigami.Units.smallSpacing
            Layout.bottomMargin: Kirigami.Units.smallSpacing
            visible: full.message.length > 0
            text: full.message
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            opacity: 0.6
            font.pointSize: Kirigami.Theme.smallFont.pointSize
        }
    }

    // Keyboard control. Shortcuts are window-scoped, so the same keys work in
    // the panel popup and in the floating window.
    Shortcut {
        sequence: "Space"
        enabled: !full.typing
        onActivated: if (full.applet) full.applet.togglePlay()
    }
    Shortcut {
        sequence: "Left"
        enabled: !full.typing
        onActivated: if (full.applet) full.applet.seekTo(full.applet.positionSec - 5)
    }
    Shortcut {
        sequence: "Right"
        enabled: !full.typing
        onActivated: if (full.applet) full.applet.seekTo(full.applet.positionSec + 5)
    }
    Shortcut {
        sequence: "Up"
        enabled: !full.typing
        onActivated: full.nudgeView(-1)
    }
    Shortcut {
        sequence: "Down"
        enabled: !full.typing
        onActivated: full.nudgeView(1)
    }
    Shortcut {
        sequence: "["
        enabled: !full.typing && full.hasChart
        onActivated: if (full.applet) full.applet.transpose = full.applet.transpose - 1
    }
    Shortcut {
        sequence: "]"
        enabled: !full.typing && full.hasChart
        onActivated: if (full.applet) full.applet.transpose = full.applet.transpose + 1
    }
    Shortcut {
        sequence: "Esc"
        onActivated: if (full.applet) full.applet.closeSelf()
    }
}

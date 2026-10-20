import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

// The popup (and the floating window, which is the same thing in a window).
Item {
    id: full

    property var applet

    // Exposed so a test harness can drive the tab.
    property alias currentTab: tabs.current

    // Plasma builds the popup once and keeps it alive, so Component.onCompleted
    // is not enough to land on the configured tab: the model bumps openCount
    // each time the popup or the window opens.
    readonly property int openCount: applet ? applet.openCount : -1
    onOpenCountChanged: tabs.current = full.defaultTab()
    function defaultTab() {
        var target = applet ? applet.defaultTabIndex : 1
        return !full.lyricsAvailable && target === 0 ? 1 : target
    }
    Component.onCompleted: tabs.current = defaultTab()

    readonly property bool lyricsAvailable: !!(applet && applet.lyricsAvailable)
    onLyricsAvailableChanged: if (!lyricsAvailable && tabs.current === 0) tabs.current = 1
    readonly property bool hasChart: !!(applet && applet.chordsAvailable)
    readonly property bool typing: {
        var item = Window.activeFocusItem
        return !!item && ("selectedText" in item)
    }
    readonly property var activeView: tabs.current === 0 ? lyricsView : chordsView

    readonly property string sourceLabel: {
        if (!applet) return ""
        var parts = []
        if (applet.lyrics && applet.lyrics.source) parts.push("LRCLIB")
        if (applet.chart && applet.chart.source) {
            const source = applet.chart.source
            if (source === "ultimate-guitar") parts.push("Ultimate Guitar")
            else if (source === "local") parts.push(i18n("Saved locally"))
            else if (source !== "none") parts.push(source)
        }
        return parts.join("  ·  ")
    }
    readonly property string message: {
        var value = applet ? applet.statusMessage : ""
        if (value === "offline") return i18n("The Chordist service is not running.")
        return value === "nothing" ? "" : value
    }

    implicitWidth: Kirigami.Units.gridUnit * 32
    implicitHeight: Kirigami.Units.gridUnit * 36
    // The popup is sized from these when the representation sits in a layout.
    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: implicitHeight
    Layout.minimumWidth: Kirigami.Units.gridUnit * 22
    Layout.minimumHeight: Kirigami.Units.gridUnit * 20

    // Our own backing: the Plasma popup background is translucent (and a glassy
    // theme makes it worse), which washes the text out. The opacity is a setting.
    Rectangle {
        anchors.fill: parent
        color: Kirigami.Theme.backgroundColor
        opacity: full.applet ? full.applet.backgroundOpacity : 1
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        NowPlaying { applet: full.applet; Layout.fillWidth: true }

        InfoStrip {
            applet: full.applet
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.leftMargin: Kirigami.Units.largeSpacing
            Layout.rightMargin: Kirigami.Units.largeSpacing
            Layout.bottomMargin: Kirigami.Units.smallSpacing
        }

        // Two tabs: Lyrics (when there are some) and the chart.
        RowLayout {
            id: tabs
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.smallSpacing
            spacing: 0
            property int current: 1

            Repeater {
                model: [
                    { index: 0, text: i18n("Lyrics"), shown: full.lyricsAvailable },
                    { index: 1, text: full.applet && full.applet.chartKind === "tab" ? i18n("Tab") : i18n("Chords"), shown: true }
                ]
                delegate: PlasmaComponents3.AbstractButton {
                    id: tab
                    required property var modelData
                    visible: modelData.shown
                    checked: tabs.current === modelData.index
                    onClicked: tabs.current = modelData.index
                    leftPadding: Kirigami.Units.largeSpacing
                    rightPadding: Kirigami.Units.largeSpacing
                    topPadding: Kirigami.Units.smallSpacing
                    bottomPadding: Kirigami.Units.smallSpacing
                    Accessible.role: Accessible.PageTab
                    contentItem: PlasmaComponents3.Label {
                        text: tab.modelData.text
                        font.weight: tab.checked ? Font.DemiBold : Font.Normal
                        opacity: tab.checked ? 1 : 0.65
                    }
                    background: Rectangle {
                        color: tab.hovered ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.06) : "transparent"
                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: 2
                            color: Kirigami.Theme.highlightColor
                            visible: tab.checked
                        }
                    }
                }
            }
            Item { Layout.fillWidth: true }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
        }

        Stage {
            applet: full.applet
            active: tabs.current === 1
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: visible ? implicitHeight : 0
        }

        SectionBar {
            applet: full.applet
            active: tabs.current === 1
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.leftMargin: Kirigami.Units.smallSpacing
            Layout.rightMargin: Kirigami.Units.smallSpacing
            Layout.topMargin: Kirigami.Units.smallSpacing
        }

        Toolbar {
            applet: full.applet
            view: full.activeView
            lyricsTab: tabs.current === 0
            // A nested layout would otherwise soak up the height the song view needs.
            Layout.fillHeight: false
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.smallSpacing / 2
            Layout.bottomMargin: Kirigami.Units.smallSpacing / 2
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            StackLayout {
                anchors.fill: parent
                currentIndex: tabs.current

                LyricsView {
                    id: lyricsView
                    applet: full.applet
                    follow: full.applet ? full.applet.lyricSync : true
                }
                ChordsView {
                    id: chordsView
                    applet: full.applet
                    // A tab has no timings to follow; the reading scroll handles it.
                    follow: !!full.applet && full.applet.lyricSync && full.applet.chartKind !== "tab"
                    showDiagrams: full.applet ? full.applet.showChordDiagrams : true
                }
            }

            VersionsPanel {
                anchors.fill: parent
                visible: !!(full.applet && full.applet.versionsOpen)
                applet: full.applet
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.largeSpacing
            Layout.rightMargin: Kirigami.Units.largeSpacing
            Layout.bottomMargin: Kirigami.Units.smallSpacing
            visible: full.message.length > 0 || full.sourceLabel.length > 0
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: full.message.length > 0 ? full.message : full.sourceLabel
                opacity: 0.55
                elide: Text.ElideRight
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }
            PlasmaComponents3.Label {
                visible: !!(full.applet && full.applet.loading)
                text: i18n("Looking…")
                opacity: 0.55
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }
        }
    }

    // Keyboard control. Shortcuts are window-scoped, so the same keys work in
    // the panel popup and in the floating window.
    Shortcut { sequence: "Space"; enabled: !full.typing; onActivated: if (full.applet) full.applet.togglePlay() }
    Shortcut { sequence: "Left"; enabled: !full.typing; onActivated: if (full.applet) full.applet.seekTo(full.applet.positionSec - 5) }
    Shortcut { sequence: "Right"; enabled: !full.typing; onActivated: if (full.applet) full.applet.seekTo(full.applet.positionSec + 5) }
    Shortcut { sequence: "Up"; enabled: !full.typing; onActivated: full.activeView.nudge(-Kirigami.Units.gridUnit * 3) }
    Shortcut { sequence: "Down"; enabled: !full.typing; onActivated: full.activeView.nudge(Kirigami.Units.gridUnit * 3) }
    Shortcut { sequence: "["; enabled: !full.typing && full.hasChart; onActivated: full.applet.transpose = full.applet.transpose - 1 }
    Shortcut { sequence: "]"; enabled: !full.typing && full.hasChart; onActivated: full.applet.transpose = full.applet.transpose + 1 }
    Shortcut { sequence: "L"; enabled: !full.typing && full.hasChart; onActivated: full.applet.toggleLoopHere() }
    Shortcut { sequence: "Esc"; onActivated: if (full.applet) full.applet.closeRequested() }
}

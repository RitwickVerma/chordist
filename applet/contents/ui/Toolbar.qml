// SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
//
// SPDX-License-Identifier: MIT

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

// Two short rows instead of one long one, built on Kirigami's ActionToolBar so
// that whatever does not fit (a narrow window) folds into an overflow menu by
// itself. The first row is what you do to a chart while playing it (key, capo,
// easy chords, text size); the second is how the view behaves (follow, scroll)
// with everything occasional behind the menu.
ColumnLayout {
    id: bar

    property var applet
    // The view on show, for "back to top".
    property var view: null
    property bool lyricsTab: false

    readonly property bool hasChords: !!(applet && applet.hasChordNames)
    spacing: 0

    // ---------------------------------------------------------------- chart
    Kirigami.ActionToolBar {
        Layout.fillWidth: true
        visible: bar.hasChords && !bar.lyricsTab
        alignment: Qt.AlignLeft
        actions: [
            Kirigami.Action {
                text: "\u2212"
                tooltip: i18n("Transpose down a semitone")
                onTriggered: bar.applet.transpose = bar.applet.transpose - 1
            },
            Kirigami.Action {
                displayComponent: PlasmaComponents3.Label {
                    text: !bar.applet || bar.applet.transpose === 0 ? i18n("Key ±0")
                        : (bar.applet.transpose > 0 ? i18n("Key +%1", bar.applet.transpose) : i18n("Key %1", bar.applet.transpose))
                    horizontalAlignment: Text.AlignHCenter
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    Accessible.name: i18n("Transposition")
                    TapHandler { enabled: !!bar.applet && bar.applet.transpose !== 0; onTapped: bar.applet.transpose = 0 }
                }
            },
            Kirigami.Action {
                text: "+"
                tooltip: i18n("Transpose up a semitone")
                onTriggered: bar.applet.transpose = bar.applet.transpose + 1
            },
            Kirigami.Action {
                displayComponent: RowLayout {
                    spacing: Kirigami.Units.smallSpacing
                    PlasmaComponents3.Label {
                        text: i18n("Capo")
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                    }
                    PlasmaComponents3.SpinBox {
                        from: 0
                        to: 12
                        value: bar.applet ? bar.applet.capo : 0
                        onValueModified: bar.applet.capo = value
                        Accessible.name: i18n("Capo fret")
                    }
                }
            },
            Kirigami.Action {
                text: i18n("Easy")
                tooltip: i18n("Simplify every chord to an easy shape")
                checkable: true
                checked: !!bar.applet && bar.applet.simplifyChords
                onTriggered: bar.applet.toggle("simplifyChords")
            },
            Kirigami.Action {
                text: i18n("Smaller text")
                icon.name: "format-font-size-less"
                displayHint: Kirigami.DisplayHint.IconOnly
                onTriggered: bar.applet.adjustFontSize(-1)
            },
            Kirigami.Action {
                text: i18n("Larger text")
                icon.name: "format-font-size-more"
                displayHint: Kirigami.DisplayHint.IconOnly
                onTriggered: bar.applet.adjustFontSize(1)
            }
        ]
    }

    // ----------------------------------------------------------- lyrics timing
    // Timings from a database drift by a second or two between releases: nudge
    // them, or pull the nearest line onto what is playing now.
    Kirigami.ActionToolBar {
        Layout.fillWidth: true
        visible: !!(bar.applet && bar.applet.lyrics && bar.lyricsTab)
        alignment: Qt.AlignLeft
        actions: [
            Kirigami.Action {
                displayComponent: PlasmaComponents3.Label {
                    text: i18n("Lyrics timing")
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    opacity: 0.6
                }
            },
            Kirigami.Action {
                text: "−0.5"
                tooltip: i18n("Lyrics half a second earlier")
                onTriggered: bar.applet.nudgeOffset(-0.5)
            },
            Kirigami.Action {
                displayComponent: PlasmaComponents3.Label {
                    text: bar.applet ? bar.applet.offsetLabel : ""
                    horizontalAlignment: Text.AlignHCenter
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    opacity: 0.7
                }
            },
            Kirigami.Action {
                text: "+0.5"
                tooltip: i18n("Lyrics half a second later")
                onTriggered: bar.applet.nudgeOffset(0.5)
            },
            Kirigami.Action {
                text: i18n("Line up now")
                tooltip: i18n("Line the lyrics up with what is playing now")
                icon.name: "view-refresh"
                displayHint: Kirigami.DisplayHint.IconOnly
                onTriggered: bar.applet.syncOffset()
            }
        ]
    }

    // ----------------------------------------------------------------- view
    Kirigami.ActionToolBar {
        Layout.fillWidth: true
        visible: !!(bar.applet && bar.applet.ready)
        alignment: Qt.AlignLeft
        actions: [
            Kirigami.Action {
                text: i18n("Follow the song")
                tooltip: i18n("Follow the song and highlight the line being sung")
                icon.name: "view-media-lyrics"
                displayHint: Kirigami.DisplayHint.IconOnly
                checkable: true
                checked: !!bar.applet && bar.applet.lyricSync
                onTriggered: bar.applet.toggle("lyricSync")
            },
            Kirigami.Action {
                text: i18n("Auto-scroll")
                tooltip: i18n("Scroll the view to keep up with the song")
                icon.name: "arrow-down"
                displayHint: Kirigami.DisplayHint.IconOnly
                checkable: true
                checked: !!bar.applet && bar.applet.autoScroll
                onTriggered: bar.applet.toggle("autoScroll")
            },
            Kirigami.Action {
                visible: !!bar.applet && bar.applet.autoScroll
                displayComponent: PlasmaComponents3.Slider {
                    implicitWidth: Kirigami.Units.gridUnit * 5
                    from: 1
                    to: 10
                    stepSize: 1
                    value: bar.applet ? bar.applet.scrollSpeed : 5
                    onMoved: bar.applet.setScrollSpeed(value)
                    Accessible.name: i18n("Scroll speed")
                    PlasmaComponents3.ToolTip { text: i18n("Scroll speed") }
                }
            },
            Kirigami.Action {
                text: i18n("Back to the top")
                icon.name: "go-top"
                displayHint: Kirigami.DisplayHint.IconOnly
                onTriggered: if (bar.view && bar.view.scrollToTop) bar.view.scrollToTop()
            },
            Kirigami.Action {
                text: i18n("Other versions")
                tooltip: i18n("Wrong version? Pick another")
                icon.name: "edit-find"
                displayHint: Kirigami.DisplayHint.IconOnly
                onTriggered: bar.applet.openVersions()
            },
            // Everything below lives in the overflow menu.
            Kirigami.Action {
                text: i18n("Ask again")
                icon.name: "view-refresh"
                displayHint: Kirigami.DisplayHint.AlwaysHide
                onTriggered: bar.applet.fetchSong()
            },
            Kirigami.Action {
                text: i18n("Romanise the lyrics")
                visible: !!(bar.applet && bar.applet.lyricsNonLatin)
                displayHint: Kirigami.DisplayHint.AlwaysHide
                checkable: true
                checked: !!bar.applet && bar.applet.lyricsRomanised
                onTriggered: bar.applet.toggleRomanise()
            },
            Kirigami.Action {
                text: i18n("Now and next chord stage")
                displayHint: Kirigami.DisplayHint.AlwaysHide
                checkable: true
                checked: !!bar.applet && bar.applet.showStage
                onTriggered: bar.applet.toggle("showStage")
            },
            Kirigami.Action {
                text: i18n("Fingering strip (when the stage is off)")
                displayHint: Kirigami.DisplayHint.AlwaysHide
                checkable: true
                checked: !!bar.applet && bar.applet.showChordDiagrams
                onTriggered: bar.applet.toggle("showChordDiagrams")
            },
            Kirigami.Action {
                text: i18n("Finger numbers")
                displayHint: Kirigami.DisplayHint.AlwaysHide
                checkable: true
                checked: !!bar.applet && bar.applet.showFingers
                onTriggered: bar.applet.toggle("showFingerNumbers")
            },
            Kirigami.Action {
                text: i18n("Left-handed diagrams")
                displayHint: Kirigami.DisplayHint.AlwaysHide
                checkable: true
                checked: !!bar.applet && bar.applet.leftHanded
                onTriggered: bar.applet.toggle("leftHanded")
            },
            Kirigami.Action {
                text: i18n("Open in a window")
                icon.name: "window-new"
                displayHint: Kirigami.DisplayHint.AlwaysHide
                onTriggered: bar.applet.windowRequested()
            }
        ]
    }
}

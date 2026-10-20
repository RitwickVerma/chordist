// SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
//
// SPDX-License-Identifier: MIT

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Item {
    id: compact
    property var applet
    // The PlasmoidItem, which owns the popup's expanded state.
    property var host

    readonly property var player: applet ? applet.player : null

    // "icon"  - only the lyrics icon, the smallest footprint (good next to
    //           another media widget such as the PlasMusic toolbar)
    // "title" - art/icon plus the song title
    // "full"  - art/icon plus title and artist
    // "chord"  - icon plus the chord you should be playing right now
    readonly property string mode: plasmoid.configuration.compactMode
    readonly property bool showArt: mode !== "icon" && mode !== "chord"
    readonly property bool showText: mode !== "icon"
    readonly property bool showArtist: mode === "full"

    readonly property string label: {
        if (!applet || !applet.ready) return "Chordist"
        if (mode === "chord") return applet.nowChord || applet.nextChord || "\u266a"
        if (showArtist && applet.artist)
            return applet.track ? applet.track + "  \u2014  " + applet.artist : applet.artist
        return applet.track || applet.artist || "Chordist"
    }

    // True when the current song has a chord chart. The panel item stays visible
    // for lyrics-only songs too (see hasContent below), so this is only used to
    // describe the chart itself.
    readonly property bool chordsAvailable: applet
        ? !!(applet.chart && applet.chart.sections && applet.chart.sections.length > 0)
        : false

    readonly property int hPadding: Kirigami.Units.smallSpacing
    // The panel gives items only a couple of pixels of margin, which leaves an
    // icon-only item looking crammed against its neighbours, so that mode gets a
    // roomier square around the same size of icon.
    readonly property int sidePadding: showText ? hPadding : hPadding * 2
    readonly property int iconSize: Kirigami.Units.iconSizes.smallMedium

    // Rock the guitar while something is playing *and* the song actually has
    // something to show. A track with no lyrics and no chart found sits still, so
    // the motion means "there is something here for you", not merely "audio is
    // playing". In icon-only mode - what this item is usually in, next to another
    // media widget - the motion is the only sign of life there is.
    readonly property bool hasContent: {
        if (!applet) return false
        var lyrics = applet.lyrics
        if (lyrics && lyrics.lines && lyrics.lines.length > 0) return true
        var chart = applet.chart
        return !!(chart && chart.sections && chart.sections.length > 0)
    }
    // Each part of the gate is its own typed boolean: a long chain of reads that
    // come back through QVariant properties is not something to bet the animation on.
    readonly property bool animateEnabled: plasmoid.configuration.animateIcon !== false
    readonly property bool playingNow: !!applet && !!applet.playing
    readonly property bool iconAnimating: animateEnabled && playingNow && hasContent


    // The applet container sizes a panel item from the attached Layout
    // properties, so they have to be set explicitly - implicitWidth on its own
    // gets ignored and the item collapses to a bare icon square.
    visible: hasContent
    Layout.preferredWidth: !hasContent ? 0
        : (showText ? content.implicitWidth + hPadding * 2 : iconSize + sidePadding * 2)
    Layout.preferredHeight: hasContent ? Math.max(content.implicitHeight, iconSize) : 0
    Layout.minimumWidth: Layout.preferredWidth
    Layout.minimumHeight: Layout.preferredHeight
    Layout.fillWidth: false
    Layout.fillHeight: hasContent
    implicitWidth: Layout.preferredWidth
    implicitHeight: Layout.preferredHeight

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: function (mouse) {
            if (mouse.button === Qt.MiddleButton) {
                const action = plasmoid.configuration.middleClickAction
                if (!compact.player) return
                if (action === "next") compact.player.Next()
                else if (action === "previous") compact.player.Previous()
                else if (action === "playpause") compact.player.PlayPause()
                return
            }
            if (plasmoid.configuration.openAsWindow) {
                if (compact.applet) compact.applet.windowRequested()
                return
            }
            // Left click opens/closes the popup. This MouseArea accepts the press,
            // so Plasma's own handler never sees it: toggle `expanded` ourselves,
            // on the PlasmoidItem, which is what the shell's CompactApplet watches.
            if (compact.host) compact.host.expanded = !compact.host.expanded
        }
    }

    RowLayout {
        id: content
        anchors.fill: parent
        anchors.leftMargin: compact.sidePadding
        anchors.rightMargin: compact.sidePadding
        spacing: Kirigami.Units.smallSpacing

        Image {
            id: art
            Layout.preferredWidth: compact.iconSize
            Layout.preferredHeight: compact.iconSize
            Layout.alignment: Qt.AlignVCenter
            visible: compact.showArt && applet !== null && applet.artUrl.length > 0
                     && status === Image.Ready
            source: compact.showArt && applet ? applet.artUrl : ""
            sourceSize.width: 128
            sourceSize.height: 128
            fillMode: Image.PreserveAspectFit
            asynchronous: true
        }

        Kirigami.Icon {
            id: glyph
            visible: !art.visible
            Layout.preferredWidth: compact.iconSize
            Layout.preferredHeight: compact.iconSize
            Layout.alignment: Qt.AlignVCenter
            // A guitar, not a lyrics page. Falls back to the lyrics icon if the
            // user's icon theme has no "guitar" (Breeze does not, Papirus does).
            source: "guitar"
            fallback: "view-media-lyrics"
            active: applet !== null && applet !== undefined && applet.playing === true
            opacity: applet && applet.ready ? 1 : 0.55

            // Pivot near the bottom of the box so it rocks like a guitar being
            // strummed rather than spinning about its middle.
            transform: Rotation {
                id: strum
                origin.x: glyph.width / 2
                origin.y: glyph.height * 0.9
                angle: 0
            }

            SequentialAnimation {
                running: glyph.visible && compact.iconAnimating
                loops: Animation.Infinite
                // Settle straight whenever it stops, so a paused song does not
                // leave the icon frozen mid-tilt.
                onRunningChanged: if (!running) strum.angle = 0

                NumberAnimation { target: strum; property: "angle"; to: -10; duration: 240; easing.type: Easing.OutQuad }
                NumberAnimation { target: strum; property: "angle"; to: 8; duration: 330; easing.type: Easing.InOutQuad }
                NumberAnimation { target: strum; property: "angle"; to: 0; duration: 270; easing.type: Easing.InQuad }
                PauseAnimation { duration: 900 }
            }
        }

        ScrollingText {
            id: title
            visible: compact.showText
            Layout.alignment: Qt.AlignVCenter
            Layout.maximumWidth: compact.mode === "chord" ? Kirigami.Units.gridUnit * 5 : Kirigami.Units.gridUnit * 14
            text: compact.label
            scrolling: plasmoid.configuration.compactScroll
            // Build a fresh font: a QML font is a value type, so mutating a copy
            // of the theme font never reached the Text.
            font: Qt.font({
                family: Kirigami.Theme.defaultFont.family,
                weight: compact.mode === "chord" ? Font.Bold : Font.Normal,
                pointSize: Math.max(1, Kirigami.Theme.defaultFont.pointSize + plasmoid.configuration.fontSizeOffset)
            })
            color: Kirigami.Theme.textColor
            horizontalAlignment: Text.AlignLeft
        }
    }
}

// SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
//
// SPDX-License-Identifier: MIT

import QtQuick
import QtQuick.Window
import QtCore
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami
import org.kde.plasma.private.mpris as Mpris

// Plasma glue: pick the player that is making noise, hand it to the song model,
// and put the model on screen in the panel, the popup and an optional window.
// Everything the widget knows about the song lives in SongModel.qml.
PlasmoidItem {
    id: root

    // ----------------------------------------------------------------- MPRIS
    Mpris.Mpris2Model {
        id: mpris
        Component.onCompleted: currentIndex = 0
    }
    // Several players are registered at once on a normal desktop (Spotify, a
    // browser tab, a phone over KDE Connect) and the first row is not
    // necessarily the one making noise, so follow whichever is playing.
    function pickPlayer() {
        var current = mpris.currentPlayer
        if (current && current.playbackStatus === Mpris.PlaybackStatus.Playing) return
        for (var i = 0; i < mpris.rowCount(); i++) {
            var candidate = mpris.data(mpris.index(i, 0), Qt.UserRole + 1)
            if (candidate && candidate.playbackStatus === Mpris.PlaybackStatus.Playing) {
                mpris.currentIndex = i
                return
            }
        }
    }
    // Only while nothing is playing: when the player we show is the one playing
    // there is nothing to look for.
    Timer { interval: 2000; repeat: true; running: !root.playing; onTriggered: root.pickPlayer() }
    Connections {
        target: mpris
        function onRowsInserted() {
            if (mpris.currentPlayer === null) mpris.currentIndex = 0
            root.pickPlayer()
        }
        function onRowsRemoved() {
            if (mpris.currentPlayer === null) mpris.currentIndex = 0
            root.pickPlayer()
        }
    }

    readonly property var player: mpris.currentPlayer || null
    readonly property bool playing: !!player && player.playbackStatus === Mpris.PlaybackStatus.Playing

    SongModel {
        id: song
        config: plasmoid.configuration
        player: root.player
        playing: root.playing
        track: root.player && root.player.track ? root.player.track : ""
        artist: root.player && root.player.artist ? root.player.artist : ""
        album: root.player && root.player.album ? root.player.album : ""
        artUrl: root.player && root.player.artUrl ? root.player.artUrl : ""
        identity: root.player && root.player.identity ? root.player.identity : ""
        lengthSec: root.player && root.player.length > 0 ? root.player.length / 1000000 : 0
        onWindowRequested: root.toggleWindow()
        onCloseRequested: root.closeSelf()
    }

    // ------------------------------------------------------ floating window
    // A detached copy of the same view in a real window, for when the popup is
    // too transient (it closes as soon as it loses focus). Opened from the
    // popup's menu, or straight from a click on the panel item when "Floating
    // window" is set in the settings.
    //
    // Staying above other windows is not something a Wayland client can ask for
    // (Qt's WindowStaysOnTopHint is ignored under xdg-shell), so that is KDE's
    // business: Keep Above from the title-bar menu, or a window rule to make it
    // stick.
    property bool windowVisible: false
    function toggleWindow() { windowVisible = !windowVisible }
    // Opening is the moment to put the tab back where the user wants it: the
    // popup and the window are each built once and then reused.
    onExpandedChanged: function () { if (root.expanded) song.openCount++ }
    onWindowVisibleChanged: function () { if (root.windowVisible) song.openCount++ }
    // Esc, from inside either: close whichever is open.
    function closeSelf() {
        if (windowVisible) windowVisible = false
        else expanded = false
    }

    // Where the window was left. Qt's own Settings type keeps these out of the
    // widget's saved configuration.
    Settings {
        id: uiSettings
        category: "chordist"
        property alias storedX: floating.x
        property alias storedY: floating.y
        property alias storedWidth: floating.width
        property alias storedHeight: floating.height
        property bool hasGeometry: false
    }

    Window {
        id: floating
        visible: root.windowVisible
        flags: Qt.Window
        title: song.ready ? (song.artist ? song.track + " — " + song.artist + " — Chordist" : song.track + " — Chordist") : "Chordist"
        color: Kirigami.Theme.backgroundColor
        width: Kirigami.Units.gridUnit * 32
        height: Kirigami.Units.gridUnit * 36
        minimumWidth: Kirigami.Units.gridUnit * 22
        minimumHeight: Kirigami.Units.gridUnit * 20
        onClosing: root.windowVisible = false

        onVisibleChanged: {
            if (!visible) return
            // First time it opens it lands centred near the top; after that it
            // comes back where it was left, size included.
            if (!uiSettings.hasGeometry) {
                floating.x = Math.round(Screen.virtualX + (Screen.width - floating.width) / 2)
                floating.y = Screen.virtualY + Kirigami.Units.gridUnit * 3
                uiSettings.hasGeometry = true
            }
            floating.requestActivate()
        }

        // Built only while the window is open: a second live copy of the whole
        // view is not something to keep around for a window nobody is looking at.
        Loader {
            anchors.fill: parent
            active: root.windowVisible
            sourceComponent: Full { applet: song }
        }
    }

    compactRepresentation: Compact { applet: song; host: root }
    fullRepresentation: Full { applet: song }

    // HiddenStatus makes the containment drop the item from the panel. Keep the
    // icon for anything worth opening, a chart OR lyrics; a track with nothing
    // recognised hides the icon instead of leaving a dead one behind. The
    // previous song's chart stays until the new answer lands, so the icon does
    // not blink on every track change.
    Plasmoid.status: (song.chordsAvailable || song.lyricsAvailable) ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.HiddenStatus
    toolTipMainText: song.ready ? song.track : i18n("Chordist")
    toolTipSubText: {
        if (!song.ready) return i18n("Chords, tabs and lyrics for whatever you play")
        var chord = song.nowChord ? i18n("Now: %1", song.nowChord) : ""
        return [song.artist, chord].filter(function (part) { return part.length > 0 }).join("  ·  ")
    }
}

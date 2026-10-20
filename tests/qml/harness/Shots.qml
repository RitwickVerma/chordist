// SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
//
// SPDX-License-Identifier: MIT

import QtQuick
import QtQuick.Window
import "applet/contents/ui" as UI

// Renders the real Full.qml against the real SongModel and a fixture service,
// then writes a PNG. Arguments after "--": scenario, output path, service port.
Window {
    id: win
    width: 576
    height: 650
    visible: true
    color: "#232629"

    readonly property var args: Qt.application.arguments.slice(Qt.application.arguments.indexOf("--") + 1)
    readonly property string scenario: args[0] || "chords"
    readonly property string out: args[1] || "shot.png"
    readonly property int port: parseInt(args[2] || "18788", 10)

    QtObject {
        id: fakeConfig
        property string serviceUrl: "http://127.0.0.1:" + win.port
        property string defaultTab: "chords"
        property bool autoScroll: true
        property bool lyricSync: true
        property bool showChordDiagrams: true
        property bool showStage: true
        property bool showFingerNumbers: true
        property bool leftHanded: win.scenario === "lefty"
        property bool simplifyChords: false
        property int scrollSpeed: 5
        property int fontSizeOffset: 0
        property int backgroundOpacity: 100
    }

    // The slice of an MPRIS player the widget touches. A plain object, because
    // QML will not declare capitalised methods like PlayPause().
    property bool playingNow: false
    readonly property var fakePlayer: {
        var self = {
            position: 0, rate: 1, minimumRate: 0.25, maximumRate: 2,
            canPlay: true, canGoNext: true, canGoPrevious: true, toggles: 0,
            PlayPause: function () { self.toggles++; win.playingNow = !win.playingNow },
            Next: function () {}, Previous: function () {}, updatePosition: function () {}
        }
        return self
    }
    Timer {
        interval: 50; repeat: true; running: win.playingNow
        onTriggered: win.fakePlayer.position += 50000 * win.fakePlayer.rate
    }

    UI.SongModel {
        id: model
        config: fakeConfig
        player: fakePlayer
        playing: win.playingNow
        track: win.scenario === "tab" ? "Open String Study" : (win.scenario === "empty" ? "" : "Amazing Grace")
        artist: win.scenario === "empty" ? "" : "Traditional"
        album: "Hymns"
        lengthSec: 34
        onWindowRequested: {}
        onCloseRequested: {}
    }

    UI.Full {
        id: full
        anchors.fill: parent
        applet: model
    }

    // Everything the UG page would add on top of a saved chart.
    function dressAsUltimateGuitar() {
        var song = JSON.parse(JSON.stringify(model.song))
        song.chords.source = "ultimate-guitar"
        song.chords.capo = 0
        song.chords.meta = {
            tuning: { name: "Standard", notes: ["E", "A", "D", "G", "B", "E"] }, difficulty: "novice", tonality: "G",
            type: "Chords", rating: 4.7, votes: 3120, views: 1250000, favorites: 9100, bpm: 87, author: "", strumming: []
        }
        song.chords.applicature = {
            "G": [{ name: "G", frets: [3, 2, 0, 0, 0, 3], fingers: [2, 1, 0, 0, 0, 3], base: 1, barre: null, source: "ultimate-guitar" },
                  { name: "G", frets: [3, 5, 5, 4, 3, 3], fingers: [1, 3, 4, 2, 1, 1], base: 3, barre: 3, source: "ultimate-guitar" }]
        }
        model.song = song
    }

    Timer {
        id: loaded
        interval: 100; repeat: true; running: true
        property int ticks: 0
        onTriggered: {
            ticks++
            var ready = win.scenario === "empty" || (model.song && model.song.chords && ticks > 8)
            if (!ready && ticks < 80) return
            running = false
            win.arrange()
        }
    }

    function arrange() {
        // A render of an empty "offline" popup is worse than no render: say so.
        if (scenario !== "empty" && !(model.song && model.song.chords)) {
            console.log("FAIL the song did not load: " + model.statusMessage)
            Qt.exit(3)
            return
        }
        if (scenario === "empty") {
            var col = full.children[1]
            for (var k = 0; k < col.children.length; k++) {
                var cc = col.children[k]
                console.log("DEBUG row", k, cc, cc.visible, Math.round(cc.y), Math.round(cc.height))
            }
            var v = full.activeView
            console.log("DEBUG view", v.x, v.y, v.width, v.height, "parent", v.parent.x, v.parent.y, v.parent.width, v.parent.height)
            for (var i = 0; i < v.children.length; i++) {
                var c = v.children[i]
                console.log("DEBUG child", i, c, c.visible, c.x, c.y, c.width, c.height)
                for (var j = 0; j < c.children.length && c.visible; j++)
                    console.log("DEBUG   sub", j, c.children[j], c.children[j].visible, c.children[j].y, c.children[j].height)
            }
            shoot(); return
        }
        if (scenario === "ug" || scenario === "lefty") dressAsUltimateGuitar()
        if (scenario === "lyrics") full.currentTab = 0
        if (scenario === "versions") {
            model.versions = { lyrics: [{ id: 1, track: "Amazing Grace", artist: "Traditional", album: "Hymns", duration: 34, synced: true },
                                        { id: 2, track: "Amazing Grace (Live)", artist: "Traditional", duration: 41, synced: false }],
                               charts: [{ url: "https://tabs.ultimate-guitar.com/tab/x/y-chords-1", name: "Amazing Grace", artist: "Traditional", type: "Chords", version: 2, rating: 4.7, votes: 3120, tonality: "G" }] }
            model.versionsOpen = true
        }
        if (scenario === "advice") { model.song.chords.capo = 0; model.transpose = 3 }
        // Play to a point in the song, so highlight, stage and countdown are live.
        fakePlayer.position = (parseFloat(args[3] || "9")) * 1000000
        model.syncPosition()
        win.playingNow = true
        settle.start()
    }

    Timer {
        id: settle
        interval: 600
        onTriggered: { win.playingNow = false; model.syncPosition(); win.shoot() }
    }

    function shoot() {
        shotTimer.start()
    }
    Timer {
        id: shotTimer
        interval: 700
        onTriggered: win.contentItem.grabToImage(function (result) {
            result.saveToFile(win.out)
            Qt.quit()
        })
    }
}

// SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
//
// SPDX-License-Identifier: MIT

import QtQuick
import QtTest
import "files.js" as List
import "applet/contents/ui" as UI

// Every component of the widget, created on the Qt and KDE stack that is installed. Nothing here knows what a
// component does: the point is that each one loads, and that creating it prints no warning. Run through
// tests/qml/components.sh, which supplies files.js, shims i18n() and fails the run on warnings. A property that the
// installed Kirigami lacks is invisible to the song-model test and to qmllint on a newer stack, and takes a whole
// view down on an older one.
TestCase {
    id: test
    name: "Components"
    when: windowShown

    // Modules this test may find missing, and why that is not a failure. Detected at run time: a component is
    // skipped (and the skip is printed) only when EVERY error it reports is "module X is not installed" on one of
    // ITS OWN import lines, with X listed here. Anything else, a missing Kirigami included, fails.
    readonly property var mayBeMissing: ({
        // The Plasma shell provides these, and Debian 13 ships them in no package at all, so a container with
        // Kirigami and Plasma Components cannot load main.qml (PlasmoidItem, Plasmoid) or config/config.qml
        // (ConfigModel). Arch, Fedora and the real shell have them, and there both are really loaded.
        "org.kde.plasma.plasmoid": "PlasmoidItem and Plasmoid are part of the Plasma shell",
        "org.kde.plasma.configuration": "ConfigModel is part of the Plasma shell",
        "org.kde.plasma.private.mpris": "the MPRIS model is a private Plasma API"
    })
    // main.qml and config/config.qml: if more than that is skipped, something broader is being hidden.
    readonly property int mostSkipsAllowed: 2
    // Loaded and compiled, but not instantiated: Plasma insists on creating a PlasmoidItem itself, as the root of
    // an applet ("Detected a PlasmoidItem which is not the root QML item"). The real-shell check in
    // docs/testing.md covers running it.
    readonly property var compileOnly: ["ui/main.qml"]

    property int loaded: 0
    property int skipped: 0

    Item { id: host; width: 400; height: 300 }

    // What the components find around them in the Plasma shell: the settings (the `plasmoid` context property, which
    // Plasma injects, is visible to a component created from here) and a song for `applet` to point at.
    QtObject {
        id: plasmoid
        readonly property var configuration: ({
            compactMode: "full", animateIcon: true, middleClickAction: "playpause", openAsWindow: false,
            compactScroll: true, fontSizeOffset: 0
        })
    }
    QtObject {
        id: config
        property string serviceUrl: "http://127.0.0.1:9"   // nothing listens here
        property string defaultTab: "chords"
        property bool lyricSync: true
        property bool simplifyChords: false
        property bool showStage: true
        property bool showChordDiagrams: true
        property bool showFingerNumbers: true
        property bool leftHanded: false
        property int fontSizeOffset: 0
        property int scrollSpeed: 5
        property bool autoScroll: true
        property int backgroundOpacity: 100
    }
    QtObject { id: shell; property bool expanded: false }
    UI.SongModel { id: song; config: config; track: "Song"; artist: "Artist"; lengthSec: 100 }

    // The error lines of a component that did not load, as a reason to skip it, or "" when it must fail.
    function skipReason(url, errors) {
        var lines = errors.split("\n").filter(function (line) { return line.length > 0 })
        var modules = []
        for (var i = 0; i < lines.length; i++) {
            var m = /^(.*?):\d+(?::\d+)? module "([^"]+)" is not installed$/.exec(lines[i])
            if (!m || m[1] !== String(url) || !(m[2] in mayBeMissing))
                return ""
            modules.push(m[2])
        }
        return modules.length === 0 ? "" : "not loadable here, " + modules.join(", ") + " is not installed (" + mayBeMissing[modules[0]] + ")"
    }

    // files.js says, per file, which of `applet`, `host` and `config` it declares (a grep, not a list kept by hand).
    function test_component_data() {
        return List.files.map(function (entry) {
            return { tag: entry.file.replace(/^applet\/contents\//, ""), entry: entry }
        })
    }

    function test_component(data) {
        var url = Qt.resolvedUrl(data.entry.file)
        var component = Qt.createComponent(url)
        if (component.status === Component.Error) {
            var reason = skipReason(url, component.errorString())
            if (reason !== "") {
                skipped++
                skip(reason)
                return
            }
            fail("does not load:\n" + component.errorString())
        }
        compare(component.status, Component.Ready)
        if (compileOnly.indexOf(data.tag) >= 0) {
            loaded++
            return
        }
        var initial = {}
        if (data.entry.applet) initial.applet = song
        if (data.entry.host) initial.host = shell
        if (data.entry.config) initial.config = config
        var object = component.createObject(host, initial)
        verify(object !== null, "createObject() returned null: " + component.errorString())
        wait(20)    // let the first bindings run: a TypeError in one is a warning, which fails the run
        object.destroy()
        loaded++
    }

    function test_zz_the_skips_did_not_swallow_the_suite() {
        verify(List.files.length > 15, "files.js lists " + List.files.length + " components")
        verify(skipped <= mostSkipsAllowed, skipped + " components were skipped; at most " + mostSkipsAllowed + " may be")
        compare(loaded + skipped, List.files.length)
    }
}

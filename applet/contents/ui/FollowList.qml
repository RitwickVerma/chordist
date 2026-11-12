// SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
//
// SPDX-License-Identifier: MIT

import QtQuick
import org.kde.kirigami as Kirigami

// A list that keeps one row in view as the song moves, glides rather than
// jumps, and stands aside while somebody is scrolling it by hand. The lyrics
// and the chart both use it, so their scrolling behaves identically.
Item {
    id: root

    property alias model: list.model
    property alias delegate: list.delegate
    property alias spacing: list.spacing
    property alias contentY: list.contentY
    property alias count: list.count

    // The row to keep in view, and whether to follow it at all.
    property int followIndex: -1
    property bool follow: true
    // How many already-sung rows stay visible above the followed one.
    property int contextLines: 4
    property int glideMs: 320
    // A steady reading scroll for when nothing is being followed: the pace is
    // 1..10, and 0 turns it off. It only moves while the song does.
    property int readingSpeed: 0
    property bool playing: true
    // Where the song is, 0..1, for a chart that has no timings of its own (a
    // tab): the page follows it in proportion, pausing and seeking with the
    // music. -1 for none.
    property real songProgress: -1
    // Hands-off period after a manual scroll, so the page is not yanked back.
    property int holdMs: 4000

    property double lastUserScroll: 0
    // A function, not a property: Date.now() is not something bindings can watch.
    function userScrolling() { return Date.now() - lastUserScroll < holdMs }

    function scrollTo(dest, instant) {
        glide.stop()
        if (instant || Math.abs(dest - list.contentY) < 1) { list.contentY = dest; return }
        glide.to = dest
        glide.start()
    }
    function scrollToIndex(index, instant) {
        if (index < 0 || index >= list.count) return
        var item = list.itemAtIndex(index)
        var lead = contextLines * (item && item.height > 0 ? item.height : Kirigami.Units.gridUnit * 2)
        // A row far off-screen has no delegate yet: jump near it first, then glide.
        if (!item) list.positionViewAtIndex(index, ListView.Beginning)
        var limit = Math.max(0, list.contentHeight - list.height)
        var dest = Math.max(0, Math.min(limit, (item ? item.y : list.contentY) - lead))
        scrollTo(dest, instant)
    }
    function scrollToTop() {
        // A deliberate scroll: follow mode must not drag the page straight back.
        lastUserScroll = Date.now()
        scrollTo(0, false)
    }
    function nudge(dy) {
        var limit = Math.max(0, list.contentHeight - list.height)
        glide.stop()
        list.contentY = Math.max(0, Math.min(limit, list.contentY + dy))
        lastUserScroll = Date.now()
    }
    function itemAtIndex(index) { return list.itemAtIndex(index) }

    // Put the followed row in view at once: when following is switched on, and
    // when the list comes on screen (the popup opening, a tab switch) with the
    // song already under way. Deferred, so the list has its size first.
    function showFollowed() {
        if (!follow || followIndex < 0 || !visible || userScrolling()) return
        Qt.callLater(function () { if (root.follow && root.visible) root.scrollToIndex(root.followIndex, true) })
    }
    onFollowIndexChanged: if (follow && followIndex >= 0 && !userScrolling()) scrollToIndex(followIndex, false)
    onFollowChanged: showFollowed()
    onVisibleChanged: showFollowed()
    // A new song: back to the top, and nothing of the old one's hands-off period.
    onModelChanged: {
        glide.stop()
        list.contentY = 0
        lastUserScroll = 0
        showFollowed()
    }

    NumberAnimation {
        id: glide
        target: list
        property: "contentY"
        duration: root.glideMs
        easing.type: Easing.InOutQuad
    }

    // The reading scroll: a constant pace while the song plays.
    Timer {
        interval: 40
        repeat: true
        running: root.readingSpeed > 0 && !root.follow && root.songProgress < 0 && root.playing && root.visible
            && list.contentHeight > list.height + 1
        onTriggered: {
            if (root.userScrolling()) return
            var limit = Math.max(0, list.contentHeight - list.height)
            if (list.contentY >= limit - 0.5) return
            list.contentY = Math.min(limit, list.contentY + root.readingSpeed * 0.12)
        }
    }
    // The proportional scroll: the page at the same fraction as the song.
    Timer {
        interval: 500
        repeat: true
        running: root.songProgress >= 0 && !root.follow && root.visible && list.contentHeight > list.height + 1
        onTriggered: {
            if (root.userScrolling()) return
            var limit = Math.max(0, list.contentHeight - list.height)
            root.scrollTo(Math.max(0, Math.min(limit, limit * root.songProgress)), false)
        }
    }

    ListView {
        id: list
        anchors.fill: parent
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        // Grabbing the list ends any glide in progress: the animation would otherwise
        // keep pulling against the user's own hand.
        onMovementStarted: { root.lastUserScroll = Date.now(); glide.stop() }
        onFlickStarted: { root.lastUserScroll = Date.now(); glide.stop() }
    }
}

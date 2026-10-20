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
    // 1..10, and 0 turns it off.
    property int readingSpeed: 0
    // Hands-off period after a manual scroll, so the page is not yanked back.
    property int holdMs: 4000

    property double lastUserScroll: 0
    // A function, not a property: Date.now() is not something bindings can watch.
    function userScrolling() { return Date.now() - lastUserScroll < holdMs }

    function scrollToIndex(index) {
        if (index < 0) return
        var item = list.itemAtIndex(index)
        var lead = contextLines * (item && item.height > 0 ? item.height : Kirigami.Units.gridUnit * 2)
        // A row far off-screen has no delegate yet: jump near it first, then glide.
        if (!item) list.positionViewAtIndex(index, ListView.Beginning)
        var limit = Math.max(0, list.contentHeight - list.height)
        var dest = Math.max(0, Math.min(limit, (item ? item.y : list.contentY) - lead))
        if (Math.abs(dest - list.contentY) < 1) return
        glide.stop()
        glide.to = dest
        glide.start()
    }
    function scrollToTop() {
        // A deliberate scroll: follow mode must not drag the page straight back.
        lastUserScroll = Date.now()
        glide.stop()
        glide.to = 0
        glide.start()
    }
    function nudge(dy) {
        var limit = Math.max(0, list.contentHeight - list.height)
        list.contentY = Math.max(0, Math.min(limit, list.contentY + dy))
        lastUserScroll = Date.now()
    }
    function itemAtIndex(index) { return list.itemAtIndex(index) }

    onFollowIndexChanged: if (follow && followIndex >= 0 && !userScrolling()) scrollToIndex(followIndex)

    NumberAnimation {
        id: glide
        target: list
        property: "contentY"
        duration: root.glideMs
        easing.type: Easing.InOutQuad
    }

    Timer {
        interval: 40
        repeat: true
        running: root.readingSpeed > 0 && !root.follow && list.contentHeight > list.height + 1
        onTriggered: {
            if (root.userScrolling()) return
            var limit = Math.max(0, list.contentHeight - list.height)
            if (list.contentY >= limit - 0.5) return
            list.contentY = Math.min(limit, list.contentY + root.readingSpeed * 0.12)
        }
    }

    ListView {
        id: list
        anchors.fill: parent
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        onMovementStarted: root.lastUserScroll = Date.now()
        onFlickStarted: root.lastUserScroll = Date.now()
    }
}

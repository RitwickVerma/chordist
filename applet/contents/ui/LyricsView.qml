import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import "../js/util.js" as Util

Item {
    id: view

    property var applet
    /** follow the playback position and auto-scroll */
    property bool follow: true

    readonly property var lyrics: applet ? applet.lyrics : null
    readonly property var lines: (lyrics && lyrics.lines) ? lyrics.lines : []
    // A synced file does not have to begin with a timestamp and may contain
    // blank gap lines, so look for any usable timestamp instead of testing line 0.
    readonly property bool synced: {
        if (!(lyrics && lyrics.synced) || lines.length === 0) return false
        for (var i = 0; i < lines.length; i++) {
            if (lines[i].t !== null && lines[i].t !== undefined) return true
        }
        return false
    }
    readonly property bool hasLyrics: lines.length > 0

    property int activeIndex: -1
    property double lastUserScroll: 0

    // How many lines already sung stay visible above the one being sung. The
    // sync scroll aims the active line this far below the top instead of
    // centring it, so the preceding lines stay on screen.
    property int contextLines: 4

    readonly property int fontDelta: applet ? applet.fontSizeOffset : 0

    // A QML font is a value type: mutating a copy of a theme font is thrown
    // away before it reaches the Text, so it silently ignored the size setting.
    // Build a fresh font instead.
    readonly property font bodyFont: Qt.font({
        family: Kirigami.Theme.defaultFont.family,
        pointSize: Math.max(1, Kirigami.Theme.defaultFont.pointSize + fontDelta)
    })

    function recomputeActive() {
        // No highlight while the shown lines still belong to the previous track.
        if (!synced || (applet && applet.stale)) { activeIndex = -1; return }
        var position = applet ? applet.playbackPosition : 0
        var found = -1
        for (var i = 0; i < lines.length; i++) {
            var stamp = lines[i].t
            if (stamp === null || stamp === undefined) continue
            if (stamp > position - (applet ? applet.syncLag : 0.25)) break
            // Blank timed lines are instrumental gaps; keep the highlight on the
            // line that was actually sung.
            if ((lines[i].text || "").length > 0) found = i
        }
        activeIndex = found
    }

    /** scroll the list by a few lines, for keyboard control */
    function nudge(dy) {
        var limit = Math.max(0, list.contentHeight - list.height)
        list.contentY = Math.max(0, Math.min(limit, list.contentY + dy))
    }

    /** jump back to the top of the song */
    function scrollToTop() {
        // Stamp the manual-scroll time so follow mode does not yank the view
        // straight back down.
        view.lastUserScroll = Date.now()
        followScroll.stop()
        followScroll.to = 0
        followScroll.start()
    }

    onLinesChanged: recomputeActive()
    onSyncedChanged: recomputeActive()
    onActiveIndexChanged: {
        if (activeIndex < 0) return
        // Lyric sync alone means "keep the line being sung in view"; auto-scroll
        // is the separate, song-independent reading scroll used when sync is off.
        if (!view.follow || !view.applet) return
        if (Date.now() - lastUserScroll < 4000) return
        view.scrollToActive()
    }

    // Glide the line being sung to `contextLines` rows below the top, so the
    // lines just sung stay visible. Qt has no animated positionViewAtIndex, so
    // aim contentY and let a NumberAnimation take it there; a line far
    // off-screen has no delegate yet, so jump first and then back off.
    function scrollToActive() {
        var item = list.itemAtIndex(activeIndex)
        var lead = view.contextLines * (item && item.height > 0 ? item.height : Kirigami.Units.gridUnit * 2)
        if (!item) list.positionViewAtIndex(activeIndex, ListView.Beginning)
        var limit = Math.max(0, list.contentHeight - list.height)
        var dest = Math.max(0, Math.min(limit, (item ? item.y : list.contentY) - lead))
        if (Math.abs(dest - list.contentY) < 1) return
        followScroll.stop()
        followScroll.to = dest
        followScroll.start()
    }

    // Smooth scroll for follow mode.
    NumberAnimation {
        id: followScroll
        target: list
        property: "contentY"
        duration: 320
        easing.type: Easing.InOutQuad
    }

    // A Connections block cannot resolve a signal on a `var`-typed target, so
    // bounce the position through a local property instead.
    property real playbackPosition: view.applet ? view.applet.playbackPosition : 0
    onPlaybackPositionChanged: view.recomputeActive()

    ListView {
        id: list
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        visible: view.hasLyrics
        clip: true
        model: view.lines
        spacing: Kirigami.Units.smallSpacing
        boundsBehavior: Flickable.StopAtBounds

        onMovementStarted: view.lastUserScroll = Date.now()
        onFlickStarted: view.lastUserScroll = Date.now()

        delegate: Item {
            id: row
            width: ListView.view.width
            implicitHeight: textItem.implicitHeight + Kirigami.Units.smallSpacing * 2
            height: implicitHeight

            readonly property var line: modelData
            readonly property bool current: index === view.activeIndex

            Rectangle {
                anchors.fill: parent
                radius: Kirigami.Units.smallSpacing / 2
                color: Kirigami.Theme.highlightColor
                opacity: row.current ? 0.16 : 0
                Behavior on opacity { NumberAnimation { duration: 150 } }
            }

            Text {
                id: textItem
                x: Kirigami.Units.smallSpacing
                width: parent.width - Kirigami.Units.smallSpacing * 2
                anchors.verticalCenter: parent.verticalCenter
                wrapMode: Text.Wrap
                textFormat: Text.RichText
                font: view.bodyFont
                text: row.displayText
                color: row.current ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
                opacity: row.current ? 1 : 0.8
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: (view.synced && row.line.t !== null && row.line.t !== undefined)
                    ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                    if (!view.applet || !view.synced) return
                    var stamp = row.line.t
                    if (stamp === null || stamp === undefined) return
                    view.applet.seekTo(stamp)
                }
            }

            // word-by-word karaoke for the current line when LRCLIB has word timings
            readonly property string displayText: {
                var text = row.line && row.line.text ? row.line.text : ""
                var words = row.line ? row.line.words : null
                if (!row.current || !words || !words.length) return Util.escapeHtml(text)
                var joined = ""
                for (var i = 0; i < words.length; i++) joined += (words[i].text || "")
                if (Util.normalize(joined) !== Util.normalize(text)) return Util.escapeHtml(text)
                var position = view.applet ? view.applet.playbackPosition : 0
                var sung = Util.colorHex(Kirigami.Theme.highlightColor)
                var pending = Util.colorHex(Kirigami.Theme.textColor)
                var html = ""
                for (var w = 0; w < words.length; w++) {
                    var word = words[w]
                    var done = (word.t !== null && word.t !== undefined) ? (word.t <= position - (view.applet ? view.applet.syncLag : 0.25)) : false
                    html += "<span style=\"color:" + (done ? sung : pending) + "\">"
                          + Util.escapeHtml(word.text || "") + "</span>"
                }
                return html
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        visible: !view.hasLyrics
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            opacity: 0.75
            text: (view.applet && view.applet.loading)
                ? i18n("Looking for lyrics\u2026")
                : i18n("No lyrics found for this track")
        }

        PasteSheet {
            Layout.fillWidth: true
            Layout.fillHeight: true
            applet: view.applet
            hint: i18n("Nothing found? Paste a chord sheet or lyrics below and it will be saved for this track.")
        }
    }
}

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import "../js/theory.js" as Theory
import "../js/util.js" as Util

Item {
    id: view

    property var applet
    /** highlight and scroll to the line that is playing (used by the Both tab) */
    property bool follow: false
    property bool showDiagrams: true

    // Index of the chart row the song has reached, or -1. The chart itself has
    // no timings, so this comes from the schedule built out of the synced lyrics.
    property int activeRow: -1

    readonly property var chart: applet ? applet.chart : null
    readonly property var sections: (chart && chart.sections) ? chart.sections : []
    readonly property bool hasChart: sections.length > 0
    readonly property int semitones: applet ? applet.effectiveTranspose : 0
    /** easy-chord reading and the reading pace used by auto-scroll */
    readonly property bool simplify: applet ? applet.simplifyChords : false
    readonly property int scrollSpeed: applet ? applet.scrollSpeed : 5
    readonly property var shapes: applet ? applet.shapes : ({})
    readonly property var chordNames: applet ? applet.displayChords : []
    readonly property bool hasPaste: !!(chart && chart.source === "local" && chart.editable)

    readonly property int fontDelta: applet ? applet.fontSizeOffset : 0

    // A QML font is a value type: mutating a copy of a theme font is thrown
    // away before it reaches the Text, so it silently ignored the size setting.
    // Build a fresh font instead.
    readonly property font chartFont: Qt.font({
        family: Kirigami.Theme.fixedWidthFont.family,
        pointSize: Math.max(1, Kirigami.Theme.fixedWidthFont.pointSize + fontDelta)
    })

    readonly property var rows: {
        var out = []
        for (var i = 0; i < sections.length; i++) {
            var section = sections[i]
            out.push({ kind: "section", name: section.name || "" })
            var lines = section.lines || []
            for (var j = 0; j < lines.length; j++) {
                var line = lines[j]
                out.push({
                    kind: "line",
                    lyric: line.lyric || "",
                    chords: line.chords || [],
                    mono: !!line.mono,
                    instrumental: !!line.instrumental
                })
            }
        }
        return out
    }

    // The applet's position, bounced through a local property of our own: a
    // Connections block cannot resolve a signal on a var-typed target, and the
    // schedule needs to be told when playback moves.
    property real playbackPosition: view.applet ? view.applet.playbackPosition : 0

    // The chart has no timings of its own (tab sites publish none), so the lines
    // being sung come from the synced lyrics and are matched onto the chart rows.
    // Charts and lyric services rarely spell a line the same way - they differ in
    // punctuation, spacing and even transliteration - so rows are scored instead
    // of compared exactly. Taking the active line as an argument keeps this pure,
    // so it can be run over a whole song at once to build the schedule below.
    function scoreLine(rowLyric, activeText) {
        var row = Util.normalize(rowLyric)
        var active = activeText
        if (!row || !active) return 0
        var rowWords = row.split(" ")
        var activeWords = active.split(" ")
        if (!rowWords.length || !activeWords.length) return 0
        // A one-word row ("haan", "main yahin") is a wildcard: it matches any
        // line that merely contains a similar word, and because the scan stops
        // at the first 0.99 that wrong row became an anchor, dragged the cursor
        // forward and ran the whole schedule ahead of the song. Rows that short
        // are left to the interpolation instead.
        if (rowWords.length < 2) return 0
        if (row.indexOf(active) >= 0 || active.indexOf(row) >= 0) return 1
        var hits = 0
        for (var i = 0; i < rowWords.length; i++) {
            var word = rowWords[i]
            if (word.length < 2) continue
            for (var j = 0; j < activeWords.length; j++) {
                if (Util.tokenMatches(word, activeWords[j])) {
                    hits++
                    break
                }
            }
        }
        // Two real words have to agree before a row may anchor a line. Charts
        // break one sung line across two rows (or join two into one), so the
        // score still measures how much of the *shorter* line was found; the
        // floor is what keeps a stray word from claiming a whole verse.
        if (hits < 2) return 0
        return hits / Math.min(rowWords.length, activeWords.length)
    }

    // A wall clock for every chart row: the time at which the song has reached
    // it. Matching a line at a time only tells us where we are while a line
    // happens to match, so a chart that spells things differently, skips
    // repeats, or carries only a fraction of the lyrics left the highlight
    // stuck. Instead the whole song is matched once, in order, and the gaps
    // between matched rows are shared out - so the chart keeps walking down the
    // page even through the parts nothing matched, and it can never jump back.
    property var rowTimes: []
    readonly property var lyricLines: (applet && applet.lyrics) ? applet.lyrics.lines : null

    function buildSchedule() {
        var rows = view.rows
        var times = []
        if (!rows) { view.rowTimes = times; return }
        for (var i = 0; i < rows.length; i++) times.push(null)

        // The backend aligns the chart against the lyric timings with a sequence
        // alignment and sends one time per lyric row.  Prefer it: it is monotonic
        // and cannot be dragged ahead by a stray row, which is what the local
        // match below used to do.  Fall back to the match when the payload
        // predates it.
        var aligned = (applet && applet.chart) ? applet.chart.row_times : null
        if (aligned && aligned.length) {
            var alignedIndex = 0
            for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
                if (rows[rowIndex].kind !== "line") continue
                if (alignedIndex >= aligned.length) break
                var alignedValue = aligned[alignedIndex++]
                if (alignedValue !== null && alignedValue !== undefined) times[rowIndex] = alignedValue
            }
            view.rowTimes = times
            return
        }

        var lines = view.lyricLines || []
        var timed = []
        for (var l = 0; l < lines.length; l++) {
            var stamp = lines[l].t
            if (stamp === null || stamp === undefined) continue
            var text = Util.normalize(lines[l].text || "")
            if (text.length < 3) continue
            timed.push({ t: stamp, text: text })
        }

        if (!timed.length) {
            // No timings to go by (an instrumental, or no lyrics for the song):
            // walk the whole chart evenly across the track, which is still far
            // friendlier than a page that never moves.
            view.fillEvenly(times, rows)
            view.rowTimes = times
            return
        }

        // Forward only, so a repeated chorus takes the *next* occurrence rather
        // than snapping back to the first one.
        var cursor = 0
        var anchors = 0
        for (var n = 0; n < timed.length; n++) {
            var best = -1
            var bestScore = 0
            for (var j = cursor; j < rows.length; j++) {
                if (rows[j].kind !== "line" || !rows[j].lyric) continue
                var score = view.scoreLine(rows[j].lyric, timed[n].text)
                if (score > bestScore) { bestScore = score; best = j }
                if (score >= 0.99) break
            }
            if (best >= 0 && bestScore >= 0.6) {
                // Never re-place a row that already has a time: because the
                // cursor does not advance past the match, a later lyric line
                // could otherwise overwrite the earlier, correct anchor of the
                // same chart row and drag the whole schedule forward.
                if (times[best] === null) times[best] = timed[n].t
                cursor = best + 1
                anchors++
            }
        }
        if (!anchors) {
            // Not one line could be placed on the chart - a very different set of
            // lyrics, or a chart of tablature - so walk it evenly instead.
            view.fillEvenly(times, rows)
            view.rowTimes = times
            return
        }

        // Rows between two known rows get an even share of the time between them;
        // rows before the first or after the last keep the nearest known time, so
        // a lead-in or an outro still holds the highlight sensibly.
        var previous = -1
        for (var k = 0; k < times.length; k++) {
            if (times[k] === null) continue
            if (previous >= 0) {
                var span = k - previous
                for (var m = 1; m < span; m++) {
                    if (times[previous + m] === null)
                        times[previous + m] = times[previous] + (times[k] - times[previous]) * m / span
                }
            }
            previous = k
        }
        // Rows before the first match and after the last one share out the time
        // to the edges of the track, so a long intro or outro keeps the chart
        // moving instead of pinning the highlight to one row.
        var firstKnown = -1
        var lastKnown = -1
        for (var q = 0; q < times.length; q++) {
            if (times[q] === null) continue
            if (firstKnown < 0) firstKnown = q
            lastKnown = q
        }
        for (var b = 0; b < firstKnown; b++)
            times[b] = times[firstKnown] * (b + 1) / (firstKnown + 1)
        var end = (applet && applet.lengthSec) ? applet.lengthSec : times[lastKnown]
        if (!(end > times[lastKnown])) end = times[lastKnown]
        var tail = times.length - 1 - lastKnown
        for (var e = lastKnown + 1; e < times.length; e++)
            times[e] = times[lastKnown] + (end - times[lastKnown]) * (e - lastKnown) / (tail + 1)

        view.rowTimes = times
    }

    /** Spread a track's length evenly over the rows: the fallback when there is
     *  nothing to match against, so the chart still walks instead of freezing. */
    function fillEvenly(times, rows) {
        var length = (view.applet && view.applet.lengthSec) ? view.applet.lengthSec : 0
        if (!(length > 0)) return
        var total = 0
        for (var r = 0; r < rows.length; r++) if (rows[r].kind === "line") total++
        var seen = 0
        for (var s = 0; s < rows.length; s++) {
            if (rows[s].kind !== "line") continue
            times[s] = total > 1 ? length * seen / total : 0
            seen++
        }
    }

    function rowForPosition(position) {
        var times = view.rowTimes
        if (!times || !times.length) return -1
        var found = -1
        for (var i = 0; i < times.length; i++) {
            if (times[i] === null) continue
            if (times[i] <= position - (view.applet ? view.applet.syncLag : 0.25)) found = i
            else break
        }
        return found
    }

    function followPosition() {
        // No highlight while the shown chart still belongs to the previous track.
        if (!view.follow || (view.applet && view.applet.stale)) return
        var target = view.rowForPosition(view.playbackPosition)
        if (target < 0 || target === view.activeRow) return
        view.activeRow = target
        // Keep the line in view, but never drag the page while the user is
        // looking somewhere else on it.
        // Lyric sync alone means "keep the line being played in view"; auto-scroll
        // is the separate, song-independent reading scroll used when sync is off.
        if (!view.applet) return
        if (Date.now() - view.lastUserScroll < 4000) return
        view.scrollToRow(target)
    }

    // Glide to the line rather than jumping to it. Qt has no animated
    // positionViewAtIndex, so aim the view's contentY at the row and let a
    // NumberAnimation take it there; the higher the speed, the shorter the
    // glide. The row is placed `contextLines` below the top so the rows just
    // sung stay visible. A row far off-screen has no delegate yet, so jump
    // first and then back off by the same margin.
    function scrollToRow(index) {
        var item = list.itemAtIndex(index)
        var lead = view.contextLines * (item && item.height > 0 ? item.height : Kirigami.Units.gridUnit * 2)
        if (!item) list.positionViewAtIndex(index, ListView.Beginning)
        var limit = Math.max(0, list.contentHeight - list.height)
        var dest = Math.max(0, Math.min(limit, (item ? item.y : list.contentY) - lead))
        if (Math.abs(dest - list.contentY) < 1) return
        followScroll.stop()
        followScroll.to = dest
        followScroll.start()
    }

    /** jump back to the top of the song */
    function scrollToTop() {
        // Treat it like a manual scroll so follow mode and the reading scroll
        // do not yank the view straight back down.
        view.lastUserScroll = Date.now()
        followScroll.stop()
        followScroll.to = 0
        followScroll.start()
    }

    function rebuildSchedule() {
        view.buildSchedule()
        view.activeRow = -1
        view.followPosition()
    }

    property double lastUserScroll: 0

    // How many rows already sung stay visible above the active one.
    property int contextLines: 4

    // Smooth scroll for follow mode.
    NumberAnimation {
        id: followScroll
        target: list
        property: "contentY"
        duration: Math.max(80, 760 - view.scrollSpeed * 70)
        easing.type: Easing.InOutQuad
    }

    // A steady scroll for reading a chart without lyric sync: the same control
    // the Ultimate Guitar viewer has. Runs only while auto-scroll is on and
    // sync is off, and pauses for a few seconds after any manual scroll.
    Timer {
        interval: 40
        repeat: true
        running: !!view.applet && view.applet.autoScroll && !view.follow
                 && list.contentHeight > list.height + 1
        onTriggered: {
            if (Date.now() - view.lastUserScroll < 3000) return
            var limit = Math.max(0, list.contentHeight - list.height)
            if (list.contentY >= limit - 0.5) return
            list.contentY = Math.min(limit, list.contentY + view.scrollSpeed * 0.12)
        }
    }

    onRowsChanged: view.rebuildSchedule()
    onLyricLinesChanged: view.rebuildSchedule()
    onPlaybackPositionChanged: view.followPosition()
    onChartChanged: view.rebuildSchedule()

    /** scroll the chart by a few lines, for keyboard control */
    function nudge(dy) {
        var limit = Math.max(0, list.contentHeight - list.height)
        list.contentY = Math.max(0, Math.min(limit, list.contentY + dy))
    }

    // Which diagram is called out right now, and the chords of the section being
    // played: the strip shows those rather than the first 24 of the whole song.
    property string highlightChord: ""
    // The section the song is in, as a row index. Kept as a number so the strip
    // below only rebuilds when the song really moves on: handing it a fresh
    // array on every line would throw away and redraw every diagram with it.
    readonly property int sectionStart: {
        if (view.activeRow < 0 || !view.rows || !view.rows.length) return -1
        var start = -1
        for (var i = 0; i <= view.activeRow && i < view.rows.length; i++) {
            if (view.rows[i].kind === "section") start = i
        }
        return start
    }

    readonly property var sectionChords: {
        if (view.sectionStart < 0 || !view.sections.length) return view.chordNames
        var names = []
        for (var j = view.sectionStart + 1; j < view.rows.length; j++) {
            var row = view.rows[j]
            if (row.kind === "section") break
            var chords = row.chords || []
            for (var k = 0; k < chords.length; k++) {
                var name = Theory.chordName(chords[k].name, view.semitones, view.simplify)
                if (names.indexOf(name) < 0) names.push(name)
            }
        }
        return names.length >= 2 ? names : view.chordNames
    }

    /** Bring a chord's diagram into view and mark it. */
    function showChord(name) {
        if (!name) return
        view.highlightChord = name
        var index = view.sectionChords.indexOf(name)
        if (index < 0) return
        var item = diagramRow.children[index]
        if (!item) return
        diagramFlick.contentX = Math.max(0, Math.min(diagramFlick.contentWidth - diagramFlick.width,
                                                    item.x - diagramFlick.width / 2 + item.width / 2))
        highlightTimer.restart()
    }
    Timer { id: highlightTimer; interval: 2500; onTriggered: view.highlightChord = "" }

    /** Which chord sits under a character of a line's chord row. */
    function chordAt(chords, charIndex) {
        if (!chords) return ""
        for (var i = 0; i < chords.length; i++) {
            var name = Theory.chordName(chords[i].name, view.semitones, view.simplify)
            var start = chords[i].pos
            if (charIndex >= start && charIndex <= start + name.length) return name
        }
        return ""
    }

    /** Every voicing we have for a chord, falling back to its single shape. */
    function variantsFor(name) {
        var variants = (view.applet && view.applet.shapeVariants) ? view.applet.shapeVariants[name] : null
        if (variants && variants.length) return variants
        var single = view.shapes[name]
        return single ? [single] : []
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        visible: view.hasChart

        Rectangle {
            id: diagramStrip
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? Kirigami.Units.gridUnit * 4.4 : 0
            visible: view.showDiagrams && view.chordNames.length > 0
            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.05)

            Flickable {
                id: diagramFlick
                anchors.fill: parent
                anchors.margins: Kirigami.Units.smallSpacing
                contentWidth: diagramRow.width
                contentHeight: height
                flickableDirection: Flickable.HorizontalFlick
                clip: true

                Row {
                    id: diagramRow
                    spacing: Kirigami.Units.largeSpacing
                    Repeater {
                        model: view.sectionChords
                        // One slot per chord, showing its default voicing. The
                        // other voicings wait behind it: click or wheel to cycle
                        // through them, so a busy section stays readable.
                        delegate: Item {
                            id: chordGroup
                            readonly property string chordName: modelData
                            readonly property var variants: view.variantsFor(chordGroup.chordName)
                            readonly property int variantCount: variants ? variants.length : 0
                            // Which voicing of this chord is on show.
                            property int voicing: 0

                            visible: variantCount > 0
                            width: visible ? implicitWidth : 0
                            height: diagramStrip.height - Kirigami.Units.smallSpacing * 2
                            implicitWidth: diagram.implicitWidth
                            implicitHeight: diagram.implicitHeight

                            function cycle(step) {
                                if (variantCount < 2) return
                                voicing = (voicing + step + variantCount) % variantCount
                            }

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: -Kirigami.Units.smallSpacing / 2
                                radius: Kirigami.Units.smallSpacing / 2
                                color: Kirigami.Theme.highlightColor
                                opacity: view.highlightChord === chordGroup.chordName ? 0.22 : 0
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                            }

                            ChordDiagram {
                                id: diagram
                                anchors.fill: parent
                                anchors.bottomMargin: chordGroup.variantCount > 1 ? Kirigami.Units.smallSpacing * 1.4 : 0
                                shape: chordGroup.variantCount
                                    ? chordGroup.variants[Math.min(chordGroup.voicing, chordGroup.variantCount - 1)]
                                    : null
                                lineColor: Kirigami.Theme.textColor
                                dotColor: Kirigami.Theme.highlightColor
                            }

                            // A dot per voicing, the filled one being the shape on
                            // show; only worth the space when there is a choice.
                            Row {
                                visible: chordGroup.variantCount > 1
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                spacing: Kirigami.Units.smallSpacing / 2
                                Repeater {
                                    model: chordGroup.variantCount
                                    delegate: Rectangle {
                                        width: Kirigami.Units.smallSpacing
                                        height: width
                                        radius: width / 2
                                        color: Kirigami.Theme.textColor
                                        opacity: index === chordGroup.voicing ? 1 : 0.3
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: chordGroup.variantCount > 1 ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: chordGroup.cycle(1)
                                // The wheel cycles the voicings too. MouseArea's own
                                // wheel signal is used because WheelHandler has no
                                // `accepted` property - assigning one is a load-time
                                // error that takes the whole applet down.
                                onWheel: function (wheel) {
                                    if (chordGroup.variantCount < 2) return
                                    chordGroup.cycle(wheel.angleDelta.y > 0 ? 1 : -1)
                                    wheel.accepted = true
                                }
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            visible: diagramStrip.visible
            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: view.rows
            boundsBehavior: Flickable.StopAtBounds

            onMovementStarted: view.lastUserScroll = Date.now()
            onFlickStarted: view.lastUserScroll = Date.now()

            delegate: Item {
                id: row
                width: ListView.view.width
                implicitHeight: content.implicitHeight + Kirigami.Units.smallSpacing * 1.5
                height: implicitHeight

                readonly property var entry: modelData
                readonly property bool isSection: entry.kind === "section"
                readonly property bool active: !isSection && index === view.activeRow

                readonly property string chordText: {
                    if (isSection || !entry.chords || !entry.chords.length) return ""
                    if (entry.instrumental) {
                        var names = []
                        for (var i = 0; i < entry.chords.length; i++)
                            names.push(Theory.chordName(entry.chords[i].name, view.semitones, view.simplify))
                        return names.join("    ")
                    }
                    return Theory.chordLine(entry.chords, view.semitones, view.simplify)
                }

                Rectangle {
                    anchors.fill: parent
                    radius: Kirigami.Units.smallSpacing / 2
                    color: Kirigami.Theme.highlightColor
                    opacity: row.active ? 0.14 : 0
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                }

                Column {
                    id: content
                    x: Kirigami.Units.smallSpacing
                    width: parent.width - Kirigami.Units.smallSpacing * 2
                    spacing: 0

                    PlasmaComponents3.Label {
                        visible: row.isSection
                        width: parent.width
                        text: row.isSection ? row.entry.name : ""
                        font.weight: Font.DemiBold
                        font.pointSize: Math.max(1, Kirigami.Theme.smallFont.pointSize + view.fontDelta)
                        color: Kirigami.Theme.highlightColor
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    Text {
                        id: chordRow
                        visible: !row.isSection && text.length > 0
                        width: parent.width
                        text: row.chordText
                        font: view.chartFont
                        color: Kirigami.Theme.highlightColor
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight

                        // Clicking a chord name brings its diagram into view.
                        MouseArea {
                            anchors.fill: parent
                            enabled: !!(row.entry && !row.entry.instrumental)
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (charMetrics.width <= 0) return
                                view.showChord(view.chordAt(row.entry.chords, Math.floor(mouse.x / charMetrics.width)))
                            }
                        }

                        TextMetrics {
                            id: charMetrics
                            font: chordRow.font
                            text: "0"
                        }
                    }

                    Text {
                        visible: !row.isSection && text.length > 0
                        width: parent.width
                        text: row.isSection ? "" : (row.entry.lyric || "")
                        font: view.chartFont
                        color: row.active ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
                        opacity: row.active ? 1 : 0.85
                        wrapMode: row.entry && row.entry.mono ? Text.NoWrap : Text.WrapAnywhere
                        elide: row.entry && row.entry.mono ? Text.ElideRight : Text.ElideNone

                        // Clicking a line sends the song to that line's time, so
                        // the chord sheet works like the lyrics page in reverse.
                        // The row's time comes from the aligned schedule.
                        MouseArea {
                            anchors.fill: parent
                            enabled: !row.isSection && !!view.applet
                                     && view.rowTimes[index] !== undefined && view.rowTimes[index] !== null
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                var t = view.rowTimes[index]
                                if (t !== undefined && t !== null && view.applet) view.applet.seekTo(t)
                            }
                        }
                    }
                }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        visible: !view.hasChart
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            opacity: 0.75
            text: (view.applet && view.applet.loading)
                ? i18n("Looking for chords\u2026")
                : i18n("No chords found for this track")
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            opacity: 0.5
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            visible: view.applet && view.applet.statusMessage === "offline"
            text: i18n("The Chordist service is not running.")
        }

        PasteSheet {
            Layout.fillWidth: true
            Layout.fillHeight: true
            applet: view.applet
            hint: i18n("Paste a chord sheet below (Ultimate Guitar format or ChordPro). It is saved for this track and always wins over the internet.")
        }
    }
}

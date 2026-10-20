import QtQuick
import QtQuick.Layouts
import QtCore
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami
import org.kde.plasma.private.mpris as Mpris
import "../js/theory.js" as Theory

PlasmoidItem {
    id: root

    // ---------------------------------------------------------------- config
    readonly property string serviceUrl: {
        var url = plasmoid.configuration.serviceUrl || "http://127.0.0.1:8788"
        return url.replace(/\/+$/, "")
    }
    readonly property bool autoScroll: plasmoid.configuration.autoScroll
    // Highlight the line being sung and keep it in step with playback. Turning
    // it off freezes the highlight; scrolling is separately gated by autoScroll.
    readonly property bool lyricSync: plasmoid.configuration.lyricSync
    readonly property bool showChordDiagrams: plasmoid.configuration.showChordDiagrams
    // Ultimate Guitar keeps an easy-chord switch and a reading-speed slider on
    // its tab toolbar; these mirror them.
    readonly property bool simplifyChords: plasmoid.configuration.simplifyChords
    readonly property int scrollSpeed: plasmoid.configuration.scrollSpeed
    // Two tabs only: 0 = Lyrics, 1 = Chords. Anything unrecognised (including a
    // "both" left over from before the Both tab was removed) opens on Chords.
    readonly property int defaultTabIndex: plasmoid.configuration.defaultTab === "lyrics" ? 0 : 1
    readonly property int fontSizeOffset: plasmoid.configuration.fontSizeOffset
    // How opaque our own backdrop is, 0..1. The Plasma popup background is
    // translucent and this desktop's Plasma theme is glassy, so the lyrics need
    // a backing of their own to stay readable.
    readonly property real backgroundOpacity: {
        var value = plasmoid.configuration.backgroundOpacity
        return (value === undefined ? 96 : value) / 100
    }
    readonly property bool openAsWindow: plasmoid.configuration.openAsWindow

    // Quick toggles for the toolbar. Both write straight back to the saved
    // configuration, so the applet comes back the way it was left.
    function toggleLyricSync() {
        plasmoid.configuration.lyricSync = !plasmoid.configuration.lyricSync
    }
    function toggleAutoScroll() {
        plasmoid.configuration.autoScroll = !plasmoid.configuration.autoScroll
    }
    function toggleChordDiagrams() {
        plasmoid.configuration.showChordDiagrams = !plasmoid.configuration.showChordDiagrams
    }
    // The chord text is fixed-width, so a step is a whole point of the chart
    // font. Clamped to the same range the settings page offers (-4..10) so a
    // toolbar button and the KCM can never disagree.
    function adjustFontSize(delta) {
        var next = root.fontSizeOffset + delta
        if (next < -4) next = -4
        if (next > 10) next = 10
        plasmoid.configuration.fontSizeOffset = next
    }
    function toggleSimplifyChords() {
        plasmoid.configuration.simplifyChords = !plasmoid.configuration.simplifyChords
    }
    // Clamped to the same 1..10 the settings page and toolbar slider offer.
    function setScrollSpeed(value) {
        var next = Math.round(value)
        if (next < 1) next = 1
        if (next > 10) next = 10
        plasmoid.configuration.scrollSpeed = next
    }

    // Nudge applied to the lyrics, for when the timings that came back do not
    // match this particular release. Remembered per song.
    property real lyricsOffset: 0
    readonly property real playbackPosition: positionSec + lyricsOffset
    // A timed line must never light up before the song reaches it. The views
    // highlight up to this many seconds AFTER a line's timestamp, which absorbs
    // the output path's own latency (a browser's media clock runs ahead of the
    // sound that has actually left the speakers). Keeping this positive is what
    // makes "lyrics can never run ahead of the song" true.
    readonly property real syncLag: 0.25
    readonly property string offsetLabel: {
        var sign = lyricsOffset > 0 ? "+" : (lyricsOffset < 0 ? "\u2212" : "")
        return sign + Math.abs(lyricsOffset).toFixed(1) + "s"
    }
    // A lyrics entry or a tab picked by hand, when the automatic match is wrong.
    property string pinnedLyricsId: ""
    property string pinnedChordUrl: ""
    property var versions: null
    property bool versionsOpen: false

    // Lyrics script. -1 follows the service's rule (romanise when the chord
    // chart for the song is romanised, so both read the same), 0 keeps the
    // original script, 1 romanises whatever script it is in.
    property int romaniseChoice: -1
    readonly property bool lyricsRomanised: !!(song && song.lyrics && song.lyrics.romanised)

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
    // Only while nothing is playing: when the player we are showing is the one
    // playing, there is nothing to look for, so there is no reason to walk the
    // player list twice a second.
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
    readonly property string track: player && player.track ? player.track : ""
    readonly property string artist: player && player.artist ? player.artist : ""
    readonly property string album: player && player.album ? player.album : ""
    readonly property string artUrl: player && player.artUrl ? player.artUrl : ""
    readonly property string identity: player && player.identity ? player.identity : ""
    readonly property int playbackStatus: player ? player.playbackStatus : Mpris.PlaybackStatus.Stopped
    readonly property bool playing: playbackStatus === Mpris.PlaybackStatus.Playing
    readonly property bool ready: track.length > 0 || artist.length > 0
    readonly property real lengthSec: player && player.length > 0 ? player.length / 1000000 : 0

    property real positionSec: 0
    // MPRIS only answers a Position request on demand, the reply is asynchronous
    // and some players refresh it only on state changes, so reading it straight
    // after updatePosition() is up to a tick stale — enough to make the highlight
    // drift. Anchor to each reported value and extrapolate with the monotonic
    // clock so the position stays accurate between samples.
    property real _anchorPos: 0
    property double _anchorTime: 0
    property bool _anchored: false
    function syncPosition() {
        if (!player) { positionSec = 0; _anchored = false; return }
        var reported = player.position / 1000000
        if (!_anchored || Math.abs(reported - _anchorPos) > 0.05) {
            _anchorPos = reported
            _anchorTime = Date.now()
            _anchored = true
        }
        positionSec = _anchorPos + (playing ? (Date.now() - _anchorTime) / 1000 : 0)
    }
    Timer {
        interval: 500
        repeat: true
        running: root.playing
        onTriggered: {
            if (root.player) {
                root.player.updatePosition()
                root.syncPosition()
            }
        }
    }
    // Re-extrapolate between MPRIS samples so the highlight glides instead of
    // stepping once every sample.
    Timer {
        interval: 200
        repeat: true
        running: root.playing
        onTriggered: if (root._anchored) root.syncPosition()
    }
    onPlayerChanged: syncPosition()
    onTrackChanged: {
        syncPosition()
        // The lyrics/chart on screen belong to the previous song until the new
        // answer lands, so stop highlighting them against the new position.
        stale = true
        // A new song gets a fresh allowance of retries.
        retryCount = 0
        // The stored pick belongs to the previous song, so forget it; the answer
        // for the new song brings its own.
        pinnedLyricsId = ""
        pinnedChordUrl = ""
        if (ready) refetch.restart()
    }

    // ------------------------------------------------------- service payload
    property var song: null
    property var shapes: ({})
    // Every voicing of each chord, keyed by chord name, for the diagram strip.
    property var shapeVariants: ({})
    property var statusMessage: ""
    property bool loading: false
    // True while the shown lyrics/chart still belong to the previous track: the
    // views suppress the highlight until the answer for the new track arrives.
    property bool stale: false
    property int retryCount: 0
    property int transpose: 0
    property int capo: 0

    readonly property var lyrics: song && song.lyrics ? song.lyrics : null
    readonly property var chart: song && song.chords ? song.chords : null

    // Ultimate Guitar writes a tab's chord names as the SHAPES you fret above
    // the capo it states. So the sounding chord is the shape raised by
    // `chartCapo` semitones. The applet's own capo control is the capo you will
    // actually use: `capo === chartCapo` shows the tab exactly as written, and
    // `capo = 0` transposes it to the real chords you can play without a capo.
    readonly property int chartCapo: (chart && chart.capo) ? chart.capo : 0
    readonly property int effectiveTranspose: transpose + chartCapo - capo
    readonly property var displayChords: Theory.uniqueNames(chart ? chart.sections : null, effectiveTranspose, simplifyChords)

    // Whether a Lyrics tab is worth offering at all. The applet is chord-first,
    // so a song with no lyrics should not show one.
    readonly property bool lyricsAvailable: !!(lyrics && lyrics.lines && lyrics.lines.length)

    // Only claim a spot on the panel while the current song actually has a
    // chord chart. A track with nothing recognised (or silence) hides the icon
    // entirely instead of leaving a dead one behind. The previous song's chart
    // stays in `song` until the new fetch lands, so the icon does not blink on
    // every track change.
    readonly property bool chordsAvailable: !!(chart && chart.sections && chart.sections.length > 0)

    onDisplayChordsChanged: shapeDebounce.restart()
    onEffectiveTransposeChanged: shapeDebounce.restart()

    Timer { id: shapeDebounce; interval: 150; onTriggered: root.refreshShapes(root.displayChords) }

    // ------------------------------------------------------------ networking
    function apiGet(path, callback) {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", serviceUrl + path)
        xhr.timeout = 90000
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status === 200) {
                try { callback(JSON.parse(xhr.responseText)) }
                catch (e) { callback(null, "bad response") }
            } else {
                callback(null, xhr.status === 0 ? "offline" : ("http " + xhr.status))
            }
        }
        xhr.send()
    }

    function fetchSong() {
        if (!ready) return
        loading = true
        statusMessage = ""
        var query = "/api/song?artist=" + encodeURIComponent(artist)
                  + "&title=" + encodeURIComponent(track)
                  + "&album=" + encodeURIComponent(album)
                  + "&duration=" + Math.round(lengthSec)
                  + (romaniseChoice >= 0 ? "&romanise=" + romaniseChoice : "")
                  + (pinnedLyricsId ? "&lyrics_id=" + encodeURIComponent(pinnedLyricsId) : "")
                  + (pinnedChordUrl ? "&chord_url=" + encodeURIComponent(pinnedChordUrl) : "")
        apiGet(query, function (data, error) {
            loading = false
            if (error) {
                statusMessage = error
                return
            }
            song = data
            stale = false
            shapes = data.shapes || ({})
            shapeVariants = data.variations || ({})
            applyPrefs(data.prefs || ({}), data.chords ? data.chords.capo : 0)
            if (!data.lyrics && (!data.chords || !(data.chords.sections || []).length))
                statusMessage = "nothing"
        })
    }

    // Put the song back the way it was left: nudge, key and any tab or lyrics
    // entry that was picked by hand.
    function applyPrefs(prefs, tabCapo) {
        lyricsOffset = prefs.offset !== undefined && prefs.offset !== null ? prefs.offset : 0
        transpose = prefs.transpose !== undefined && prefs.transpose !== null ? prefs.transpose : 0
        // With no capo saved for this song, start from the tab's own capo so the
        // chart reads exactly as Ultimate Guitar wrote it.
        capo = prefs.capo !== undefined && prefs.capo !== null ? prefs.capo : (tabCapo || 0)
        pinnedLyricsId = prefs.lyrics_id || ""
        pinnedChordUrl = prefs.chord_url || ""
    }

    function refreshShapes(names) {
        if (!names || !names.length) { shapes = ({}); shapeVariants = ({}); return }
        apiGet("/api/shapes?names=" + encodeURIComponent(names.join(",")), function (data, error) {
            if (error || !data) return
            if (data.shapes) shapes = data.shapes
            if (data.variations) shapeVariants = data.variations
        })
    }

    function submitPaste(text) {
        if (!text) return
        var xhr = new XMLHttpRequest()
        xhr.open("POST", serviceUrl + "/api/paste")
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.timeout = 30000
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status === 200) root.fetchSong()
            else root.statusMessage = "could not save"
        }
        xhr.send(JSON.stringify({ artist: artist, title: track, text: text }))
    }

    Timer { id: refetch; interval: 350; onTriggered: root.fetchSong() }
    onArtistChanged: {
        // A new artist identifies a new track even when the title repeats.
        stale = true
        retryCount = 0
        if (ready) refetch.restart()
    }
    Component.onCompleted: if (ready) refetch.restart()

    // A song the service has nothing for must not become a request every five
    // seconds for as long as it plays: retry promptly while the service looks
    // down, occasionally for "nothing found", and then not at all until the
    // track changes.
    Timer {
        interval: root.statusMessage === "offline" ? 5000 : 30000
        repeat: true
        running: root.statusMessage === "offline"
            || (root.statusMessage === "nothing" && root.retryCount < 6)
        onTriggered: {
            root.retryCount++
            root.fetchSong()
        }
    }

    // --------------------------------------------------------- lyric timing
    function nudgeOffset(seconds) {
        var value = Math.max(-20, Math.min(20, lyricsOffset + seconds))
        lyricsOffset = Math.round(value * 20) / 20
        prefsSave.restart()
    }

    // "That line starts now": pull the nearest timestamp onto the current
    // position, which fixes a whole song's drift in one press.
    function syncOffset() {
        if (!lyrics || !lyrics.lines || !lyrics.lines.length) return
        var best = null
        for (var i = 0; i < lyrics.lines.length; i++) {
            var stamp = lyrics.lines[i].t
            if (stamp === null || stamp === undefined) continue
            var delta = Math.abs((stamp - lyricsOffset) - positionSec)
            if (best === null || delta < best.delta) best = { delta: delta, stamp: stamp }
        }
        if (!best) return
        lyricsOffset = Math.round((best.stamp - positionSec) * 20) / 20
        prefsSave.restart()
    }

    // The service remembers all of this per song; the widget just tells it what
    // changed, a moment after the last click.
    function savePrefs() {
        if (!ready) return
        var xhr = new XMLHttpRequest()
        xhr.open("POST", serviceUrl + "/api/prefs")
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.timeout = 15000
        xhr.send(JSON.stringify({
            artist: artist,
            title: track,
            offset: lyricsOffset,
            transpose: transpose,
            capo: capo,
            lyrics_id: pinnedLyricsId,
            chord_url: pinnedChordUrl
        }))
    }
    Timer { id: prefsSave; interval: 700; onTriggered: root.savePrefs() }
    onTransposeChanged: prefsSave.restart()
    onCapoChanged: prefsSave.restart()

    // ------------------------------------------------------------- versions
    function openVersions() {
        if (!ready) return
        versionsOpen = true
        if (versions) return
        apiGet("/api/versions?artist=" + encodeURIComponent(artist)
               + "&title=" + encodeURIComponent(track)
               + "&album=" + encodeURIComponent(album)
               + "&duration=" + Math.round(lengthSec), function (data, error) {
            if (!error) versions = data
        })
    }
    function closeVersions() { versionsOpen = false }
    function chooseVersion(kind, item) {
        if (!item) return
        if (kind === "lyrics") pinnedLyricsId = item.id === undefined || item.id === null ? "" : String(item.id)
        else pinnedChordUrl = item.url || ""
        versionsOpen = false
        prefsSave.restart()
        fetchSong()
    }
    function clearPins() {
        pinnedLyricsId = ""
        pinnedChordUrl = ""
        versionsOpen = false
        prefsSave.restart()
        fetchSong()
    }

    // ------------------------------------------------------------- transport
    function togglePlay() { if (player) player.PlayPause() }
    function nextTrack() { if (player) player.Next() }
    function previousTrack() { if (player) player.Previous() }
    function seekTo(seconds) {
        if (!player || seconds < 0) return
        player.position = Math.max(0, Math.round(seconds * 1000000))
        // Move the local anchor as well, so the highlight lands on the clicked
        // line at once instead of waiting up to half a second for the next MPRIS
        // poll.  This is the other half of the sync: playback drives the
        // highlight, and a click drives playback.
        _anchorPos = Math.max(0, seconds)
        _anchorTime = Date.now()
        _anchored = true
        positionSec = Math.max(0, seconds)
    }

    // ------------------------------------------------------ floating window
    // A detached copy of the same view in a real window, for when the popup is
    // too transient (it closes as soon as it loses focus). Opened from the
    // popup's window button, or straight from a click on the panel item when
    // "Floating window" is set in the settings.
    //
    // Staying above other windows is not something a Wayland client can ask for
    // - Qt's WindowStaysOnTopHint is ignored under xdg-shell - so that is KDE's
    // business: Keep Above from the title-bar menu, or a window rule to make it
    // stick. That same flag is what the kwin-canvas effect reads to decide
    // which windows it lets float around the canvas.
    property bool windowVisible: false
    function toggleWindow() { windowVisible = !windowVisible }
    // Something opening is the moment to put the tab back where the user wants
    // it: the popup and the window are each built once and then reused, so
    // without this the tab would stay wherever it was left last time.
    property int openCount: 0
    onExpandedChanged: if (expanded) openCount++
    onWindowVisibleChanged: if (windowVisible) openCount++
    // Esc, from inside either the popup or the window: close whichever is open.
    function closeSelf() {
        if (windowVisible) windowVisible = false
        else expanded = false
    }

    // Where the window was left. Qt's own Settings type keeps these out of the
    // widget's saved configuration.
    Settings {
        id: uiSettings
        category: "lyricist"
        property alias storedX: floating.x
        property alias storedY: floating.y
        property alias storedWidth: floating.width
        property alias storedHeight: floating.height
        property bool hasGeometry: false
    }

    // Flip the lyrics between their own script and a romanised reading. The
    // transliteration happens in the service, so this just refetches with the
    // opposite wish and remembers it for the rest of the session.
    function toggleRomanise() {
        romaniseChoice = lyricsRomanised ? 0 : 1
        fetchSong()
    }

    Window {
        id: floating
        visible: root.windowVisible
        flags: Qt.Window
        title: root.ready ? (root.artist ? root.track + " \u2014 " + root.artist + " \u2014 Chordist" : root.track + " \u2014 Chordist") : "Chordist"
        color: Kirigami.Theme.backgroundColor
        width: Kirigami.Units.gridUnit * 30
        height: Kirigami.Units.gridUnit * 26
        minimumWidth: Kirigami.Units.gridUnit * 18
        minimumHeight: Kirigami.Units.gridUnit * 14

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

        Shortcut {
            sequence: "Esc"
            context: Qt.WindowShortcut
            onActivated: root.windowVisible = false
        }

        // Built only while the window is open: a second live copy of the whole
        // view - its own list views, its own chart schedule - is not something
        // to keep around for a window nobody is looking at.
        Loader {
            anchors.fill: parent
            active: root.windowVisible
            sourceComponent: Full {
                applet: root
            }
        }
    }

    compactRepresentation: Compact { applet: root }
    fullRepresentation: Full { applet: root }

    // HiddenStatus makes the containment drop the item from the panel. Keep the
    // icon for anything worth opening - a chart OR lyrics. A lyrics-only song is
    // still useful, and hiding it left no way to reach the widget at all.
    Plasmoid.status: (chordsAvailable || lyricsAvailable) ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.HiddenStatus
    toolTipMainText: ready ? track : i18n("Chordist")
    toolTipSubText: ready ? artist : i18n("Lyrics and chords for whatever you play")
}

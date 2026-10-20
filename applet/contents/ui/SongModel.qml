import QtQuick
import "../js/theory.js" as Theory
import "../js/schedule.js" as Schedule
import "../js/util.js" as Util

// Everything the views know about the song that is playing: what the service
// said, where the song has got to, which chord is sounding, what capo would make
// it easy. No Plasma types in here, so it can be tested on its own and driven
// from a harness; main.qml only wires the media player and the configuration
// into it.
QtObject {
    id: model

    // ------------------------------------------------------------- inputs
    // Anything with the widget's settings as properties: plasmoid.configuration
    // in the shell, a plain object in tests.
    property var config
    // An MPRIS player (PlayPause(), Next(), position, rate ...) or null.
    property var player: null
    property string track: ""
    property string artist: ""
    property string album: ""
    property string artUrl: ""
    property string identity: ""
    property real lengthSec: 0
    property bool playing: false

    // The widget asks for a window or to be closed; main.qml acts on it.
    signal windowRequested()
    signal closeRequested()
    // Bumped whenever the popup or the window opens, so views can put the tab back.
    property int openCount: 0

    // ------------------------------------------------------------- config
    function cfg(key, fallback) {
        var value = config ? config[key] : undefined
        return value === undefined || value === null ? fallback : value
    }
    function setCfg(key, value) { if (config) config[key] = value }

    readonly property string serviceUrl: String(cfg("serviceUrl", "http://127.0.0.1:8788") || "http://127.0.0.1:8788").replace(/\/+$/, "")
    readonly property bool autoScroll: cfg("autoScroll", true)
    readonly property bool lyricSync: cfg("lyricSync", true)
    readonly property bool showChordDiagrams: cfg("showChordDiagrams", true)
    readonly property bool showStage: cfg("showStage", true)
    readonly property bool leftHanded: cfg("leftHanded", false)
    readonly property bool showFingers: cfg("showFingerNumbers", true)
    readonly property bool simplifyChords: cfg("simplifyChords", false)
    readonly property int scrollSpeed: cfg("scrollSpeed", 5)
    // Two tabs: 0 = Lyrics, 1 = Chords. Anything unrecognised opens on Chords.
    readonly property int defaultTabIndex: cfg("defaultTab", "chords") === "lyrics" ? 0 : 1
    readonly property int fontSizeOffset: cfg("fontSizeOffset", 0)
    // How opaque our own backdrop is, 0..1: the popup background is translucent
    // and glassy themes make the text unreadable without one of our own.
    readonly property real backgroundOpacity: cfg("backgroundOpacity", 96) / 100

    function toggle(key) { setCfg(key, !cfg(key, false)) }
    function adjustFontSize(delta) { setCfg("fontSizeOffset", Math.max(-4, Math.min(10, fontSizeOffset + delta))) }
    function setScrollSpeed(value) { setCfg("scrollSpeed", Math.max(1, Math.min(10, Math.round(value)))) }

    // ------------------------------------------------------------ playback
    readonly property bool ready: track.length > 0 || artist.length > 0

    property real positionSec: 0
    // A timed line must never light up before the song reaches it: views
    // highlight up to this many seconds AFTER a line's timestamp, which absorbs
    // the output path's own latency (a browser's clock runs ahead of the sound).
    readonly property real syncLag: 0.25
    // Nudge for when the timings do not match this release. Remembered per song.
    property real lyricsOffset: 0
    readonly property real playbackPosition: positionSec + lyricsOffset
    readonly property real playbackRate: player && player.rate > 0 ? player.rate : 1
    readonly property bool canChangeRate: !!player && player.rate !== undefined
        && (player.maximumRate || 0) > (player.minimumRate || 0)

    // MPRIS answers a Position request on demand, asynchronously, and some
    // players only refresh it on state changes, so a straight read is up to a
    // tick stale. Anchor to each reported value and extrapolate on the monotonic
    // clock (scaled by the playback rate) so the position stays accurate.
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
        positionSec = _anchorPos + (playing ? (Date.now() - _anchorTime) / 1000 * playbackRate : 0)
        enforceLoop()
    }
    property Timer _poll: Timer {
        interval: 500; repeat: true; running: model.playing
        onTriggered: if (model.player) { model.player.updatePosition(); model.syncPosition() }
    }
    // Re-extrapolate between samples so highlights glide; much faster while a
    // section loops, so the jump back lands close to the section's end.
    property Timer _glide: Timer {
        interval: model.loopSpan ? 50 : 200; repeat: true; running: model.playing
        onTriggered: if (model._anchored) model.syncPosition()
    }
    onPlayerChanged: syncPosition()
    // Pausing stops the extrapolation; resuming must restart it from where the
    // song was, not from the anchor taken before the pause (which would make the
    // position leap ahead by the length of the pause until the next poll).
    onPlayingChanged: {
        _anchorPos = positionSec
        _anchorTime = Date.now()
    }

    function togglePlay() { if (player) player.PlayPause() }
    function nextTrack() { if (player) player.Next() }
    function previousTrack() { if (player) player.Previous() }
    function seekTo(seconds) {
        if (!player || seconds < 0) return
        player.position = Math.max(0, Math.round(seconds * 1000000))
        // Move the local anchor too, so the highlight lands on the clicked line
        // at once instead of waiting for the next MPRIS poll.
        _anchorPos = Math.max(0, seconds)
        _anchorTime = Date.now()
        _anchored = true
        positionSec = Math.max(0, seconds)
    }
    // Practice speed. Players that cannot change rate ignore this.
    function setRate(rate) {
        if (!canChangeRate) return
        player.rate = Math.max(player.minimumRate, Math.min(player.maximumRate, rate))
        // The extrapolation must switch speed from "now", not from the old anchor.
        _anchorPos = positionSec
        _anchorTime = Date.now()
    }

    // ------------------------------------------------------------ practice loop
    // A section played over and over: {name, start, end} in song seconds.
    property var loopSpan: null
    function enforceLoop() {
        if (!loopSpan || !playing) return
        if (positionSec >= loopSpan.end - 0.05 && positionSec < loopSpan.end + 3) seekTo(loopSpan.start)
    }
    function loopSection(span) { loopSpan = span ? { name: span.name, start: span.start, end: span.end } : null }
    function toggleLoopHere() {
        if (loopSpan) { loopSpan = null; return }
        var here = activeSpan
        if (here) loopSection(here)
    }
    function jumpToSection(span) { if (span) seekTo(span.start) }

    // ------------------------------------------------------- service payload
    property var song: null
    property var shapes: ({})
    // Every voicing of each chord, keyed by chord name, for the diagrams.
    property var shapeVariants: ({})
    property string statusMessage: ""
    property bool loading: false
    // True while the shown lyrics/chart still belong to the previous track.
    property bool stale: false
    property int retryCount: 0
    property int transpose: 0
    property int capo: 0
    // A lyrics entry or tab picked by hand, when the automatic match is wrong.
    property string pinnedLyricsId: ""
    property string pinnedChordUrl: ""
    property var versions: null
    property bool versionsOpen: false
    // -1 follows the service's script rule, 0 keeps the original, 1 romanises.
    property int romaniseChoice: -1
    readonly property bool lyricsRomanised: !!(song && song.lyrics && song.lyrics.romanised)

    readonly property var lyrics: song && song.lyrics ? song.lyrics : null
    readonly property var chart: song && song.chords ? song.chords : null
    readonly property var chartMeta: chart && chart.meta ? chart.meta : ({})
    readonly property bool lyricsAvailable: !!(lyrics && lyrics.lines && lyrics.lines.length)
    readonly property bool chordsAvailable: !!(chart && chart.sections && chart.sections.length > 0)
    // "chords", "tab" or "mixed": what the chart is made of.
    readonly property string chartKind: chart && chart.kind ? chart.kind : "chords"
    readonly property bool hasChordNames: chordsAvailable && chartKind !== "tab"

    // Tab sites write chord names as the SHAPES you fret above the capo they
    // state, so the sounding chord is the shape raised by `chartCapo`. The
    // capo control here is the capo you will actually use: `capo === chartCapo`
    // shows the tab exactly as written, `capo = 0` transposes it to the real
    // chords for playing without one.
    readonly property int chartCapo: (chart && chart.capo) ? chart.capo : 0
    readonly property int effectiveTranspose: transpose + chartCapo - capo
    readonly property var displayChords: Theory.uniqueNames(chart ? chart.sections : null, effectiveTranspose, simplifyChords)

    // Lyrics: which line is being sung, and whether they are worth romanising.
    // A synced file need not begin with a timestamp, so look for any usable one.
    readonly property bool lyricsSynced: {
        var lines = lyrics && lyrics.lines ? lyrics.lines : []
        if (!(lyrics && lyrics.synced)) return false
        for (var i = 0; i < lines.length; i++)
            if (lines[i].t !== null && lines[i].t !== undefined) return true
        return false
    }
    readonly property int lyricActive: lyricsSynced && !stale
        ? Schedule.lyricAt(lyrics.lines, playbackPosition, syncLag) : -1
    readonly property bool lyricsNonLatin: {
        if (lyricsRomanised) return true
        var lines = lyrics && lyrics.lines ? lyrics.lines : []
        for (var i = 0; i < lines.length && i < 6; i++)
            if (Util.hasDevanagari(lines[i].text)) return true
        return false
    }

    // ------------------------------------------------------- guitar analysis
    readonly property var chordCounts: Theory.chordWeights(chart ? chart.sections : null)
    readonly property var chartNames: Theory.orderedNames(chart ? chart.sections : null)
    // The chords as they sound, before any capo shift.
    readonly property var soundingNames: chartNames.map(function (n) {
        return Theory.transposeChord(n, transpose + chartCapo)
    })
    // key: {name, tonic, mode, source}. The tab's own stated key wins when it
    // gives one; otherwise it is worked out from the chords.
    readonly property var keyInfo: {
        if (!hasChordNames) return null
        var weights = {}
        for (var i = 0; i < chartNames.length; i++) weights[soundingNames[i]] = chordCounts[chartNames[i]]
        var detected = Theory.detectKey(soundingNames, weights)
        var stated = chartMeta.tonality || chart.key || ""
        var parsed = stated ? /^\s*([A-Ga-g][#b]?)\s*(m|min|minor)?\b/.exec(stated) : null
        if (parsed) {
            var root = parsed[1].charAt(0).toUpperCase() + parsed[1].slice(1)
            var minor = !!parsed[2]
            var shifted = Theory.transposeChord(root, transpose)
            return {
                name: shifted + (minor ? "m" : ""),
                tonic: Theory.parseChord(shifted).root,
                mode: minor ? "minor" : "major",
                source: "tab"
            }
        }
        return detected ? { name: detected.name, tonic: detected.tonic, mode: detected.mode, source: "chords" } : null
    }
    function romanFor(name) {
        return keyInfo ? Theory.romanNumeral(name, keyInfo.tonic, keyInfo.mode) : null
    }
    function chordWeightsAt(names) {
        var weights = {}
        for (var i = 0; i < chartNames.length; i++) weights[names[i]] = chordCounts[chartNames[i]]
        return weights
    }
    // The easiest capo for these chords, and what it would turn them into.
    // Null when a capo would not make the shapes any easier than they are now.
    readonly property var capoAdvice: {
        if (!hasChordNames || simplifyChords) return null
        var best = Theory.suggestCapo(soundingNames, chordWeightsAt(soundingNames), 7)
        if (!best || best.capo === capo) return null
        var current = Theory.capoCost(soundingNames, chordWeightsAt(soundingNames), capo)
        return best.cost < current - 0.75 ? best : null
    }

    // Voicings: the tab's own fingerings (UG's applicature) first, then ours,
    // without duplicates. The user's pick per chord is remembered for the session.
    property var voicingPick: ({})
    function variantsFor(name) {
        var out = [], seen = {}
        function add(list) {
            for (var i = 0; list && i < list.length; i++) {
                var key = list[i].frets.join(",")
                if (!seen[key]) { seen[key] = true; out.push(list[i]) }
            }
        }
        add(chart && chart.applicature ? chart.applicature[name] : null)
        add(shapeVariants ? shapeVariants[name] : null)
        if (!out.length && shapes && shapes[name]) out.push(shapes[name])
        return out
    }
    function voicingFor(name) {
        var list = variantsFor(name)
        if (!list.length) return null
        return list[Math.min(voicingPick[name] || 0, list.length - 1)]
    }
    function cycleVoicing(name, step) {
        var count = variantsFor(name).length
        if (count < 2) return
        var next = JSON.parse(JSON.stringify(voicingPick))
        next[name] = ((next[name] || 0) + step + count) % count
        voicingPick = next
    }

    // ------------------------------------------------------------ timing
    // The chart as rows (a header per section, then its lines) and a time for
    // each: what the service aligned against the synced lyrics, else evenly
    // spread. The views only draw; nothing else computes this.
    readonly property var chartRows: {
        var out = []
        var sections = chart && chart.sections ? chart.sections : []
        for (var i = 0; i < sections.length; i++) {
            out.push({ kind: "section", name: sections[i].name || "" })
            var lines = sections[i].lines || []
            for (var j = 0; j < lines.length; j++) {
                var line = lines[j]
                out.push({
                    kind: "line", lyric: line.lyric || "", chords: line.chords || [],
                    mono: !!line.mono, instrumental: !!line.instrumental, staff: line.staff || null
                })
            }
        }
        return out
    }
    readonly property var rowTimes: Schedule.rowTimes(chartRows, chart ? chart.row_times : null, lengthSec)
    readonly property var chordEvents: Schedule.chordEvents(chartRows, rowTimes, lengthSec)
    readonly property var spans: Schedule.sectionSpans(chartRows, rowTimes, lengthSec)
    // Nothing is highlighted while what is on screen belongs to the last track.
    // A tab has no timings to follow (its times are only an even spread), so it has no active row.
    readonly property int activeRow: lyricSync && !stale && chartKind !== "tab" ? Schedule.rowAt(rowTimes, playbackPosition, syncLag) : -1
    readonly property var activeSpan: stale ? null : Schedule.spanAt(spans, playbackPosition)
    readonly property var chordState: stale || !hasChordNames ? null : Schedule.chordAt(chordEvents, playbackPosition, syncLag)

    function shown(name) { return name ? Theory.chordName(name, effectiveTranspose, simplifyChords) : "" }
    readonly property string nowChord: chordState && chordState.current ? shown(chordState.current.name) : ""
    readonly property string nextChord: chordState && chordState.next ? shown(chordState.next.name) : ""
    readonly property real nextIn: chordState && chordState.nextIn !== null ? chordState.nextIn : -1
    // How far through the current chord's stay we are, 0..1, for the countdown bar.
    readonly property real chordProgress: {
        if (!chordState || !chordState.current || !chordState.next) return 0
        var span = chordState.next.t - chordState.current.t
        return span > 0 ? Math.max(0, Math.min(1, (playbackPosition - chordState.current.t) / span)) : 0
    }
    readonly property int activeChordRow: chordState && chordState.current ? chordState.current.row : -1
    readonly property int activeChordIndex: chordState && chordState.current ? chordState.current.chord : -1

    // ------------------------------------------------------------ networking
    property var _songRequest: null
    property int _requestId: 0

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
        return xhr
    }
    function apiPost(path, body, callback) {
        var xhr = new XMLHttpRequest()
        xhr.open("POST", serviceUrl + path)
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.timeout = 30000
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE || !callback) return
            callback(xhr.status === 200)
        }
        xhr.send(JSON.stringify(body))
    }

    function fetchSong() {
        if (!ready) return
        // Only the newest request may land: a slow answer for the previous
        // track must not overwrite the one for this track.
        if (_songRequest) _songRequest.abort()
        var id = ++_requestId
        loading = true
        statusMessage = ""
        var query = "/api/song?artist=" + encodeURIComponent(artist)
                  + "&title=" + encodeURIComponent(track)
                  + "&album=" + encodeURIComponent(album)
                  + "&duration=" + Math.round(lengthSec)
                  + (romaniseChoice >= 0 ? "&romanise=" + romaniseChoice : "")
                  + (pinnedLyricsId ? "&lyrics_id=" + encodeURIComponent(pinnedLyricsId) : "")
                  + (pinnedChordUrl ? "&chord_url=" + encodeURIComponent(pinnedChordUrl) : "")
        _songRequest = apiGet(query, function (data, error) {
            if (id !== _requestId) return
            loading = false
            if (error) {
                // An aborted request reports "offline"; a newer one is on its way.
                statusMessage = error
                return
            }
            song = data
            stale = false
            shapes = data.shapes || ({})
            shapeVariants = data.variations || ({})
            voicingPick = ({})
            applyPrefs(data.prefs || ({}), data.chords ? data.chords.capo : 0)
            if (!data.lyrics && (!data.chords || !(data.chords.sections || []).length))
                statusMessage = "nothing"
        })
    }

    // Put the song back the way it was left: nudge, key and any hand-picked
    // tab or lyrics entry.
    function applyPrefs(prefs, tabCapo) {
        lyricsOffset = prefs.offset !== undefined && prefs.offset !== null ? prefs.offset : 0
        transpose = prefs.transpose !== undefined && prefs.transpose !== null ? prefs.transpose : 0
        // With no capo saved, start from the tab's own so it reads as written.
        capo = prefs.capo !== undefined && prefs.capo !== null ? prefs.capo : (tabCapo || 0)
        pinnedLyricsId = prefs.lyrics_id || ""
        pinnedChordUrl = prefs.chord_url || ""
    }

    function refreshShapes(names) {
        if (!names || !names.length) { shapes = ({}); shapeVariants = ({}); return }
        var id = _requestId
        apiGet("/api/shapes?names=" + encodeURIComponent(names.join(",")), function (data, error) {
            if (error || !data || id !== _requestId) return
            if (data.shapes) shapes = data.shapes
            if (data.variations) shapeVariants = data.variations
        })
    }
    property Timer _shapeDebounce: Timer { interval: 150; onTriggered: model.refreshShapes(model.displayChords) }
    onDisplayChordsChanged: _shapeDebounce.restart()

    function submitPaste(text) {
        var value = (text || "").trim()
        if (!value) return
        // A bare Ultimate Guitar address is a request to use that tab.
        if (/^https?:\/\/\S+$/.test(value) && pinChartUrl(value)) return
        apiPost("/api/paste", { artist: artist, title: track, text: text }, function (ok) {
            if (ok) fetchSong()
            else statusMessage = "could not save"
        })
    }

    // Use a specific Ultimate Guitar tab for this song. Anything else is
    // refused here as well as by the service.
    function pinChartUrl(url) {
        var trimmed = (url || "").trim()
        if (!/^https:\/\/([a-z0-9-]+\.)?ultimate-guitar\.com\/\S+$/i.test(trimmed)) return false
        pinnedChordUrl = trimmed
        versionsOpen = false
        _prefsSave.restart()
        fetchSong()
        return true
    }

    property Timer _refetch: Timer { interval: 350; onTriggered: model.fetchSong() }
    Component.onCompleted: if (ready) _refetch.restart()
    onTrackChanged: {
        syncPosition()
        // What is on screen belongs to the previous song until the answer lands.
        stale = true
        retryCount = 0
        pinnedLyricsId = ""
        pinnedChordUrl = ""
        // Another song's alternatives are not this song's alternatives.
        versions = null
        versionsOpen = false
        loopSpan = null
        if (ready) _refetch.restart()
    }
    onArtistChanged: {
        // A new artist identifies a new track even when the title repeats.
        stale = true
        retryCount = 0
        if (ready) _refetch.restart()
    }

    // A song the service has nothing for must not become a request every few
    // seconds for as long as it plays: retry promptly while the service looks
    // down, occasionally for "nothing found", then not at all until the track
    // changes.
    property Timer _retry: Timer {
        interval: model.statusMessage === "offline" ? 5000 : 30000
        repeat: true
        running: model.statusMessage === "offline"
            || (model.statusMessage === "nothing" && model.retryCount < 6)
        onTriggered: { model.retryCount++; model.fetchSong() }
    }

    // ----------------------------------------------------------- lyric timing
    function nudgeOffset(seconds) {
        lyricsOffset = Math.round(Math.max(-20, Math.min(20, lyricsOffset + seconds)) * 20) / 20
        _prefsSave.restart()
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
        _prefsSave.restart()
    }
    readonly property string offsetLabel: {
        var sign = lyricsOffset > 0 ? "+" : (lyricsOffset < 0 ? "−" : "")
        return sign + Math.abs(lyricsOffset).toFixed(1) + "s"
    }

    // The service remembers all of this per song; we tell it what changed, a
    // moment after the last click.
    function savePrefs() {
        if (!ready) return
        apiPost("/api/prefs", {
            artist: artist, title: track, offset: lyricsOffset, transpose: transpose, capo: capo,
            lyrics_id: pinnedLyricsId, chord_url: pinnedChordUrl
        })
    }
    property Timer _prefsSave: Timer { interval: 700; onTriggered: model.savePrefs() }
    onTransposeChanged: _prefsSave.restart()
    onCapoChanged: _prefsSave.restart()

    // ------------------------------------------------------------- versions
    function openVersions() {
        if (!ready) return
        versionsOpen = true
        if (versions) return
        var forTrack = track
        apiGet("/api/versions?artist=" + encodeURIComponent(artist)
               + "&title=" + encodeURIComponent(track)
               + "&album=" + encodeURIComponent(album)
               + "&duration=" + Math.round(lengthSec), function (data, error) {
            if (!error && forTrack === track) versions = data
        })
    }
    function closeVersions() { versionsOpen = false }
    function chooseVersion(kind, item) {
        if (!item) return
        if (kind === "lyrics") pinnedLyricsId = item.id === undefined || item.id === null ? "" : String(item.id)
        else pinnedChordUrl = item.url || ""
        versionsOpen = false
        _prefsSave.restart()
        fetchSong()
    }
    function clearPins() {
        pinnedLyricsId = ""
        pinnedChordUrl = ""
        versionsOpen = false
        _prefsSave.restart()
        fetchSong()
    }

    // Flip the lyrics between their own script and a romanised reading; the
    // transliteration happens in the service, so this just refetches.
    function toggleRomanise() {
        romaniseChoice = lyricsRomanised ? 0 : 1
        fetchSong()
    }
}

// SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
//
// SPDX-License-Identifier: MIT

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
    // What each setting reads as when the configuration does not have it. One
    // table, so a toggle and the property it flips can never disagree.
    readonly property var _defaults: ({
        serviceUrl: "http://127.0.0.1:8788", autoScroll: true, lyricSync: true, showChordDiagrams: true,
        showStage: true, showFingerNumbers: true, leftHanded: false, simplifyChords: false, scrollSpeed: 5,
        defaultTab: "chords", fontSizeOffset: 0, backgroundOpacity: 96, highlightDelayMs: 250, hideWhenEmpty: true
    })
    function cfg(key) {
        var value = config ? config[key] : undefined
        return value === undefined || value === null ? _defaults[key] : value
    }
    function setCfg(key, value) { if (config) config[key] = value }

    readonly property string serviceUrl: String(cfg("serviceUrl") || _defaults.serviceUrl).replace(/\/+$/, "")
    readonly property bool autoScroll: cfg("autoScroll")
    readonly property bool lyricSync: cfg("lyricSync")
    readonly property bool showChordDiagrams: cfg("showChordDiagrams")
    readonly property bool showStage: cfg("showStage")
    readonly property bool leftHanded: cfg("leftHanded")
    readonly property bool showFingers: cfg("showFingerNumbers")
    readonly property bool simplifyChords: cfg("simplifyChords")
    readonly property int scrollSpeed: cfg("scrollSpeed")
    // Two tabs: 0 = Lyrics, 1 = Chords. Anything unrecognised opens on Chords.
    readonly property int defaultTabIndex: cfg("defaultTab") === "lyrics" ? 0 : 1
    readonly property int fontSizeOffset: cfg("fontSizeOffset")
    // How opaque our own backdrop is, 0..1: the popup background is translucent
    // and glassy themes make the text unreadable without one of our own.
    readonly property real backgroundOpacity: cfg("backgroundOpacity") / 100
    // Leave the panel without an icon while the current track has nothing to show (the default), or keep a dimmed
    // one, which is how a chart can be pasted for that track.
    readonly property bool hideWhenEmpty: cfg("hideWhenEmpty")

    function toggle(key) { setCfg(key, !cfg(key)) }
    function adjustFontSize(delta) { setCfg("fontSizeOffset", Math.max(-4, Math.min(10, fontSizeOffset + delta))) }
    function setScrollSpeed(value) { setCfg("scrollSpeed", Math.max(1, Math.min(10, Math.round(value)))) }

    // ------------------------------------------------------------ playback
    readonly property bool ready: track.length > 0 || artist.length > 0
    // True while the popup or the window is on screen (main.qml sets it): the
    // clock then ticks finer and the player is asked where it is more often.
    property bool viewVisible: false

    property real positionSec: 0
    // A timed line must never light up before the song reaches it: views
    // highlight up to this many seconds AFTER a line's timestamp, which absorbs
    // the output path's own latency (a browser's clock runs ahead of the sound;
    // Bluetooth adds a few hundred milliseconds more). A setting, in milliseconds.
    readonly property real syncLag: {
        var ms = Number(cfg("highlightDelayMs"))
        return isFinite(ms) ? Math.max(0, Math.min(2, ms / 1000)) : _defaults.highlightDelayMs / 1000
    }
    // Nudge for when the timings do not match this release. Remembered per song.
    property real lyricsOffset: 0
    // Where the song is on the timings' own clock: what every line, row and chord time is compared with.
    readonly property real playbackPosition: positionSec + lyricsOffset
    readonly property real playbackRate: player && player.rate > 0 ? player.rate : 1
    readonly property bool canChangeRate: !!player && player.rate !== undefined
        && (player.maximumRate || 0) > (player.minimumRate || 0)
    // A player that cannot be sent somewhere (a browser without Plasma Browser Integration) gets no seek cursors.
    readonly property bool canSeek: !!player && player.canSeek !== false

    // ---- the clock
    // MPRIS answers a Position request asynchronously: the value read straight
    // after asking is the previous answer, up to a poll old, and anchoring to it
    // made the highlight run late and stutter. So the player is asked, and its
    // answer is taken when it arrives (positionChanged, which a seek also
    // raises); between answers the position is extrapolated on this machine's
    // clock, scaled by the playback rate. An answer close to the extrapolation
    // only nudges it, so a player that reports in coarse steps cannot make the
    // highlight jitter; a distant one (a seek, a new track) resets it.
    property real _anchorPos: 0
    property double _anchorTime: 0
    // A report has been taken for this anchor; without one the clock runs from
    // wherever it was last set (the top of a new track).
    property bool _anchored: false
    // Nearer than this, a report and the extrapolation are the same moment apart from jitter.
    readonly property real _snapThreshold: 0.3
    // True once this player has reported a moving position. A player that
    // never does (a browser without Plasma Browser Integration) is followed
    // by an estimate counted from the start of the track.
    property bool positionReported: false
    readonly property bool clockEstimated: playing && !positionReported && positionSec > 8

    function _extrapolated(now) {
        return _anchorPos + (playing ? (now - _anchorTime) / 1000 * playbackRate : 0)
    }
    function _tick() {
        positionSec = Math.max(0, _extrapolated(Date.now()))
        enforceLoop()
    }
    // A position the player has just reported, in seconds.
    function observePosition(reported) {
        if (!(reported >= 0)) return
        var now = Date.now()
        if (reported > 0) positionReported = true
        var expected = _extrapolated(now)
        if (!_anchored || Math.abs(reported - expected) > _snapThreshold) _anchorPos = reported
        else _anchorPos = expected + (reported - expected) / 2
        _anchorTime = now
        _anchored = true
        _tick()
    }
    // Take the player's last answer as it stands: for the moment a player is
    // picked, and for harnesses that set `position` by hand. The poll never
    // reads it, because what it reads would be stale.
    function syncPosition() {
        if (!player) { positionSec = 0; _anchored = false; return }
        observePosition(player.position / 1000000)
    }
    property Connections _playerWatch: Connections {
        // A plain object standing in for the player (tests, the screenshot harness) has no signals.
        target: model.player && model.player.positionChanged !== undefined ? model.player : null
        ignoreUnknownSignals: true
        function onPositionChanged() { model.observePosition(model.player.position / 1000000) }
    }
    // Ask the player where it is: every second while the popup is open, less
    // often while it is not (the extrapolation holds, and a seek announces itself).
    property Timer _poll: Timer {
        interval: model.viewVisible ? 1000 : 3000; repeat: true; triggeredOnStart: true
        running: model.playing && !!model.player
        onTriggered: if (model.player && model.player.updatePosition) model.player.updatePosition()
    }
    // Re-extrapolate between answers so highlights glide: ten times a second on
    // screen, less while hidden (the panel's chord, the tooltip), and much faster
    // while a section loops, so the jump back lands close to the section's end.
    property Timer _glide: Timer {
        interval: model.loopSpan ? 50 : (model.viewVisible ? 100 : 200); repeat: true; running: model.playing
        onTriggered: model._tick()
    }
    onPlayerChanged: {
        _anchored = false
        positionReported = false
        syncPosition()
        if (player && player.updatePosition) player.updatePosition()
    }
    // Pausing stops the extrapolation; resuming must restart it from where the
    // song was, not from the anchor taken before the pause (which would make the
    // position leap ahead by the length of the pause). The player's own answer
    // follows: Plasma asks it on every state and rate change.
    onPlayingChanged: {
        _anchorPos = positionSec
        _anchorTime = Date.now()
    }
    onPlaybackRateChanged: {
        _anchorPos = positionSec
        _anchorTime = Date.now()
    }

    function togglePlay() { if (player) player.PlayPause() }
    function nextTrack() { if (player) player.Next() }
    function previousTrack() { if (player) player.Previous() }
    // Send the player to `seconds` of the track.
    function seekTo(seconds) {
        if (!player || !(seconds >= 0)) return
        var target = lengthSec > 0 ? Math.min(seconds, lengthSec) : seconds
        player.position = Math.round(target * 1000000)
        // Move the local anchor too, so the highlight lands on the clicked line
        // at once instead of waiting for the player's answer.
        _anchorPos = target
        _anchorTime = Date.now()
        _anchored = true
        positionSec = target
    }
    // Send the player to a moment on the timings' clock (a lyric line, a chart
    // row, a section): the per-song nudge separates the two.
    function seekToLyricTime(seconds) { seekTo(seconds - lyricsOffset) }
    // Practice speed. Players that cannot change rate ignore this.
    function setRate(rate) {
        if (!canChangeRate) return
        player.rate = Math.max(player.minimumRate, Math.min(player.maximumRate, rate))
        // The extrapolation must switch speed from "now", not from the old anchor.
        _anchorPos = positionSec
        _anchorTime = Date.now()
    }

    // ------------------------------------------------------------ practice loop
    // A section played over and over: {name, start, end} on the timings' clock.
    property var loopSpan: null
    function enforceLoop() {
        if (!loopSpan || !playing) return
        var at = playbackPosition
        if (at >= loopSpan.end - 0.05 && at < loopSpan.end + 3) seekToLyricTime(loopSpan.start)
    }
    // A section only a moment long would be seeked back over and over: not looped.
    function loopSection(span) {
        if (span && span.end - span.start < 2) return
        loopSpan = span ? { name: span.name, start: span.start, end: span.end } : null
    }
    function toggleLoopHere() {
        if (loopSpan) { loopSpan = null; return }
        var here = activeSpan
        if (here) loopSection(here)
    }
    function jumpToSection(span) { if (span) seekToLyricTime(span.start) }

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
    // A tab or lyrics entry picked by hand would not load, and the automatic pick is shown instead.
    readonly property bool pinFailed: !!((chart && chart.pin_failed) || (lyrics && lyrics.pin_failed))
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
    // Two spellings of one chord (C# and Db) collapse to one sounding name.
    readonly property var soundingNames: {
        var seen = {}, out = []
        chartNames.forEach(function (n) {
            var sounding = Theory.transposeChord(n, transpose + chartCapo)
            if (!seen[sounding]) { seen[sounding] = true; out.push(sounding) }
        })
        return out
    }
    // How often each sounding chord occurs, counting every spelling that maps to it.
    readonly property var soundingWeights: {
        var weights = {}
        chartNames.forEach(function (n) {
            var sounding = Theory.transposeChord(n, transpose + chartCapo)
            weights[sounding] = (weights[sounding] || 0) + chordCounts[n]
        })
        return weights
    }
    // key: {name, tonic, mode, source}. The tab's own stated key wins when it
    // gives one; otherwise it is worked out from the chords.
    readonly property var keyInfo: {
        if (!hasChordNames) return null
        var detected = Theory.detectKey(soundingNames, soundingWeights)
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
    // The easiest capo for these chords, and what it would turn them into.
    // Null when a capo would not make the shapes any easier than they are now.
    readonly property var capoAdvice: {
        if (!hasChordNames || simplifyChords) return null
        var best = Theory.suggestCapo(soundingNames, soundingWeights, 7)
        if (!best || best.capo === capo) return null
        var current = Theory.capoCost(soundingNames, soundingWeights, capo)
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
    // A chord tapped in the chart, shown on the Stage for a few seconds in place
    // of the one being played.
    property string previewChord: ""
    function previewChordNamed(name) {
        previewChord = name || ""
        if (previewChord) _previewClear.restart()
    }
    property Timer _previewClear: Timer { interval: 5000; onTriggered: model.previewChord = "" }
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
    property bool _shapeFetching: false
    // The length the last song request was made with: 0 means the player had not
    // told us yet, and a lookup by title alone is less certain than one by length.
    property int _requestedLength: -1
    // The first answer for this track has arrived and its remembered settings are in place.
    property bool _prefsLoaded: false

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

    // `refresh` ("Ask again") also bypasses the service's memory of a miss.
    function fetchSong(refresh) {
        if (!ready) return
        // Only the newest request may land: a slow answer for the previous
        // track must not overwrite the one for this track.
        if (_songRequest) _songRequest.abort()
        var id = ++_requestId
        var forArtist = artist, forTrack = track
        _requestedLength = Math.round(lengthSec)
        loading = true
        statusMessage = ""
        // The pins stay out of the first request for a track, so the service
        // applies what it remembers for the song; from the answer on they are
        // always sent, empty included, so a pick (or an un-pick) made here wins
        // over a remembered one that has not reached the disk yet.
        var pins = _prefsLoaded || pinnedLyricsId || pinnedChordUrl
        var query = "/api/song?artist=" + encodeURIComponent(artist)
                  + "&title=" + encodeURIComponent(track)
                  + "&album=" + encodeURIComponent(album)
                  + "&duration=" + Math.round(lengthSec)
                  + (romaniseChoice >= 0 ? "&romanise=" + romaniseChoice : "")
                  + (pins ? "&lyrics_id=" + encodeURIComponent(pinnedLyricsId)
                            + "&chord_url=" + encodeURIComponent(pinnedChordUrl) : "")
                  + (refresh === true ? "&refresh=1" : "")
                  // A paused player is not recorded for identification.
                  + "&playing=" + (playing ? 1 : 0)
        _songRequest = apiGet(query, function (data, error) {
            if (id !== _requestId) return
            loading = false
            if (error) {
                // An aborted request reports "offline"; a newer one is on its way.
                statusMessage = error
                return
            }
            acceptSong(data, forArtist, forTrack)
        })
    }
    // An answer for the track. The first puts the song's remembered settings
    // back; a later one (another version, "Ask again", the script flipped)
    // keeps whatever the user has set here since, and only follows the new
    // chart's own capo when the old chart was being played as written.
    function acceptSong(data, forArtist, forTrack) {
        var first = !_prefsLoaded
        var followingCapo = !first && capo === chartCapo
        song = data
        stale = false
        shapes = data.shapes || ({})
        shapeVariants = data.variations || ({})
        voicingPick = ({})
        if (first) {
            _prefsFor = { artist: forArtist, title: forTrack }
            applyPrefs(data.prefs || ({}), data.chords ? data.chords.capo : 0)
            _prefsLoaded = true
        } else if (followingCapo && capo !== chartCapo) {
            _applying = true
            capo = chartCapo
            _applying = false
        }
        if (!lyricsAvailable && !chordsAvailable) statusMessage = "nothing"
    }

    // Put the song back the way it was left: nudge, key and any hand-picked
    // tab or lyrics entry.
    function applyPrefs(prefs, tabCapo) {
        _applying = true
        lyricsOffset = prefs.offset !== undefined && prefs.offset !== null ? prefs.offset : 0
        transpose = prefs.transpose !== undefined && prefs.transpose !== null ? prefs.transpose : 0
        // With no capo saved, start from the tab's own so it reads as written.
        capo = prefs.capo !== undefined && prefs.capo !== null ? prefs.capo : (tabCapo || 0)
        pinnedLyricsId = prefs.lyrics_id || ""
        pinnedChordUrl = prefs.chord_url || ""
        _applying = false
    }

    function refreshShapes(names) {
        if (!names || !names.length) { shapes = ({}); shapeVariants = ({}); return }
        // The song's own answer already carried these (the common case: no
        // transposition): nothing to ask for.
        if (names.every(function (name) { return shapeVariants && shapeVariants[name] })) return
        var id = _requestId
        _shapeFetching = true
        apiGet("/api/shapes?names=" + encodeURIComponent(names.join(",")), function (data, error) {
            _shapeFetching = false
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
        // A chart belongs to a song: with nothing playing it would be saved under
        // no name at all.
        if (!ready) { statusMessage = "notrack"; return }
        // A bare address is a request to use that tab, and only Ultimate Guitar's
        // can be used: anything else is not a chart, so it is not saved as one.
        if (/^https?:\/\/\S+$/.test(value)) {
            if (!pinChartUrl(value)) statusMessage = "badaddress"
            return
        }
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
    // A new title, or a new artist under a repeated title, is a new song.
    function _songChanged() {
        flushPrefs()
        // The player's answer for the new track is on its way (Plasma asks for it
        // on every track change); until it lands the track is taken to start from
        // the top, which is also where a player that never answers is followed from.
        _anchorPos = 0
        _anchorTime = Date.now()
        _anchored = false
        positionSec = 0
        // What is on screen belongs to the previous song until the answer lands.
        stale = true
        retryCount = 0
        _prefsLoaded = false
        pinnedLyricsId = ""
        pinnedChordUrl = ""
        // Another song's alternatives are not this song's alternatives.
        versions = null
        versionsOpen = false
        loopSpan = null
        previewChord = ""
        if (ready) _refetch.restart()
    }
    onTrackChanged: _songChanged()
    onArtistChanged: _songChanged()
    // Some players announce the track's length a moment after its name. A lookup
    // made without it is redone once it arrives.
    onLengthSecChanged: if (ready && _requestedLength === 0 && lengthSec > 0) _refetch.restart()

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
    // position, highlight delay included, so the line lights as the button is
    // pressed; one press fixes a whole song's drift. `stamps` are the times to
    // choose from (the chart's rows on the chart tab); the lyric lines by default.
    function syncOffset(stamps) {
        var candidates = stamps
        if (!candidates) {
            candidates = []
            var lines = lyrics && lyrics.lines ? lyrics.lines : []
            for (var i = 0; i < lines.length; i++) candidates.push(lines[i].t)
        }
        // Where the song is on the timings' clock, allowing for the delay.
        var heard = positionSec + lyricsOffset - syncLag
        var best = null
        for (var k = 0; k < candidates.length; k++) {
            var stamp = candidates[k]
            if (stamp === null || stamp === undefined) continue
            var delta = Math.abs(stamp - heard)
            if (best === null || delta < best.delta) best = { delta: delta, stamp: stamp }
        }
        if (!best) return
        lyricsOffset = Math.round((best.stamp + syncLag - positionSec) * 20) / 20
        _prefsSave.restart()
    }
    function resetOffset() {
        if (lyricsOffset === 0) return
        lyricsOffset = 0
        _prefsSave.restart()
    }
    readonly property string offsetLabel: {
        var sign = lyricsOffset > 0 ? "+" : (lyricsOffset < 0 ? "−" : "")
        return sign + Math.abs(lyricsOffset).toFixed(1) + "s"
    }

    // The service remembers all of this per song; we tell it what changed, a
    // moment after the last click. The save goes to the song the settings were
    // loaded for, not whatever is playing when the timer fires, so skipping a
    // track right after a tweak cannot write one song's settings onto the next.
    property var _prefsFor: null
    // True while a song's own saved settings are being put back: those changes
    // are not the user's, and must not be saved as if they were.
    property bool _applying: false
    function prefsBody() {
        if (!_prefsFor) return null
        return {
            artist: _prefsFor.artist, title: _prefsFor.title, offset: lyricsOffset, transpose: transpose,
            capo: capo, lyrics_id: pinnedLyricsId, chord_url: pinnedChordUrl
        }
    }
    function savePrefs() {
        var body = prefsBody()
        if (body) apiPost("/api/prefs", body)
    }
    // Write out a pending change now, while the settings still describe the song
    // they were made for.
    function flushPrefs() {
        if (!_prefsSave.running) return
        _prefsSave.stop()
        savePrefs()
    }
    property Timer _prefsSave: Timer { interval: 700; onTriggered: model.savePrefs() }
    onTransposeChanged: if (!_applying) _prefsSave.restart()
    onCapoChanged: if (!_applying) _prefsSave.restart()

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

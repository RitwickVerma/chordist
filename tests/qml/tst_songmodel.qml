// SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
//
// SPDX-License-Identifier: MIT

import QtQuick
import QtTest
import "../../applet/contents/ui"

// Logic of the song model on its own: no Plasma, no service. The model is fed
// charts directly and a plain object stands in for the MPRIS player.
TestCase {
    id: test
    name: "SongModel"
    when: windowShown

    QtObject {
        id: config
        property string serviceUrl: "http://127.0.0.1:9"   // nothing listens here
        property bool lyricSync: true
        property bool simplifyChords: false
        property bool showStage: true
        property int fontSizeOffset: 0
        property int scrollSpeed: 5
        property bool autoScroll: true
        property int highlightDelayMs: 250
        property bool hideWhenEmpty: true
    }

    SongModel {
        id: model
        config: config
        track: "Song"
        artist: "Artist"
        lengthSec: 100
    }

    function line(lyric, chords) { return { lyric: lyric, chords: chords, mono: false, instrumental: false } }
    function chart(extra) {
        var base = {
            source: "local", kind: "chords", capo: 0, key: "",
            sections: [
                { name: "Verse", lines: [line("hello there my friend", [{ pos: 0, name: "Bb" }, { pos: 12, name: "F" }]),
                                          line("it has been so long", [{ pos: 0, name: "Gm" }])] },
                { name: "Chorus", lines: [line("sing along now", [{ pos: 0, name: "Eb" }])] }
            ],
            row_times: [10, 20, 40]
        }
        for (var key in extra) base[key] = extra[key]
        return base
    }
    function load(c) {
        model.song = { lyrics: null, chords: c, prefs: {} }
        model.stale = false
        model.transpose = 0
        model.capo = c.capo || 0
        model.loopSpan = null
        model.positionSec = 0
        model.lyricsOffset = 0
    }
    function init() {
        model.track = "Song"             // first: a track change marks the chart stale
        load(chart({}))
        model._prefsFor = { artist: "Artist", title: "Song" }
        model._prefsSave.stop()
    }

    // ----------------------------------------------------------------- rows
    function test_rows_and_times_line_up() {
        compare(model.chartRows.length, 5)      // 2 section headers + 3 lines
        compare(model.chartRows[0].kind, "section")
        compare(model.rowTimes[1], 10)
        compare(model.rowTimes[2], 20)
        compare(model.rowTimes[0], null)
    }

    function test_active_row_follows_position_and_respects_lag() {
        model.positionSec = 5
        compare(model.activeRow, -1)
        model.positionSec = 10.1                // inside the sync lag: not yet
        compare(model.activeRow, -1)
        model.positionSec = 10.5
        compare(model.activeRow, 1)
        model.positionSec = 45
        compare(model.activeRow, 4)
    }

    function test_a_stale_chart_is_not_highlighted() {
        model.positionSec = 45
        model.stale = true
        compare(model.activeRow, -1)
        verify(model.chordState === null)
        compare(model.nowChord, "")
    }

    function test_lyric_offset_shifts_the_highlight() {
        model.positionSec = 8
        model.lyricsOffset = 3
        compare(model.activeRow, 1)
    }

    function test_a_tab_has_no_active_row() {
        load(chart({ kind: "tab" }))
        model.positionSec = 45
        compare(model.activeRow, -1)
    }

    // --------------------------------------------------------------- chords
    function test_now_and_next_chord() {
        model.positionSec = 10.5
        compare(model.nowChord, "Bb")
        compare(model.nextChord, "F")
        verify(model.nextIn > 0)
        model.positionSec = 30
        compare(model.nowChord, "Gm")
        compare(model.nextChord, "Eb")
    }

    function test_chord_names_follow_transpose_and_capo() {
        model.positionSec = 10.5
        model.transpose = 2
        compare(model.nowChord, "C")
        model.transpose = 0
        model.capo = 3                           // shapes drop three frets
        compare(model.effectiveTranspose, -3)
        compare(model.nowChord, "G")
    }

    function test_effective_transpose_counts_the_charts_own_capo() {
        load(chart({ capo: 2 }))
        compare(model.capo, 2)
        compare(model.effectiveTranspose, 0)     // played as written
        model.capo = 0
        compare(model.effectiveTranspose, 2)     // no capo: shapes rise by two frets
    }

    // ------------------------------------------------------------ analysis
    function test_capo_advice_turns_barres_into_open_shapes() {
        var advice = model.capoAdvice
        verify(advice !== null)
        compare(advice.capo, 3)
        compare(advice.shapes.slice(0, 2).join(" "), "G D")
        model.capo = 3
        verify(model.capoAdvice === null, "already on the best capo: nothing to suggest")
    }

    function test_no_capo_advice_for_easy_chords_or_easy_mode() {
        load(chart({ sections: [{ name: "V", lines: [line("a b", [{ pos: 0, name: "G" }, { pos: 2, name: "C" }, { pos: 4, name: "D" }])] }], row_times: [1] }))
        verify(model.capoAdvice === null)
        load(chart({}))
        config.simplifyChords = true
        verify(model.capoAdvice === null)
        config.simplifyChords = false
    }

    function test_stated_key_wins_and_follows_transpose() {
        load(chart({ meta: { tonality: "Bb" } }))
        compare(model.keyInfo.name, "Bb")
        compare(model.keyInfo.source, "tab")
        model.transpose = 2
        compare(model.keyInfo.name, "C")
        load(chart({ meta: { tonality: "F#m" } }))
        compare(model.keyInfo.mode, "minor")
    }

    function test_key_is_worked_out_when_the_tab_does_not_say() {
        compare(model.keyInfo.source, "chords")
        compare(model.keyInfo.name, "Bb")
        compare(model.romanFor("Gm"), "vi")
        compare(model.romanFor("Eb"), "IV")
    }

    function test_no_chord_analysis_for_a_tab() {
        load(chart({ kind: "tab" }))
        verify(model.keyInfo === null)
        verify(model.capoAdvice === null)
    }

    // ------------------------------------------------------------- voicings
    function test_the_tabs_own_fingerings_come_first_without_duplicates() {
        var mine = { name: "Bb", frets: [-1, 1, 3, 3, 3, 1], fingers: [0, 1, 2, 3, 4, 1], base: 1, barre: 1 }
        var theirs = { name: "Bb", frets: [6, 8, 8, 7, 6, 6], fingers: [1, 3, 4, 2, 1, 1], base: 6, barre: 6, source: "ultimate-guitar" }
        load(chart({ applicature: { Bb: [theirs, mine] } }))
        model.shapeVariants = { Bb: [mine, { name: "Bb", frets: [6, 8, 8, 7, 6, 6] }] }
        var list = model.variantsFor("Bb")
        compare(list.length, 2)
        compare(list[0].source, "ultimate-guitar")
        compare(model.voicingFor("Bb").frets.join(), "6,8,8,7,6,6")
        model.cycleVoicing("Bb", 1)
        compare(model.voicingFor("Bb").frets.join(), "-1,1,3,3,3,1")
        model.cycleVoicing("Bb", 1)
        compare(model.voicingFor("Bb").frets.join(), "6,8,8,7,6,6")      // wraps
        compare(model.variantsFor("Nope").length, 0)
        verify(model.voicingFor("Nope") === null)
    }

    function test_a_previewed_chord_is_remembered_until_cleared() {
        compare(model.previewChord, "")
        model.previewChordNamed("Am")
        compare(model.previewChord, "Am")
        model.previewChordNamed("")
        compare(model.previewChord, "")
    }

    // ----------------------------------------------------------------- loop
    property var fake: null
    function makePlayer() {
        var self = { position: 0, rate: 1, minimumRate: 0.5, maximumRate: 2, toggles: 0,
                     PlayPause: function () { self.toggles++ }, Next: function () {}, Previous: function () {},
                     updatePosition: function () {} }
        return self
    }

    function test_sections_have_spans() {
        compare(model.spans.length, 2)
        compare(model.spans[0].name, "Verse")
        compare(model.spans[0].start, 10)
        compare(model.spans[0].end, 40)
        compare(model.spans[1].end, 100)
    }

    function test_loop_jumps_back_when_the_section_ends() {
        var player = makePlayer()
        model.player = player
        model.playing = true
        model.loopSection(model.spans[0])
        player.position = 39.97 * 1000000
        model.syncPosition()
        // within 50 ms of the end: back to the start of the section
        compare(player.position, 10 * 1000000)
        model.playing = false
        model.player = null
    }

    function test_loop_is_off_when_paused_and_cleared_on_a_new_track() {
        var player = makePlayer()
        model.player = player
        model.loopSection(model.spans[0])
        player.position = 41 * 1000000
        model.syncPosition()
        compare(player.position, 41 * 1000000)       // paused: left alone
        model.track = "Another"
        verify(model.loopSpan === null)
        model.track = "Song"
        model.player = null
    }

    function test_toggle_loop_here_needs_a_section() {
        model.positionSec = 5
        model.toggleLoopHere()
        verify(model.loopSpan === null)
        model.positionSec = 15
        model.toggleLoopHere()
        compare(model.loopSpan.name, "Verse")
        model.toggleLoopHere()
        verify(model.loopSpan === null)
    }

    // -------------------------------------------------------------- position
    function test_position_extrapolates_between_polls() {
        var player = makePlayer()
        player.position = 20 * 1000000
        model.player = player
        model.playing = true
        model.syncPosition()
        compare(Math.round(model.positionSec), 20)
        wait(450)
        verify(model.positionSec > 20.3, "glide timer advanced it: " + model.positionSec)
        model.playing = false
        model.player = null
    }

    function test_resuming_does_not_leap_by_the_length_of_the_pause() {
        var player = makePlayer()
        player.position = 20 * 1000000
        model.player = player
        model.playing = true
        model.syncPosition()
        model.playing = false
        var paused = model.positionSec
        wait(700)                                  // a pause
        model.playing = true
        wait(120)
        verify(model.positionSec - paused < 0.6, "jumped to " + model.positionSec + " from " + paused)
        model.playing = false
        model.player = null
    }

    function test_seek_moves_player_and_position_at_once() {
        var player = makePlayer()
        model.player = player
        model.seekTo(33)
        compare(player.position, 33 * 1000000)
        compare(model.positionSec, 33)
        model.seekTo(-5)
        compare(player.position, 33 * 1000000)     // negative ignored
        model.player = null
    }

    function test_rate_is_clamped_and_only_offered_when_supported() {
        verify(!model.canChangeRate)
        var player = makePlayer()
        model.player = player
        verify(model.canChangeRate)
        model.setRate(0.1)
        compare(player.rate, 0.5)
        model.setRate(9)
        compare(player.rate, 2)
        model.player = null
    }

    // ------------------------------------------------------------ pinning
    function test_only_ultimate_guitar_addresses_can_be_pinned() {
        verify(!model.pinChartUrl("http://tabs.ultimate-guitar.com/tab/a"))
        verify(!model.pinChartUrl("https://evil.example/ultimate-guitar.com"))
        verify(!model.pinChartUrl("https://ultimate-guitar.com.evil.example/x"))
        verify(!model.pinChartUrl("file:///etc/passwd"))
        compare(model.pinnedChordUrl, "")
        verify(model.pinChartUrl("  https://tabs.ultimate-guitar.com/tab/radiohead/x-tabs-1  "))
        compare(model.pinnedChordUrl, "https://tabs.ultimate-guitar.com/tab/radiohead/x-tabs-1")
    }

    // --------------------------------------------------------------- config
    function test_font_size_and_speed_are_clamped() {
        config.fontSizeOffset = 10
        model.adjustFontSize(5)
        compare(config.fontSizeOffset, 10)
        config.fontSizeOffset = -4
        model.adjustFontSize(-1)
        compare(config.fontSizeOffset, -4)
        config.fontSizeOffset = 0
        model.setScrollSpeed(99)
        compare(config.scrollSpeed, 10)
        model.setScrollSpeed(0)
        compare(config.scrollSpeed, 1)
    }

    function test_a_new_track_forgets_the_previous_songs_alternatives() {
        model.versions = { lyrics: [], charts: [{ url: "x" }] }
        model.versionsOpen = true
        model.track = "Different"
        verify(model.versions === null)
        compare(model.versionsOpen, false)
        compare(model.stale, true)
        model.track = "Song"
    }

    // ------------------------------------------------------ review-pass fixes
    function test_toggle_agrees_with_the_default_it_reads_with() {
        // lyricSync reads as true when unset, so one toggle must turn it off
        verify(model.lyricSync)
        model.toggle("lyricSync")
        verify(!model.lyricSync)
        model.toggle("lyricSync")
        verify(model.lyricSync)
    }

    function test_two_spellings_of_one_chord_add_their_counts() {
        load(chart({ sections: [{ name: "V", lines: [
            line("a b c", [{ pos: 0, name: "C#" }, { pos: 2, name: "Db" }, { pos: 4, name: "Db" }])] }], row_times: [1] }))
        var weights = model.soundingWeights
        var total = 0
        for (var name in weights) total += weights[name]
        compare(total, 3)
    }

    function test_a_section_too_short_to_loop_is_refused() {
        model.loopSection({ name: "blip", start: 10, end: 10.4 })
        verify(model.loopSpan === null)
        model.loopSection({ name: "ok", start: 10, end: 14 })
        compare(model.loopSpan.name, "ok")
    }

    function test_applying_a_songs_prefs_does_not_save_them_back() {
        model.applyPrefs({ capo: 3, transpose: 2, offset: 0.5 }, 0)
        compare(model.capo, 3)
        verify(!model._prefsSave.running, "loading must not schedule a save")
        model.applyPrefs({}, 2)
        verify(!model._prefsSave.running)
    }

    function test_a_users_change_does_schedule_a_save() {
        model.capo = 5
        verify(model._prefsSave.running)
    }

    function test_prefs_belong_to_the_song_they_were_loaded_for() {
        model.transpose = 2
        model.track = "Next song"            // the track moves on before the save fires
        var body = model.prefsBody()
        compare(body.title, "Song")          // ...but the save still goes to the old one
        compare(body.artist, "Artist")
    }

    function test_changing_track_flushes_a_pending_save_before_clearing_pins() {
        model.pinnedChordUrl = "https://tabs.ultimate-guitar.com/tab/a/b-tabs-1"
        model.capo = 4
        verify(model._prefsSave.running)
        model.track = "Another one"
        verify(!model._prefsSave.running, "the pending save is flushed, not left to fire later")
        compare(model.pinnedChordUrl, "")
    }

    function test_nothing_is_saved_before_a_song_has_loaded() {
        model._prefsFor = null
        verify(model.prefsBody() === null)
    }

    function test_a_non_ultimate_guitar_address_is_not_saved_as_a_chart() {
        model.statusMessage = ""
        model.submitPaste("https://example.com/some-page")
        compare(model.statusMessage, "badaddress")
    }

    function test_shapes_already_in_hand_are_not_fetched_again() {
        model.shapeVariants = { Bb: [{ frets: [1, 1, 1, 1, 1, 1] }], F: [{ frets: [1] }] }
        var before = model._requestId
        model.refreshShapes(["Bb", "F"])
        compare(model._requestId, before)
        verify(!model._shapeFetching, "no request was made")
    }

    function test_nothing_can_be_saved_when_nothing_is_playing() {
        model.track = ""
        model.artist = ""
        verify(!model.ready)
        model.statusMessage = ""
        model.submitPaste("Am F\nhello there")
        compare(model.statusMessage, "notrack")
        model.artist = "Artist"
        model.track = "Song"
    }

    // ------------------------------------------------------------- the clock
    function test_a_report_close_to_the_clock_only_nudges_it() {
        var player = makePlayer()
        model.player = player
        model.playing = true
        model.observePosition(20)
        verify(Math.abs(model.positionSec - 20) < 0.05, "took the first report: " + model.positionSec)
        // A report a little off (jitter, a player that reports in coarse steps) moves the clock half way.
        model.observePosition(20.2)
        verify(Math.abs(model.positionSec - 20.1) < 0.05, "nudged to " + model.positionSec)
        // One far off (a seek in the player) is taken as it is.
        model.observePosition(60)
        verify(Math.abs(model.positionSec - 60) < 0.05, "snapped to " + model.positionSec)
        model.playing = false
        model.player = null
    }

    function test_the_poll_asks_the_player_and_never_adopts_its_stale_answer() {
        // A real player answers updatePosition() later, through positionChanged; what `position` holds meanwhile
        // is the previous answer. The fake's never changes, so taking it would show here as a jump.
        var player = makePlayer()
        var asked = 0
        player.updatePosition = function () { asked++ }
        model.player = player
        model.playing = true
        player.position = 55 * 1000000
        wait(150)
        verify(asked >= 2, "the player was asked " + asked + " times")
        verify(model.positionSec < 1, "adopted the stale value: " + model.positionSec)
        model.playing = false
        model.player = null
    }

    function test_seeking_to_a_line_allows_for_the_songs_nudge() {
        var player = makePlayer()
        model.player = player
        model.lyricsOffset = 2                  // the timings run two seconds ahead of this recording
        model.seekToLyricTime(30)               // a line stamped 30 s is sung 28 s into the recording
        compare(player.position, 28 * 1000000)
        compare(model.playbackPosition, 30)     // and the highlight lands on it at once
        model.lyricsOffset = 0
        model.player = null
    }

    function test_the_loop_is_measured_on_the_timings_clock() {
        var player = makePlayer()
        model.player = player
        model.playing = true
        model.lyricsOffset = 1
        model.loopSection(model.spans[0])       // Verse: 10..40 on the timings' clock
        model.observePosition(38.97)            // 39.97 on that clock: the verse is ending
        compare(player.position, 9 * 1000000)   // back to 10 on it, which is 9 s of the recording
        model.playing = false
        model.lyricsOffset = 0
        model.player = null
    }

    function test_line_up_now_lights_the_nearest_line_at_once() {
        model.song = { lyrics: { synced: true, lines: [{ t: 10, text: "a" }, { t: 20, text: "b" }, { t: 40, text: "c" }] },
                       chords: chart({}), prefs: {} }
        model.stale = false
        model.lyricsOffset = 0
        model.positionSec = 19.4                // the line stamped 20 is heard now
        model.syncOffset()
        compare(model.lyricsOffset, Math.round((20 + model.syncLag - 19.4) * 20) / 20)
        compare(model.lyricActive, 1)           // lit this instant, delay included
        // On the chart tab the rows' own times are the candidates.
        model.positionSec = 39
        model.syncOffset(model.rowTimes)
        compare(model.activeRow, 4)
        model.resetOffset()
        compare(model.lyricsOffset, 0)
        model._prefsSave.stop()
    }

    function test_a_new_track_starts_the_clock_from_the_top() {
        var player = makePlayer()
        player.position = 200 * 1000000
        model.player = player
        model.playing = true
        model.syncPosition()
        compare(Math.round(model.positionSec), 200)
        model.track = "Next"                    // the player's 200 s belong to the old track
        verify(model.positionSec < 1, "still at " + model.positionSec)
        model.observePosition(3)                // its answer for the new one
        verify(Math.abs(model.positionSec - 3) < 0.05, "at " + model.positionSec)
        model.playing = false
        model.player = null
        model.track = "Song"
    }

    function test_a_player_that_never_reports_is_followed_by_an_estimate() {
        var player = makePlayer()               // position stays 0, like a browser without Plasma Browser Integration
        model.player = player
        model.playing = true
        verify(!model.clockEstimated)
        model._anchorTime = Date.now() - 10000  // ten seconds into the track
        model._tick()
        verify(model.clockEstimated, "no report in ten seconds: an estimate")
        model.observePosition(10.5)
        verify(!model.clockEstimated)
        model.playing = false
        model.player = null
    }

    function test_the_highlight_delay_is_a_setting() {
        compare(model.syncLag, 0.25)
        config.highlightDelayMs = 600
        compare(model.syncLag, 0.6)
        config.highlightDelayMs = 99999
        compare(model.syncLag, 2)
        config.highlightDelayMs = 250
    }

    function test_a_player_that_cannot_seek_says_so() {
        verify(!model.canSeek)
        var player = makePlayer()
        model.player = player
        verify(model.canSeek)                   // a player that does not say is assumed able
        player.canSeek = false
        model.player = null
        model.player = player
        verify(!model.canSeek)
        model.player = null
    }

    // ------------------------------------------------------------- answers
    function test_a_later_answer_keeps_the_users_changes_and_follows_the_charts_capo() {
        model._prefsLoaded = false
        model.acceptSong({ lyrics: null, chords: chart({ capo: 2 }), prefs: { transpose: 1 } }, "Artist", "Song")
        compare(model.transpose, 1)
        compare(model.capo, 2)                  // no capo saved: the chart's own, as written
        model.transpose = 3                     // the user's change...
        model.acceptSong({ lyrics: null, chords: chart({ capo: 4 }), prefs: { transpose: 1 } }, "Artist", "Song")
        compare(model.transpose, 3)             // ...survives the next answer's stale prefs
        compare(model.capo, 4)                  // and a chart played as written stays as written
        model.capo = 1                          // but a capo the user chose...
        model.acceptSong({ lyrics: null, chords: chart({ capo: 5 }), prefs: {} }, "Artist", "Song")
        compare(model.capo, 1)                  // ...is left alone
        model._prefsSave.stop()
    }

    function test_an_answer_with_nothing_in_it_says_nothing() {
        model.statusMessage = ""
        model.acceptSong({ lyrics: { source: "none" }, chords: { source: "none", sections: [] }, prefs: {} }, "Artist", "Song")
        compare(model.statusMessage, "nothing")
        model.statusMessage = ""
        model.acceptSong({ lyrics: null, chords: chart({}), prefs: {} }, "Artist", "Song")
        compare(model.statusMessage, "")
    }
}

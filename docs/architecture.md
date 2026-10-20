# Architecture

Two programs and a data file:

```
  player ──MPRIS──▶ Plasma widget (applet/) ──HTTP, loopback──▶ lyricistd (lyricist/) ──▶ LRCLIB
  (Spotify,         main.qml  SongModel.qml  views                server.py               Ultimate Guitar
   browser, …)                                                    providers, cache        SongRec (audio)
                                                                  data/guitar-chords.json
```

The widget does everything that must be instant (following playback, transposing, the capo calculator, drawing).
The service does everything slow or messy (scraping, parsing, caching, identifying a track, aligning a chart to
lyrics) behind a synchronous-looking JSON API, so QML never blocks the compositor.

## The service

`server.py` is a `ThreadingHTTPServer` with route tables ([api.md](api.md)). A request for a song runs
`Service.song()`:

1. **identity** (`identity.py`). Streaming metadata is written for people watching a video: the artist is the
   channel, the title carries the film, the singers and a "(Official Video)". The raw pair is resolved once to a
   canonical artist/title, by trying candidate pairs against LRCLIB and accepting one only if the recording length
   agrees and its name shares a word with the title (`titles.py` takes titles apart). If nothing verifies, the
   audio is identified (`fingerprint.py`). Lyrics and chords both run on the answer, so they cannot disagree about
   which song is playing.
2. **lyrics** (`lyrics.py`): LRCLIB's exact match, else a scored search; timed LRC including word timings (`lrc.py`).
3. **chords** (`chords.py`): your own ChordPro file, then the cache, then Ultimate Guitar. UG's search results are
   filtered so a tab is trusted only when every meaningful word of its name is in the title or artist asked for;
   popularity breaks ties. Chords are preferred; a song with none falls back to a Tab. The page's `js-store` blob
   yields the chart (`chart.py`) and its metadata (tuning, difficulty, key, capo, rating, strumming tempo, UG's own
   fingerings). Misses are cached briefly, hits for a year.
4. **alignment** (`align.py`): Needleman-Wunsch over (chart row × timed lyric line) with word overlap as the score,
   so the best *monotonic* pairing wins and a stray one-word row cannot hijack the path. Output: one time per
   chart row (`row_times`).
5. **script** (`translit.py`): Devanagari lyrics are romanised when the chart is Latin, so both halves read alike.
6. **shapes** (`shapes.py`): fingerings from chords-db, with derived barre shapes for chords it lacks.

Everything is a plain dict and JSON: no database. `cache.py` is one file per key, written atomically; `songprefs.py`
remembers transpose, capo, timing offset and pinned picks per song.

### Charts

`chart.py` reads three dialects (Ultimate Guitar markup, ChordPro, plain text) into one shape:

```
{title, artist, key, capo, source, kind: "chords"|"tab"|"mixed", chord_names, row_times?, meta?, applicature?,
 sections: [{name, lines: [{lyric, chords: [{pos, name}], mono, instrumental, staff?: {labels, rows}}]}]}
```

`pos` is a character offset into `lyric`, so a monospace renderer puts each chord above its syllable. A tablature
staff is a group of string rows (`staff`); `lyric` still holds the staff as text for renderers that do not know
about staves.

## The widget

| File | Role |
| --- | --- |
| `main.qml` | Plasma glue: picks the MPRIS player that is making noise, hosts the model, the floating window and the panel item |
| `SongModel.qml` | all state and logic; no Plasma types, so it is tested alone and driven by the screenshot harness |
| `js/theory.js` | transposition, chord tones, key detection, roman numerals, the capo calculator |
| `js/schedule.js` | which row/line is being sung, which chord is sounding and which is next, section spans |
| `js/tab.js` | re-flowing a tab staff at its bar lines |
| `Full.qml` | the popup and the window: header, chips, tabs, Stage, section bar, toolbars, views |
| `Stage`, `SectionBar`, `InfoStrip`, `Toolbar`, `ChordsView`, `LyricsView`, `StaffView`, `ChordDiagram`, `FollowList`, … | views; they draw and forward clicks |

Two ideas carry most of the weight:

**One clock.** MPRIS reports position on demand and some players only on state changes, so `SongModel` anchors to
each report and extrapolates on the monotonic clock, scaled by the playback rate. Everything reads `playbackPosition`
(position plus the per-song lyric offset). A line never lights before its time: views highlight up to `syncLag`
(0.25 s) *after* a timestamp, absorbing the output path's latency.

**One schedule.** The model lays the service's `row_times` onto the chart's rows (an even spread if there are
none), then derives chord events: a chord sits at the same fraction along its row's duration as its first letter
along the lyric, instrumental rows spread theirs evenly. "Now", "next", the countdown, section spans, the loop and
the highlight all read from it, and the popup and the window share it.

### Capo, transposition, key

Tabs write chord names as the *shapes* played above the capo they state. So the sounding chord is the shape raised
by `chartCapo` semitones; the capo control is the capo you will actually use, `effectiveTranspose = transpose +
chartCapo − capo`, and `capo === chartCapo` shows the tab as written. `suggestCapo` prices every shape (0 for a
comfortable open chord, 2.5 for a full barre), weights it by how often it occurs, and picks the cheapest capo up to
the seventh fret, preferring the lower on a tie.

### Decisions worth knowing

- **Standard-library-only service.** A daemon that starts at login and is installed by copying files should not
  need a virtualenv. Data is vendored (chords-db) instead.
- **Loopback HTTP, not D-Bus**, because QML's `XMLHttpRequest` is the simplest bridge and `lyricist` is also a CLI
  that prints the same data. The price is the hardening in [SECURITY.md](../SECURITY.md).
- **A tab can only be fetched from Ultimate Guitar**, even when pinned by address.
- **No fixed key table for fingerings.** chords-db covers 500+ chords with several positions each; the hand-written
  barre derivation is only the fallback.
- **The strumming pattern is not drawn.** UG stores it in its own numeric code; only the tempo is used, because
  guessing the rest would show wrong arrows.

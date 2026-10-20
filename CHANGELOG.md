# Changelog

All notable changes are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [2.0.0] — 2026-10-19

A rebuild of the widget and a hardening of the service. Settings, saved charts and per-song memory carry over.

### Added
- **The Stage:** the chord to play now, large, with fingering, finger numbers, notes and roman numeral; the next
  chord with a countdown; a chord tapped in the chart previews there. The sounding chord is marked in the chart.
- **Capo calculator** and **key detection** (the tab's stated key, else worked out from the chords).
- **Practice tools:** section chips (jump), loop a section, playback speed where the player allows it.
- **Tablature as music:** staves parsed from tabs and re-flowed at bar lines; songs that only have a tab now fall
  back to one. Tab metadata (tuning, difficulty, tempo, rating, views) shown as chips.
- **Better fingerings:** [chords-db](https://github.com/tombatossals/chords-db) voicings with finger numbers and
  barres; Ultimate Guitar's own fingering for the chords on a tab; left-handed mirroring.
- Pin a tab by pasting its Ultimate Guitar address. A panel mode that shows the current chord.
- `lyricist doctor`, `lyricist cache prune`; `make install|uninstall|test|lint|shots`.
- Tests (pytest, node, qmltestrunner), a headless screenshot harness, CI, REUSE licensing, documentation.

### Changed
- `main.qml` is Plasma glue; all state and logic is in `SongModel.qml`, shared by the popup and the window. The
  chart's timing is computed once, in `schedule.js`, instead of by each view.
- Kirigami `Chip` and `ActionToolBar` and the Plasma `TabBar` replace hand-built equivalents; the toolbar folds into
  an overflow menu when narrow.
- Fingering data moved from hand-typed tables to chords-db.
- The systemd unit is sandboxed.

### Fixed
- A slow reply for the previous track could overwrite the current track's chart.
- The "other versions" list survived a track change and showed the previous song's.
- Resuming after a pause made the highlight leap ahead by the length of the pause.
- Barre diagrams above the nut were drawn a fret too low.
- One global lock held while sleeping made the request throttle serialise every host, not just one.
- An unwritable cache directory made requests fail instead of being ignored.
- Per-song locks and the prefs file's eviction order leaked/misbehaved over a long session.

### Security
- A pinned tab could be any URL, including `file://` and LAN addresses; only `https://*.ultimate-guitar.com` is
  fetched now.
- Any web page could read the local API (CORS `*`), change it with a text/plain POST, or set `songrec_path` to an
  arbitrary program through `POST /api/config`. See [SECURITY.md](SECURITY.md).

## [1.0.0]

The installed widget and service this work started from, imported unchanged as the first commit of this
repository.

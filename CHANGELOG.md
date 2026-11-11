# Changelog

All notable changes are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [2.0.1] — 2026-11-10

Chordist runs on the KDE Frameworks that Debian 13 ships, installs on distributions other than Arch, and is now
packaged and released by CI.

### Fixed

- **The popup failed to load on KDE Frameworks older than 6.16** (Debian 13 ships 6.13): it used
  `Kirigami.Chip.interactive` (Frameworks 6.16) and `Kirigami.Theme.fixedWidthFont` (6.14), so the info strip,
  section bar and Stage did not load and the chord chart threw errors. Both are now used only where they exist.
- `make lint` and `make test` looked for Qt only in Arch's `/usr/lib/qt6`; they now ask `qtpaths6` (Fedora and
  openSUSE keep it in `/usr/lib64`) and leave out qmllint options that an older Qt does not know.
- `make install PREFIX=…` wrote a service unit that still pointed at `~/.local/bin`; it now points at the launcher it
  installed. Without a running user systemd, `make install` prints the commands to run instead of stopping with the
  widget uninstalled.
- `make migrate-panel` could leave the panel stopped when a step failed. It now checks for `kwriteconfig6` before it
  stops anything, and always brings the shell back, through systemd when Plasma runs under it.
- Audio identification records for 1 to 30 seconds whatever the setting says, and a recorder that overstays is
  killed with everything it started. SongRec is found in `~/.cargo/bin` and `~/.local/bin`, which a systemd service's
  `PATH` does not include, and `chordist doctor` shows which one is used.
- The service's sandbox follows `XDG_CONFIG_HOME` instead of assuming `~/.config`.
- `chordist lyrics` and `chordist chords` exit non-zero, with the reason on stderr, when nothing was found.
- The tempo chip no longer logs an i18n warning on every load.
- The Arch package depends on `hicolor-icon-theme`, which owns the icon directory it installs into (a namcap
  error), and declares `bash` and `kcmutils`, which it uses directly.

### Changed

- `make deps` lists only what running Chordist needs, checks for Python 3.12 or newer, and prints the install line
  for the distribution it runs on (Arch, Debian and Ubuntu, Fedora, openSUSE). `make deps-dev` adds the test and
  lint tools.
- The "open as a window" setting says what it does: on top under X11; under Wayland, Keep Above from the window's
  title-bar menu.
- The README states the tested range and covers installing SongRec, `songrec_path`, and the service's sandbox on
  kernels without unprivileged user namespaces.
- The wheel builds with uv_build 0.13 or 0.14 and carries the licence.

### Added

- Every merge request builds the Arch package as a normal user, fails on any namcap error, installs and runs it,
  and builds the AUR files from the same tarball. It also runs the tests on Python 3.12, 3.13 and 3.14, on Debian 13
  (loading every widget component on its Kirigami 6.13) and on Fedora, and lints the QML with the KDE modules
  installed.
- A test that creates every widget component on the installed Qt and KDE stack (`make test-qml`).
- Releases are cut by pushing a `vX.Y.Z` tag: CI builds the tarball, keeps it in the project's package registry,
  creates the GitLab release from this changelog and generates the AUR `PKGBUILD`, `chordist.install` and
  `.SRCINFO` from `packaging/` (`make aur`), so the AUR package cannot drift from this repository.

## [2.0.0] — 2026-11-10

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
- For a public repository: LICENSE and third-party notices, code of conduct, issue and merge-request templates, an
  icon, an Arch `PKGBUILD` (`make pkgbuild`), `make dist` and `make check-build`, a `chordist` command next to
  `chordistd`, a troubleshooting guide, a release guide, an animated demo (`make demo`), and a `Legal` and
  `Known limits` section in the README.
- Python coverage went from 71% to 89% (`make coverage`): the CLI, titles, transliteration, LRC parsing,
  fingerprinting, identity resolution and lyrics search all have tests now.

### Changed
- The project lives at [gitlab.com/ritwick7/chordist](https://gitlab.com/ritwick7/chordist), mirrored to
  [GitHub](https://github.com/RitwickVerma/chordist). It was `…/chordify`, a name that belongs to someone else; the old address redirects.
- **Renamed: everything is Chordist now** (it was `lyricist`): widget `com.ritwick.chordist`, service `chordistd`,
  CLI and package `chordist`, state in `~/.config|.local/share|.cache/chordist`. `make install` migrates the service
  and your data; `make migrate-panel` moves the panel entry, keeping its position and settings.
- `main.qml` is Plasma glue; all state and logic is in `SongModel.qml`, shared by the popup and the window. The
  chart's timing is computed once, in `schedule.js`, instead of by each view.
- Kirigami `Chip` and `ActionToolBar` and the Plasma `TabBar` replace hand-built equivalents; the toolbar folds into
  an overflow menu when narrow.
- Fingering data moved from hand-typed tables to chords-db.
- The systemd unit is sandboxed.

### Fixed
- `make test` failed on Node 22 LTS, which reads `node --test <directory>` as a file to run.
- A slow reply for the previous track could overwrite the current track's chart.
- The "other versions" list survived a track change and showed the previous song's.
- Resuming after a pause made the highlight leap ahead by the length of the pause.
- Barre diagrams above the nut were drawn a fret too low.
- One global lock held while sleeping made the request throttle serialise every host, not just one.
- An unwritable cache directory made requests fail instead of being ignored.
- Per-song locks and the prefs file's eviction order leaked/misbehaved over a long session.

- Chart and tab parsing, theory and timing, found in a review pass:
  - `CM7`/`CM9` were simplified to a *minor* chord in easy mode.
  - Adjacent chord names were glued together (`AmF`); chord tones were mis-spelled (the third of `Gm` was `A#`),
    and altered extensions (`7b9`) gave the natural note. Transposed chords now use guitarists' spellings
    (`Bb`, `Eb`, `G#m`), and an easy open chord with an extension (`A7sus4`) is no longer priced as a barre.
  - A tab staff that began before its first bar line lost that music when re-flowed; barless pieces overflowed;
    `999999` views read "1000k".
  - The next-chord countdown reached zero before the chord actually switched; chords of a zero-length row
    could reorder.
  - Settings saved after a quick skip could be written onto the *next* song, a track change erased pending
    pinned picks, and loading a song wrote its defaults back as if the user had chosen them.
  - Pasting a chart for a song whose metadata is decorated ("... (Official Video)") saved it under a name lookups
    never used, so it was never found; deleting and the version chooser had the same mismatch. A pinned tab
    skipped identity resolution and so lost its lyrics.
  - Ultimate Guitar searches were not URL-encoded (`&`, `#`, and every non-ASCII title failed outright).
  - A chart file named after an artist was returned for every song by them.
  - "No chords found" and "no lyrics" were never actually remembered, so every retry re-ran the whole search;
    now remembered (and "Ask again" looks past it), without ever remembering "offline" as "not found".
  - A pinned tab that failed to load made the whole song fail, lyrics included; it now falls back and says so.
  - The server kept a connection alive after refusing a request without reading its body, so that body was parsed
    as the next request. A glide animation fought the user's scrolling. `Config.save` wrote every default into
    `config.json`. Concurrent cache writers shared a temp file.
  - With nothing playing, pasting a chart saved it as `untitled-<time>` with no song; the widget and the service
    now refuse.
  - Aligning a long chart took about a second per lookup; it is 15x faster, with identical results.

### Security
- `Origin: null` and cross-site fetch metadata are refused as well; redirects may not leave http(s).
- A pinned tab could be any URL, including `file://` and LAN addresses; only `https://*.ultimate-guitar.com` is
  fetched now.
- Any web page could read the local API (CORS `*`), change it with a text/plain POST, or set `songrec_path` to an
  arbitrary program through `POST /api/config`. See [SECURITY.md](SECURITY.md).

## [1.0.0]

The installed widget and service this work started from, imported unchanged as the first commit of this
repository.

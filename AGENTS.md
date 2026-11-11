# AGENTS.md

Operating guide for anyone (human or agent) changing this repo. [README.md](README.md) says what it is,
[docs/architecture.md](docs/architecture.md) why it is shaped this way, [SECURITY.md](SECURITY.md) what leaves the
machine.

## Layout

```
applet/      the Plasma widget (a KPackage): main.qml is Plasma glue, SongModel.qml holds all state and logic,
             the rest are views; js/ holds the pure logic (theory, schedule, tab layout)
chordist/    the local service (Python, standard library only), `chordist serve`; data/ has the vendored chords-db
bin/         chordistd, the launcher the systemd unit runs
packaging/   the systemd user unit, the PKGBUILD (the only one: the AUR copy is generated from it) and its .install
ci/          what the pipeline runs that is not a make target: the image, the Arch package and release scripts
tests/       python/ (pytest), js/ (node --test), qml/ (qmltestrunner + the screenshot harness)
tools/       update-chords-db.py; deps.sh (`make deps`); aur-pkgbuild.py (AUR files) and gitlab-release.py (tag pipeline)
docs/        architecture, API, testing
```

## Run

```sh
make deps                    # what is missing
make install                 # into ~/.local; (re)starts the service, never plasmashell
systemctl --user restart plasma-plasmashell     # the owner's step
python3 -m chordist chords "Oasis" "Wonderwall"      # the service's lookups from a terminal
python3 -m chordist doctor
```

## Test

```sh
make test      # pytest (no network), node --test, qmltestrunner (Qt 6, offscreen; also loads every component)
make lint      # reuse, ruff, vulture, qmllint (warnings are errors), shellcheck
make shots     # headless renders of the real QML against a fixture service -> build/shots
```

- `qmltestrunner` must be the **Qt 6** one (`/usr/lib/qt6/bin`); `/usr/bin/qmltestrunner` is Qt 5.
- Output from quiet test runners can be mangled by a shell output filter; `rtk proxy <cmd>` shows it raw.
- A UI change is not done until it has been rendered (`make shots`, look at the PNGs) and, if it touches
  `main.qml`, `Compact.qml` or config, loaded in a real Plasma host: [docs/testing.md](docs/testing.md).

## Rules

- **One name.** Widget `com.ritwick.chordist`, service `chordistd`, package and CLI `chordist`, state in
  `~/.config|.local/share|.cache/chordist`. Pre-2.0 it was `lyricist`; `tools/migrate-from-lyricist.sh` (tested in
  `tests/python/test_migrate.py`) is the only place the old name may appear, besides the changelog. Renaming again
  means a migration for the widget id (the panel stores it) and for the three state directories.
- **No Python dependencies in the service.** It is a login daemon installed by copying files. Reach for the
  standard library; vendor *data* (as chords-db is) rather than adding a package.
- **Use FOSS that already does the job** (Kirigami, Plasma components, chords-db, SongRec, LRCLIB) instead of
  rewriting it. Hand-written code is for what nobody ships: chart and tab parsing, alignment, the capo calculator.
- **Logic goes in `SongModel.qml` or `js/`**, not in views. Views draw and forward clicks. Pure functions get a
  node test; model behaviour gets a `tst_songmodel.qml` case.
- **The service never trusts its caller.** It fetches only `https://*.ultimate-guitar.com`, accepts POSTs only as
  `application/json`, sends no CORS headers, checks `Host` and `Origin`, and `POST /api/config` changes only
  the keys in `MUTABLE_CONFIG`. Do not loosen any of these; add a test if you touch them.
- **A cache or prefs failure must never fail a request.** Reads and writes under the XDG directories are
  best-effort.
- **A song has one name.** Lookups, saving a chart, deleting one and the version chooser all use the identity the
  song resolved to (`Service._known_identity`, which never starts an audio capture), and `clean()` on top. Anything
  that keys data by artist/title must go through the same path, or it will be saved under one name and sought under
  another.
- **Not found is not offline.** Cache a miss only when the site answered. A network failure must stay uncached.
- **Per-song settings follow the song they were loaded for** (`SongModel._prefsFor`), not whatever plays when a
  timer fires, and putting a song's own settings back is not a user change (`_applying`).
- **Timing is monotonic.** A chart row's time never goes backwards, and a line never lights before its time
  (`syncLag`).
- Unit-file sandboxing is real: new files the service writes must be under `~/.config/chordist`,
  `~/.local/share/chordist` or the cache directory, or `ReadWritePaths` must grow.
- **The widget has to load on the oldest Kirigami it claims (6.13, Debian 13).** Check a Kirigami/Plasma property or
  type against that release before using it, and look a newer one up by name (`typeof x["prop"]`) rather than
  writing it in a binding. `tests/qml/tst_components.qml` creates every component and the `debian-trixie` job runs it
  on Kirigami 6.13. A new top-level component gets covered by being in `contents/ui`; one needing a module that
  Debian does not package goes on the (commented) list there.
- QML: `Layout.fillHeight: false` on nested layouts that should not stretch (a hidden-row layout otherwise
  soaks up spare height); methods and properties cannot start with a capital, so MPRIS fakes are plain objects.
- Never push to the default branch; open a merge request. Never restart the owner's plasmashell or service
  from a task: hand over the command.

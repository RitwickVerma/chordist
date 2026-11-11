# Testing

Four layers, from cheapest to most real. `make test` runs the first three; the fourth is by hand.

| Layer | Command | Covers |
| --- | --- | --- |
| Python | `make test-python` | chart/tab parsing, shapes, providers against faked Ultimate Guitar pages, the HTTP server and every one of its guards, cache, prefs, throttle. The suite blocks the network, so a test that reaches for it fails. |
| JS | `make test-js` | `theory.js`, `schedule.js`, `tab.js`, `util.js`, loaded exactly as the widget loads them (the `.pragma library` line is stripped) |
| QML model | `make test-qml` | `SongModel.qml`: active row and lag, now/next chord, capo and key advice, voicing choice, loop, position extrapolation across a pause, pinning, clamping. Qt 6's `qmltestrunner`, offscreen, a plain object standing in for the MPRIS player. |
| QML components | `make test-qml` | every `contents/ui/*.qml`, `ui/config/*.qml` and `config/config.qml` created on the Qt and KDE stack installed (`tests/qml/components.sh`, `tst_components.qml`): fails on a component that does not load (a property the installed Kirigami lacks) and on any warning the load prints. |
| Real shell | below | `main.qml`, `Compact.qml`, the config page, Mpris wiring |

CI runs the same `make` targets (the `qml` and `qml-tests` jobs install Plasma and Kirigami first, so qmllint resolves
every KDE type and the components load against today's Arch) and adds three jobs that are not `make` targets:

- `package-arch` builds the Arch package from the tree as a normal user (`ci/package-arch.sh`), runs namcap (an `E:` fails
  the job), installs the package, checks `chordist --help` and the plasmoid files, then builds the AUR files for the same
  tarball and compares the two packages.
- `python-compat` runs pytest on Python 3.12, 3.13 and 3.14; `debian-trixie` runs pytest, node and qmltestrunner on
  Debian's Python 3.13, Node 20, Qt 6.8 and Kirigami 6.13, the oldest stack the widget claims, where the components
  test is the one that matters (Debian packages `org.kde.plasma.plasmoid` and `.configuration` nowhere, so `main.qml`
  and `config.qml` are skipped there, listed in the output); `fedora-install` runs `make install`/`uninstall` into a
  throwaway home on the current Fedora release (`ci/install-layout.sh`).
- `release` runs on tags only ([releasing.md](releasing.md)).

To reproduce one, run its script in the image it names, e.g.
`docker run --rm -v "$PWD":/src -w /src archlinux ci/package-arch.sh`.

## Screenshots

`make shots` (or `tests/qml/run.sh OUT [scenario…]`) starts `tests/qml/fixture_service.py`, a real service with
canned data for two public-domain songs and no network, and renders the real `Full.qml` against the real
`SongModel` with Qt's offscreen platform and the KDE desktop style. Scenarios: `chords ug lefty tab lyrics versions
empty`. KDE's `i18n()` exists only inside the shell, so the runner swaps in a shim that substitutes `%1…` in a
scratch copy; the tree itself is never modified. **Look at the PNGs**: layout bugs (a hidden layout stealing
height, an overflowing toolbar) do not show up in any assertion.

## Real shell

Load the widget in a real Plasma host without touching your session: private data, config and cache, and a private
D-Bus so no live player or service is involved.

```sh
S=$(mktemp -d); mkdir -p $S/{data,config,cache}
XDG_DATA_HOME=$S/data kpackagetool6 -t Plasma/Applet -i applet
XDG_DATA_HOME=$S/data XDG_CONFIG_HOME=$S/config XDG_CACHE_HOME=$S/cache \
  QT_ASSUME_STDERR_HAS_CONSOLE=1 QT_QPA_PLATFORM=offscreen \
  timeout 20 dbus-run-session -- plasmawindowed com.ritwick.chordist
```

It should run until the timeout (exit 124) and print no `QML`, `TypeError` or `ReferenceError` lines.

## The sandboxed unit

To check the unit's sandboxing without installing it, run the service as a transient unit with the same properties
and state outside `/tmp` (the unit has `PrivateTmp`), then `curl /api/health`, `POST /api/paste` and confirm
the files land only in the data directory. The properties are the `[Service]` block of `packaging/chordistd.service`.

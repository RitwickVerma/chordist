# Troubleshooting

Start with the two commands that know the most:

```sh
chordist doctor                          # what the service can and cannot do here
journalctl --user -u chordistd -n 50     # what it has been saying
```

(`chordist` is the installed command; from a checkout use `python3 -m chordist`.)

## The widget is not in the panel / its icon vanishes

The panel item hides itself while the current song has neither a chord chart nor lyrics, so there is no dead icon
sitting there. Start something playing and give it a few seconds. If a song you expect to work never shows it, see
"No chords found" below.

If you added the widget before 2.0 and it now says the widget is missing, the panel still points at the old
`com.ritwick.lyricist`: run `make migrate-panel` once (see the README).

## "The Chordist service is not running"

```sh
systemctl --user status chordistd
systemctl --user restart chordistd
```

If it fails to start, `journalctl` says why. The usual causes:

- **Port 8788 is taken.** Change `"port"` in `~/.config/chordist/config.json` *and* the service address in the
  widget's settings.
- **`status=226/NAMESPACE`.** The unit sandboxes the service and needs its three directories to exist:
  `mkdir -p ~/.config/chordist ~/.local/share/chordist` and restart.

## No chords found for this track

- Look at what the player reports (the title and artist at the top of the popup). Videos often put the channel in the
  artist field and decoration in the title; the service takes that apart, but a very unusual title can defeat it.
- `chordist chords "<artist>" "<title>"` shows exactly what the service finds, without the widget in the way.
- Use the magnifier button (**Other versions**) to pick a tab by hand, or paste an Ultimate Guitar address, or paste
  the chart itself. Anything you pick or paste is remembered for that song.
- "Nothing found" answers are remembered for three days so the site is not searched again and again. **Ask again** in
  the `⋮` menu looks past that.
- Ultimate Guitar occasionally rate-limits or changes its pages. `ug_enabled: false` turns the lookup off; your own
  charts keep working.

## The wrong song's chords or lyrics

Use **Other versions** (the magnifier). The automatic pick prefers a match on title, artist and recording length, but
the same song exists many times (live, acoustic, remaster). Your choice is saved per song.

## The highlight is early, late, or drifting

- Lyrics come from LRCLIB with timings made for *one* release. The **Lyrics timing** row (Lyrics tab) nudges them, and
  the refresh button there pulls the nearest line onto what you are hearing now. It is remembered per song.
- Bluetooth speakers add delay the player does not report. Nudge the lyrics later.
- A chart is aligned to the lyric timings. With no synced lyrics it is spread evenly over the song, which follows
  the music loosely. Pasting a chart for a song never makes it more precise than its lyrics.

## Chord names look wrong or odd

- Tab sites write chord names as the *shapes* played above the capo they state. With the capo box set to the tab's
  capo you see it as written; set it to 0 to see the chords that actually sound.
- **Easy** reduces every chord to a plain major or minor triad.
- A "Key" chip is the key the tab states, or, if it does not say, a guess from the chords.

## Audio identification does nothing

It only runs when the player's metadata cannot be matched by name, and needs `songrec`, `pw-record` and `pactl`
(`chordist doctor` shows which are missing). It listens to your default output for a few seconds, so something has to
be playing. Switch it off with `"fingerprint_enabled": false`.

## The floating window does not stay on top

Wayland clients cannot ask for that. Use the title-bar menu (**More actions → Keep above others**) or a KWin window
rule for "Chordist".

## Reporting a bug

Please include: the output of `chordist doctor`, your Plasma version (`plasmashell --version`), what the player
reports for the song, and for a wrong-chords report `chordist chords "<artist>" "<title>" --json`. The issue
templates ask for exactly these.

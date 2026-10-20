# Service HTTP API

`lyricistd` on `http://127.0.0.1:8788` (see `host`/`port`). JSON in and out. `GET /api/health` is the quick check.
Requests from a non-loopback `Host`, or with a cross-site `Origin`, get `403`. Writes must be
`Content-Type: application/json` (`415` otherwise), bodies are capped at 1 MiB (`413`). There are no CORS headers.

## Read

| Request | Returns |
| --- | --- |
| `GET /api/health` | `{ok, version, port, sources, ug_enabled, contact_configured, local_charts, uptime_seconds}` |
| `GET /api/song?artist=&title=&album=&duration=[&romanise=0\|1][&lyrics_id=][&chord_url=]` | everything for a song, below |
| `GET /api/lyrics?…` | just the lyrics object |
| `GET /api/chords?artist=&title=&duration=[&chord_url=]` | just the chart |
| `GET /api/versions?artist=&title=&album=&duration=` | `{lyrics: [...], charts: [...]}` candidates for the "wrong version" chooser |
| `GET /api/shapes?names=C,Am7,F%23m` | `{shapes: {name: voicing}, variations: {name: [voicing…]}}` (at most 64 names) |
| `GET /api/prefs?artist=&title=` | the song's remembered `{offset, transpose, capo, lyrics_id, chord_url}` |
| `GET /api/local` | `{items: [{file, slug, size, modified}]}`: your own charts |
| `GET /api/config` | the effective configuration |

`chord_url` must be an `https://*.ultimate-guitar.com` address; anything else is ignored.

### `/api/song`

```
{ query, lyrics, chords, shapes, variations, transpose, romanised, resolved, prefs }
```

- `lyrics`: `{source, id, track, artist, album, duration, synced, word_synced, instrumental, lines: [{t, text, words}], plain, romanised?, pinned?}`
- `chords`: a chart (see [architecture](architecture.md)), plus `url`, `capo`, `key`, `rating`, `votes`, `version`,
  `meta` (`{tuning: {name, notes}, difficulty, tonality, type, rating, votes, views, favorites, author, bpm,
  strumming, simplified_available}`), `applicature` (`{chord: [voicing]}`, Ultimate Guitar's own fingerings),
  `row_times` (one per chart row with lyrics, aligned to the synced lyrics), `cached?`, `pinned?`
- a **voicing**: `{name, frets[6], fingers[6], base, barre, bass, source}`; strings run low E to high e, `frets` are
  absolute (`-1` muted, `0` open), `base` is the fret the diagram's first row sits on, `barre` the barre fret or `null`
- `resolved`: set when the song was understood to be something other than the raw metadata

## Write

| Request | Body | Does |
| --- | --- | --- |
| `POST /api/paste` | `{artist, title, text, format?}` | parses a chart and saves it as ChordPro; it beats the internet from then on |
| `POST /api/prefs` | `{artist, title, offset?, transpose?, capo?, lyrics_id?, chord_url?}` | remembers per-song settings |
| `POST /api/config` | any of `contact chords_sources ug_enabled romanise fingerprint_enabled fingerprint_seconds log_level min_request_interval negative_ttl_seconds request_timeout` | merges into `config.json`; other keys get `403` |
| `DELETE /api/local?artist=&title=` | | deletes your saved chart for that song |

Errors are `{error: "..."}` with the status; a song lookup that finds nothing is a normal `200` with empty
`lyrics`/`chords`.

# Security and privacy

## What leaves your machine

| When | What | To |
| --- | --- | --- |
| a song starts | its artist, title, album and length | [LRCLIB](https://lrclib.net) (lyrics) and [Ultimate Guitar](https://www.ultimate-guitar.com) (charts, tabs), unless `ug_enabled` is `false` |
| a track's metadata cannot be matched to a song, and `fingerprint_enabled` is `true` (the default) | about six seconds of the audio playing on your default output, recorded from its PipeWire monitor and turned into a fingerprint | Shazam's service, through [SongRec](https://github.com/marin-m/SongRec) |

Nothing else. No account, no telemetry. Results are cached under `~/.cache/lyricist`; your charts and per-song
settings stay in `~/.local/share/lyricist`.

To keep lookups to text only, set `"fingerprint_enabled": false` in `~/.config/lyricist/config.json`. To stay
offline except for lyrics, also set `"ug_enabled": false`. Fingerprinting records *whatever is playing*, including
a call or a video if it is on that output at the time; that is why it is a switch, and why it only runs when the
metadata cannot be resolved some other way.

## The local service

`lyricistd` listens on `127.0.0.1:8788`. Anything on the machine can reach that, including a web page in your
browser, so the service defends itself:

- no CORS headers: a page cannot read an answer, and cannot pass a preflight to change anything;
- `Host` must be loopback (against DNS rebinding) and a cross-site `Origin` is refused;
- writes must be `application/json`, which a browser cannot send cross-site without a preflight;
- bodies are capped at 1 MiB, and a pinned tab may only be an `https://*.ultimate-guitar.com` address (it used to
  be any URL, which allowed fetching local files and LAN hosts);
- `POST /api/config` accepts a fixed list of safe keys. Which program runs (`songrec_path`), where the service
  listens and where it writes are edited in `config.json` only;
- the systemd unit adds `NoNewPrivileges`, a read-only view of the filesystem apart from its three directories,
  and restricts address families, namespaces and kernel interfaces.

Each of these has a test in `tests/python/test_server.py` or `test_chords.py`.

## Reporting

Email the maintainer (see the git log) with details; please do not open a public issue for a vulnerability. This is
a one-person project, so expect a reply in days, not hours.

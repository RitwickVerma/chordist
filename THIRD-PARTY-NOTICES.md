# Third-party notices

## Shipped in this repository

| What | Where | Licence |
| --- | --- | --- |
| [chords-db](https://github.com/tombatossals/chords-db): guitar chord fingerings, trimmed to the fields the service reads by `tools/update-chords-db.py` | `chordist/data/guitar-chords.json` | MIT, (c) 2016 David Rubert. Full text: [chordist/data/LICENSE.chords-db](chordist/data/LICENSE.chords-db) |

## Used at run time, not shipped

These are installed separately and used through their public interfaces. Their licences do not apply to this
repository's code, and nothing of them is copied into it.

| What | How it is used |
| --- | --- |
| KDE Plasma, Kirigami, Qt, KDE Frameworks (LGPL/GPL) | the widget runs inside Plasma and uses its components |
| [SongRec](https://github.com/marin-m/SongRec) (GPL-3.0) | started as a separate program to identify audio; never linked |
| [LRCLIB](https://lrclib.net) | the service asks its public HTTP API for synced lyrics |
| [Ultimate Guitar](https://www.ultimate-guitar.com) | chord charts and tabs are fetched from its public pages on request, kept in a local cache and never redistributed by this project |

## Trademarks

Plasma and KDE are trademarks of KDE e.V. Ultimate Guitar is a trademark of its owner and Shazam is a trademark of Apple
Inc. They are named here only to say what this software works with.
Chordist is not affiliated with, endorsed by, or sponsored by any of them.

# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
#
# SPDX-License-Identifier: MIT

"""A Chordist service with canned data, for the QML harness and its tests.

Serves the real HTTP API on the given port, but nothing leaves the machine:
lyrics, identity and tab-site lookups are replaced by two public-domain songs.
State (config, caches, saved charts) lives in a throwaway directory.

    python fixture_service.py PORT STATE_DIR
"""

from __future__ import annotations

import os
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, REPO)

GRACE_LYRICS = [
    (6.0, "Amazing grace how sweet the sound"),
    (13.0, "That saved a wretch like me"),
    (20.0, "I once was lost but now am found"),
    (27.0, "Was blind but now I see"),
]

GRACE_CHART = """{title: Amazing Grace}
{artist: Traditional}
{key: G}
{comment: Verse 1}
[G]Amazing [G7]grace how [C]sweet the [G]sound
That [G]saved a [Em]wretch like [D]me
{comment: Verse 2}
I [G]once was [G7]lost but [C]now am [G]found
Was [Em]blind but [D]now I [G]see
"""

TAB_CHART = """{title: Open String Study}
{artist: Traditional}
{comment: Intro}
{start_of_tab}
e|-----0-----0-----0-----0-----|-----3-----3-----3-----3-----|-----2-----2-----2-----2-----|
B|---1-----1-----1-----1-------|---0-----0-----0-----0-------|---3-----3-----3-----3-------|
G|-0-----0-----0-----0---------|-0-----0-----0-----0---------|-2-----2-----2-----2---------|
D|-----------------------------|-----------------------------|-----------------------------|
A|-3---------------------------|-2---------------------------|-0---------------------------|
E|-----------------------------|-----------------------------|-----------------------------|
{end_of_tab}
"""


def main() -> None:
    port, state = int(sys.argv[1]), sys.argv[2]
    for name in ("config", "data", "cache"):
        path = os.path.join(state, name)
        os.makedirs(path, exist_ok=True)
        os.environ[f"XDG_{name.upper()}_HOME"] = path

    from chordist import chords, identity, lyrics, server
    from chordist.config import Config

    config = Config(
        {
            "host": "127.0.0.1", "port": port, "chords_sources": ["local"], "ug_enabled": False,
            "fingerprint_enabled": False, "min_request_interval": 0, "log_level": "warning",
        }
    )

    def lookup(self, artist, title, album="", duration=0.0, lyrics_id=None):
        if "grace" in title.lower():
            lines = [{"t": t, "text": text, "words": []} for t, text in GRACE_LYRICS]
            return {"source": "lrclib", "synced": True, "lines": lines, "plain": "", "track": title,
                    "artist": artist, "album": "", "duration": 34, "id": 1}
        return {"source": "none", "lines": []}

    lyrics.LyricsProvider.lookup = lookup
    lyrics.LyricsProvider.candidates = lambda self, *a, **k: [
        {"id": 1, "track": "Amazing Grace", "artist": "Traditional", "album": "Hymns", "duration": 34,
         "synced": True, "instrumental": False, "word_synced": False, "score": 20.0},
        {"id": 2, "track": "Amazing Grace (Live)", "artist": "Traditional", "album": "", "duration": 41,
         "synced": False, "instrumental": False, "word_synced": False, "score": 9.0},
    ]
    chords.ChordProvider.candidates = lambda self, *a, **k: [
        {"url": "https://tabs.ultimate-guitar.com/tab/traditional/amazing-grace-chords-1", "name": "Amazing Grace",
         "artist": "Traditional", "type": "Chords", "version": 2, "rating": 4.7, "votes": 3120,
         "tonality": "G", "score": 11.0},
        {"url": "https://tabs.ultimate-guitar.com/tab/traditional/amazing-grace-tabs-2", "name": "Amazing Grace",
         "artist": "Traditional", "type": "Tabs", "version": 1, "rating": 4.2, "votes": 88, "tonality": "G", "score": 7.0},
    ]
    identity.resolve = lambda *a, **k: None

    httpd = server.Server(config)
    httpd.service.chords.save_local("Traditional", "Amazing Grace", GRACE_CHART)
    httpd.service.chords.save_local("Traditional", "Open String Study", TAB_CHART)
    print(f"ready {port}", flush=True)
    httpd.serve_forever()


if __name__ == "__main__":
    tempfile.tempdir = tempfile.tempdir  # keep the linter honest about the import
    main()

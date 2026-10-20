"""Take a polluted streaming title apart into song names worth searching.

Streaming metadata is written for people, not for a database. A video title is
"Judaai - Full Audio Song | Badlapur | Varun Dhawan, Yami Gautam | Rekha
Bhardwaj & Arijit Singh": one song buried under a movie name, an actor list and
a singer list. A tab site indexes the *song name*, so the raw string has to be
decomposed and each plausible name searched on its own, most likely first.

Everything here is deliberately conservative. A candidate is a literal run of
words from the title, and the matcher refuses any tab whose name introduces
words the title never had. Finding nothing is acceptable; playing somebody
else's song is not.
"""

from __future__ import annotations

import re
import unicodedata

# Separators a video site puts between song, movie, actors and singers. The
# bare forms catch titles like "Sahil Samuel-Zakir" where a space was dropped.
_SEPARATORS = (
    " | ", " / ", " – ", " — ", " · ", " - ", "| ", "/ ", " –", " —", " -",
    "- ", "– ", "— ", "|", "/", "–", "—", "·",
)

# A segment built only from these is production noise, not a song name.
_NOISE_WORDS = {
    "full", "audio", "song", "songs", "video", "videos", "lyric", "lyrics",
    "lyrical", "official", "music", "visualiser", "visualizer", "remastered",
    "remaster", "hd", "hq", "4k", "8d", "mv", "topic", "explicit", "clean",
    "mono", "stereo", "instrumental", "karaoke", "title", "track", "version",
    "new", "latest", "high", "quality", "hindi", "bollywood", "fullsong",
    "with", "and", "the", "out", "now",
    # The platform, not the song: a segment built only from these is the site
    # or the uploader, never a title worth searching for.
    "youtube", "yt", "vevo", "upload", "channel",
}

# A segment containing these is a list of people, not a song name.
_CREDIT_WORDS = {
    "feat", "ft", "featuring", "starring", "singer", "singers", "actor",
    "actors", "composer", "lyricist", "director", "presented", "produced",
    "vocals", "artist",
}

# Words a tab name may add without saying anything about which song it is.
_VERSION_WORDS = {
    "acoustic", "live", "remix", "unplugged", "version", "demo", "session",
    "slowed", "reverb", "lofi", "lo", "fi", "cover", "reprise", "extended",
    "edit", "mix", "instrumental", "karaoke", "official", "audio", "video",
    "lyrics", "lyric", "remastered", "remaster",
    # Platform vocabulary must never make two different songs look alike: the
    # literal token "youtube" in "(9) Voh - YouTube" was enough for a junk
    # upload named "YOUTUBE" to be adopted as the identity of "Voh".
    "youtube", "yt", "vevo", "topic", "upload", "channel",
}

_STOP_WORDS = {
    "a", "an", "the", "of", "in", "on", "at", "to", "is", "i", "you", "me",
    "my", "we",
}

_WORD_RE = re.compile(r"[^\W_]+", re.UNICODE)
_REPEAT_RE = re.compile(r"(.)\1+", re.UNICODE)


def _plain(text: str) -> str:
    """Drop diacritics, so a tab's "Brahmāstra"/"Lambī" matches "Brahmastra"."""
    decomposed = unicodedata.normalize("NFKD", text or "")
    return "".join(ch for ch in decomposed if not unicodedata.combining(ch))


def tokens(text: str) -> list[str]:
    return _WORD_RE.findall(_plain((text or "").casefold()))


def fold(token: str) -> str:
    """Collapse doubled letters, so "Judaai", "Judai" and "Judaa" compare well."""
    return _REPEAT_RE.sub(r"\1", token)


def subset(context: str, phrase: str) -> bool:
    """True when every meaningful word of ``phrase`` already appears in ``context``.

    This is the guard that stops a search for "Judaai" from accepting a tab
    called "I Love Ny - Judaai" (the film "I Love Ny" is not in the title) or
    Arijit Singh's "Judaa". A tab may only add version words of its own.
    """
    known = {fold(t) for t in tokens(context)}
    meaningful = [
        t for t in tokens(phrase)
        if t not in _STOP_WORDS and t not in _VERSION_WORDS
    ]
    if not meaningful:
        return False
    return all(fold(word) in known for word in meaningful)


def shares_word(title: str, phrase: str) -> bool:
    """Does ``phrase`` use any meaningful word from ``title``?

    An album may be part of a tab's name (a soundtrack is filed as
    "Lootera - Zinda"), but album words alone never make a tab the right song:
    Radiohead's "Motion Picture Soundtrack" must not match a Badlapur track
    just because the film's album is called "... Motion Picture Soundtrack".
    """
    wanted = {
        fold(t) for t in tokens(title)
        if t not in _STOP_WORDS and t not in _VERSION_WORDS
    }
    if not wanted:
        return True
    return bool(wanted & {fold(t) for t in tokens(phrase)})


def film_filed(title: str, song_name: str, context: str) -> bool:
    """True for a tab filed as "<film/album> - <song>" with the song last.

    Ultimate Guitar names a soundtrack tab after the film, and the film's full
    title often carries more words than the album we resolved -- the Kesariya
    tab is "Brahmāstra Part One - Shiva - Kesariya" while the album is just
    "Brahmastra". Requiring every one of those words to be explained
    (``subset``) throws the tab away, so a tab whose LAST segment is the song
    is accepted when any earlier segment is already known from the
    artist/title/album context.
    """
    wanted = [
        fold(t) for t in tokens(title)
        if t not in _STOP_WORDS and t not in _VERSION_WORDS
    ]
    if not wanted:
        return False
    segments = split_segments(song_name)
    if len(segments) < 2:
        return False
    tail = [
        fold(t) for t in tokens(segments[-1])
        if t not in _STOP_WORDS and t not in _VERSION_WORDS
    ]
    if tail != wanted:
        return False
    known = {fold(t) for t in tokens(context)}
    for segment in segments[:-1]:
        words = {
            fold(t) for t in tokens(segment)
            if t not in _STOP_WORDS and t not in _VERSION_WORDS
        }
        if words & known:
            return True
    return False


def split_segments(title: str) -> list[str]:
    """Split a title on the separators video sites use, keeping order."""
    text = title or ""
    for separator in _SEPARATORS:
        text = text.replace(separator, "\x1f")
    return [part.strip() for part in text.split("\x1f") if part.strip()]


def _is_noise(segment: str) -> bool:
    words = tokens(segment)
    return bool(words) and all(word in _NOISE_WORDS for word in words)


def _is_credits(segment: str) -> bool:
    lowered = (segment or "").casefold()
    if "&" in lowered:
        return True
    if any(word in _CREDIT_WORDS for word in tokens(segment)):
        return True
    # "A, B, C" - a comma list of names is a cast or a singer lineup.
    return bool("," in segment and len(tokens(segment)) >= 2)


def song_candidates(title: str) -> list[str]:
    """The song names worth searching, most likely first.

    Video titles are usually "<song> - <noise> | <movie> | <people>" (the song
    leads) or "<channel> / <collaborator> - <song>" (the song trails), so the
    first and last meaningful segments are tried before the ones between them.
    """
    segments = split_segments(title)
    meaningful = [s for s in segments if not _is_noise(s) and not _is_credits(s)]
    ordered: list[str] = []

    def add(value: str) -> None:
        value = value.strip(" -–—|/·")
        if value and value not in ordered:
            ordered.append(value)

    if meaningful:
        add(meaningful[0])
        if len(meaningful) > 1:
            add(meaningful[-1])
        for segment in meaningful[1:-1]:
            add(segment)
    add(title)
    return ordered


def _split_people(segment: str) -> list[str]:
    return [
        piece.strip()
        for piece in re.split(r"\s*(?:&|,|/|\bfeat\.?\b|\bft\.?\b|\bfeaturing\b)\s*", segment, flags=re.I)
        if piece.strip()
    ]


def artist_hints(title: str, artist: str = "") -> list[str]:
    """Names that might be the artist: the player's, then the title's credits."""
    hints: list[str] = []

    def add(value: str) -> None:
        value = (value or "").strip(" -–—|/·")
        if value and value not in hints:
            hints.append(value)

    add(artist)
    for segment in split_segments(title):
        if _is_credits(segment):
            for piece in _split_people(segment):
                add(piece)
    return hints


def album_hints(title: str) -> list[str]:
    """Segments past the first meaningful one: usually the movie or album."""
    segments = split_segments(title)
    meaningful = [s for s in segments if not _is_noise(s) and not _is_credits(s)]
    hints: list[str] = []
    for segment in meaningful[1:]:
        if segment not in hints:
            hints.append(segment)
    return hints


def candidate_queries(
    artist: str, title: str, limit: int = 6, album: str = ""
) -> list[str]:
    """Search queries to try, in order, for a polluted title.

    ``album`` is an extra hint. Film and album names are how soundtrack charts
    are often filed on Ultimate Guitar (for example "Lootera - Zinda" for the
    song "Zinda"), so it is tried as a prefix pairing when the plain song name
    on its own finds nothing.
    """
    songs = song_candidates(title)
    albums = album_hints(title)
    artists = artist_hints(title, artist)
    queries: list[str] = []

    def add(value: str) -> None:
        value = re.sub(r"\s+", " ", (value or "")).strip()
        if value and value not in queries:
            queries.append(value)

    # The whole string first: unchanged behaviour when the title is already clean.
    add(f"{artist} {title}")
    add(title)
    # Soundtracks are often filed as "<Movie> - <Song>"; try that pairing too.
    if album:
        add(f"{album} {title}")
    for song in songs[:3]:
        for hint in artists[:2]:
            add(f"{hint} {song}")
        add(song)
        if albums:
            add(f"{song} {albums[0]}")
    return queries[:limit]

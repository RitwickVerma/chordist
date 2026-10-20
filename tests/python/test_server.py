# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
#
# SPDX-License-Identifier: MIT

from __future__ import annotations

import json
import threading
import urllib.error
import urllib.request

import pytest

from lyricist import server
from lyricist.config import Config, config_path

pytestmark = pytest.mark.loopback


@pytest.fixture
def api(monkeypatch):  # talks to its own loopback server through an opener, which the network guard allows
    config = Config({
        "host": "127.0.0.1", "port": 0, "chords_sources": ["local"], "ug_enabled": False,
        "fingerprint_enabled": False, "min_request_interval": 0,
    })
    httpd = server.Server(config)
    monkeypatch.setattr(httpd.service.lyrics, "lookup", lambda *a, **k: {"source": "none", "lines": []})
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    port = httpd.server_address[1]
    def call(method, path, body=None, headers=None, raw=None):
        data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
        request = urllib.request.Request(f"http://127.0.0.1:{port}{path}", data=data, method=method)
        if body is not None or raw is not None:
            request.add_header("Content-Type", "application/json")
        for key, value in (headers or {}).items():
            request.add_header(key, value)
        try:
            with urllib.request.build_opener().open(request, timeout=5) as response:
                return response.status, json.loads(response.read()), dict(response.headers)
        except urllib.error.HTTPError as exc:
            return exc.code, json.loads(exc.read() or b"{}"), dict(exc.headers)

    call.httpd = httpd
    yield call
    httpd.shutdown()
    httpd.server_close()


def test_health(api):
    status, body, headers = api("GET", "/api/health")
    assert status == 200 and body["ok"] is True and "uptime_seconds" in body
    assert not any(h.lower().startswith("access-control") for h in headers)


def test_unknown_route_is_404(api):
    assert api("GET", "/api/nope")[0] == 404


def test_foreign_host_header_is_refused_dns_rebinding(api):
    status, _, _ = api("GET", "/api/health", headers={"Host": "evil.example:8788"})
    assert status == 403


def test_cross_origin_page_is_refused(api):
    assert api("GET", "/api/config", headers={"Origin": "https://evil.example"})[0] == 403
    assert api("GET", "/api/health", headers={"Origin": "http://localhost:5173"})[0] == 200


def test_post_must_be_json_typed(api):
    request = urllib.request.Request(
        f"http://127.0.0.1:{api.httpd.server_address[1]}/api/prefs",
        data=b'{"artist":"a","title":"b","capo":3}', method="POST",
    )
    request.add_header("Content-Type", "text/plain")
    with pytest.raises(urllib.error.HTTPError) as err:
        urllib.request.build_opener().open(request, timeout=5)
    assert err.value.code == 415


def _raw(api, request: bytes) -> bytes:
    """Send bytes on a fresh connection and read until the server closes it."""
    import socket

    with socket.create_connection(("127.0.0.1", api.httpd.server_address[1]), timeout=5) as sock:
        sock.sendall(request)
        chunks = []
        while True:
            try:
                data = sock.recv(65536)
            except TimeoutError:
                break
            if not data:
                break
            chunks.append(data)
    return b"".join(chunks)


def test_oversized_and_malformed_bodies(api):
    declared = server.MAX_BODY + 1
    reply = _raw(api, b"POST /api/prefs HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\n"
                      b"Content-Length: %d\r\n\r\n" % declared)
    assert reply.startswith(b"HTTP/1.1 413")
    assert api("POST", "/api/prefs", raw=b"{not json")[0] == 400


def test_a_refused_request_closes_the_connection_so_its_body_is_not_a_second_request(api):
    smuggled = b"GET /api/health HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
    reply = _raw(api, b"POST /api/prefs HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: text/plain\r\n"
                      b"Content-Length: %d\r\n\r\n" % len(smuggled) + smuggled)
    assert reply.startswith(b"HTTP/1.1 415")
    assert reply.count(b"HTTP/1.1 ") == 1, "the unread body was parsed as another request"
    assert b"Connection: close" in reply


def test_config_cannot_change_what_runs_or_where_it_listens(api):
    for key in ("songrec_path", "host", "port"):
        status, body, _ = api("POST", "/api/config", {key: "/bin/sh"})
        assert status == 403 and key in body["error"]
    assert api("GET", "/api/config")[1]["songrec_path"] == ""


def test_config_allows_safe_keys_and_persists(api):
    status, body, _ = api("POST", "/api/config", {"contact": "me@example.org"})
    assert status == 200 and body["contact"] == "me@example.org"
    assert json.loads(config_path().read_text())["contact"] == "me@example.org"


def test_paste_then_song_roundtrip(api):
    status, pasted, _ = api("POST", "/api/paste", {"artist": "X", "title": "Y", "text": "Am   F\nhello there world\n"})
    assert status == 200 and pasted["chords"]["chord_names"] == ["Am", "F"] and "Am" in pasted["shapes"]
    status, song, _ = api("GET", "/api/song?artist=X&title=Y")
    assert song["chords"]["source"] == "local" and song["chords"]["kind"] == "chords"
    assert api("DELETE", "/api/local?artist=X&title=Y")[1] == {"removed": True}


def test_prefs_roundtrip(api):
    api("POST", "/api/prefs", {"artist": "X", "title": "Y", "capo": 4, "offset": -0.5})
    assert api("GET", "/api/prefs?artist=X&title=Y")[1] == {"capo": 4, "offset": -0.5}


def test_song_without_title_is_an_error_payload_not_a_crash(api):
    status, body, _ = api("GET", "/api/song?artist=X")
    assert status == 200 and body["error"] == "missing title"


def test_shapes_endpoint_caps_the_request(api):
    names = ",".join(["C"] * 500 + [f"D{i}" for i in range(100)])
    assert len(api("GET", f"/api/shapes?names={names}")[1]["shapes"]) <= 64


def test_keyed_locks_are_forgotten_after_use():
    locks = server.KeyedLocks()
    with locks.hold("a", "b"):
        assert len(locks._locks) == 1
    assert locks._locks == {}


# ---- review pass ----

def test_origin_null_is_refused_it_is_what_a_sandboxed_page_sends(api):
    assert api("GET", "/api/health", headers={"Origin": "null"})[0] == 403


def test_cross_site_fetch_metadata_is_refused(api):
    assert api("GET", "/api/health", headers={"Sec-Fetch-Site": "cross-site"})[0] == 403
    assert api("GET", "/api/health", headers={"Sec-Fetch-Site": "same-site"})[0] == 403
    assert api("GET", "/api/health", headers={"Sec-Fetch-Site": "none"})[0] == 200
    assert api("GET", "/api/health", headers={"Sec-Fetch-Site": "same-origin"})[0] == 200


def test_the_widget_itself_sends_neither_and_is_let_in(api):
    # Qt's XMLHttpRequest sends no Origin and no Sec-Fetch-*; this must keep working.
    assert api("GET", "/api/health")[0] == 200
    assert api("POST", "/api/prefs", {"artist": "a", "title": "b", "capo": 1})[0] == 200


class _Recorder:
    def __init__(self):
        self.lyrics_calls = []
        self.chord_calls = []


@pytest.fixture
def service(monkeypatch):
    config = Config({"chords_sources": ["local"], "ug_enabled": False, "fingerprint_enabled": False,
                     "min_request_interval": 0})
    svc = server.Service(config)
    rec = _Recorder()
    monkeypatch.setattr(server.identity, "resolve", lambda *a, **k: {
        "artist": "Real Artist", "title": "Real Title", "album": "Real Album", "source": "lrclib"})

    def lyrics(artist, title, album="", duration=0.0, lyrics_id=None, refresh=False):
        rec.lyrics_calls.append((artist, title))
        return {"source": "none", "lines": []}

    def chords(artist, title, duration=0.0, chord_url=None, album="", refresh=False):
        rec.chord_calls.append((artist, title, chord_url))
        return {"source": "none", "sections": [], "chord_names": []}

    monkeypatch.setattr(svc.lyrics, "lookup", lyrics)
    monkeypatch.setattr(svc.chords, "lookup", chords)
    svc.rec = rec
    return svc


UG = "https://tabs.ultimate-guitar.com/tab/a/b-tabs-1"


def test_a_pinned_tab_still_gets_lyrics_for_the_song_it_really_is(service):
    service.song("Some Channel", "Junk Title (Official Video)", chord_url=UG)
    assert service.rec.lyrics_calls == [("Real Artist", "Real Title")]
    assert service.rec.chord_calls[0][2] == UG


def test_a_pinned_lyrics_entry_still_searches_charts_by_the_real_song(service):
    service.song("Some Channel", "Junk Title", lyrics_id="42")
    assert service.rec.chord_calls[0][:2] == ("Real Artist", "Real Title")


def test_with_both_pinned_the_song_is_not_second_guessed(service):
    service.song("Some Channel", "Junk Title", lyrics_id="42", chord_url=UG)
    assert service.rec.lyrics_calls == [("Some Channel", "Junk Title")]


def test_a_chart_without_a_song_is_refused_not_saved_as_untitled(api):
    status, body, _ = api("POST", "/api/paste", {"artist": "X", "title": "", "text": "Am F\nhello"})
    assert status == 400 and "title" in body["error"]
    assert api("GET", "/api/local")[1]["items"] == []

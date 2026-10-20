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


def test_oversized_and_malformed_bodies(api):
    assert api("POST", "/api/prefs", raw=b"x" * (server.MAX_BODY + 1))[0] == 413
    assert api("POST", "/api/prefs", raw=b"{not json")[0] == 400


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

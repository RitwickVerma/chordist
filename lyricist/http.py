# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
#
# SPDX-License-Identifier: MIT

"""HTTP helpers shared by the providers.

Two jobs: send a believable browser User-Agent (Ultimate Guitar will not talk
to a bare urllib client), and keep per-host request pacing so a burst of lookups
cannot get us 502'd.
"""

from __future__ import annotations

import json
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any

MAX_BODY_BYTES = 8 * 1024 * 1024

BROWSER_UA = (
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"
)


class Throttle:
    """Keeps a minimum gap between requests to the same host.

    Each host has its own lock, so a slow Ultimate Guitar pacing delay never
    holds up an LRCLIB request that could go out right now.
    """

    def __init__(self, interval: float = 0.0) -> None:
        self.interval = interval
        self._guard = threading.Lock()
        self._locks: dict[str, threading.Lock] = {}
        self._last: dict[str, float] = {}

    def wait(self, url: str) -> None:
        if self.interval <= 0:
            return
        host = urllib.parse.urlsplit(url).netloc
        with self._guard:
            lock = self._locks.setdefault(host, threading.Lock())
        with lock:
            previous = self._last.get(host)
            if previous is not None:
                delay = self.interval - (time.monotonic() - previous)
                if delay > 0:
                    time.sleep(delay)
            self._last[host] = time.monotonic()


class _HttpOnlyRedirects(urllib.request.HTTPRedirectHandler):
    """Follow redirects only to http(s): urllib would also follow one to ftp://."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):  # type: ignore[no-untyped-def]
        if urllib.parse.urlsplit(newurl).scheme not in ("http", "https"):
            raise urllib.error.HTTPError(req.full_url, code, f"redirect to {newurl!r} refused", headers, fp)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


_OPENER = urllib.request.build_opener(_HttpOnlyRedirects)


class HttpError(RuntimeError):
    def __init__(self, status: int, url: str) -> None:
        super().__init__(f"HTTP {status} for {url}")
        self.status = status
        self.url = url


def fetch(
    url: str,
    *,
    throttle: Throttle | None = None,
    timeout: float = 20,
    headers: dict[str, str] | None = None,
    retries: int = 1,
    accept: str = "text/html,application/json,*/*",
) -> str:
    """GET ``url`` and return the body as text.

    Retries once on the transient failures that scraping runs into (502/503
    from a rate limiter, a dropped connection), with a short backoff.
    """
    if urllib.parse.urlsplit(url).scheme not in ("http", "https"):
        raise ValueError(f"refusing to fetch a non-http URL: {url!r}")
    request_headers = {
        "User-Agent": BROWSER_UA,
        "Accept": accept,
        "Accept-Language": "en-US,en;q=0.9",
    }
    if headers:
        request_headers.update(headers)

    last_error: Exception | None = None
    for attempt in range(retries + 1):
        if throttle is not None:
            throttle.wait(url)
        request = urllib.request.Request(url, headers=request_headers)
        try:
            with _OPENER.open(request, timeout=timeout) as response:
                charset = response.headers.get_content_charset() or "utf-8"
                return response.read(MAX_BODY_BYTES).decode(charset, "replace")
        except urllib.error.HTTPError as exc:
            last_error = HttpError(exc.code, url)
            if exc.code in (429, 500, 502, 503, 504) and attempt < retries:
                time.sleep(1.5 * (attempt + 1))
                continue
            raise last_error from exc
        except (urllib.error.URLError, OSError) as exc:
            last_error = exc
            if attempt < retries:
                time.sleep(1.0 * (attempt + 1))
                continue
            raise
    raise last_error if last_error else RuntimeError("unreachable")


def fetch_json(url: str, **kwargs: Any) -> Any:
    kwargs.setdefault("accept", "application/json,*/*")
    return json.loads(fetch(url, **kwargs))

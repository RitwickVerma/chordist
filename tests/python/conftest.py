# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
#
# SPDX-License-Identifier: MIT

"""Shared fixtures: every test gets its own XDG directories and no network."""

from __future__ import annotations

import html
import json
from typing import Any

import pytest


@pytest.fixture(autouse=True)
def xdg(tmp_path, monkeypatch):
    for name in ("CONFIG", "DATA", "CACHE"):
        directory = tmp_path / name.lower()
        directory.mkdir()
        monkeypatch.setenv(f"XDG_{name}_HOME", str(directory))
    return tmp_path


@pytest.fixture(autouse=True)
def no_network(monkeypatch):
    """Anything that reaches urllib without a test's say-so is a bug in the test."""

    def refuse(*args: Any, **kwargs: Any):
        raise AssertionError(f"unexpected network access: {args[:1]}")

    monkeypatch.setattr("urllib.request.urlopen", refuse)


def ug_page(tab_view: dict[str, Any], tab: dict[str, Any] | None = None) -> str:
    """A minimal Ultimate Guitar page: the js-store blob and nothing else."""
    store = {"store": {"page": {"data": {"tab": tab or {}, "tab_view": tab_view}}}}
    payload = html.escape(json.dumps(store), quote=True)
    return f'<html><div class="js-store" data-content="{payload}"></div></html>'


def ug_search_page(results: list[dict[str, Any]]) -> str:
    store = {"store": {"page": {"data": {"results": results}}}}
    payload = html.escape(json.dumps(store), quote=True)
    return f'<html><div class="js-store" data-content="{payload}"></div></html>'

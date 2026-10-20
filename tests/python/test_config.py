# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
#
# SPDX-License-Identifier: MIT

from __future__ import annotations

import json

from chordist.config import DEFAULTS, Config, config_path


def test_saving_writes_only_what_was_set_not_every_default():
    config_path().parent.mkdir(parents=True)
    config_path().write_text(json.dumps({"contact": "me@example.org"}))
    config = Config.load()
    config["log_level"] = "debug"
    config.save()
    on_disk = json.loads(config_path().read_text())
    assert on_disk == {"contact": "me@example.org", "log_level": "debug"}


def test_a_default_changed_later_still_reaches_a_user_who_never_set_it():
    config = Config.load()
    config["contact"] = "me@example.org"
    config.save()
    assert "request_timeout" not in json.loads(config_path().read_text())
    assert Config.load()["request_timeout"] == DEFAULTS["request_timeout"]


def test_unrelated_keys_in_the_file_survive_a_save():
    config_path().parent.mkdir(parents=True)
    config_path().write_text(json.dumps({"something_else": 1}))
    config = Config.load()
    config["contact"] = "x"
    config.save()
    assert json.loads(config_path().read_text()) == {"something_else": 1, "contact": "x"}


def test_a_broken_file_never_stops_startup():
    config_path().parent.mkdir(parents=True)
    config_path().write_text("{nope")
    assert Config.load()["port"] == DEFAULTS["port"]

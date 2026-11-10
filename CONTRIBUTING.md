# Contributing

Issues and merge requests are welcome on [GitLab](https://gitlab.com/ritwick7/chordist), where development happens. The
[GitHub repository](https://github.com/RitwickVerma/chordist) is a mirror: issues filed there are read too, but merge requests go to GitLab.
Security problems go through [SECURITY.md](SECURITY.md), not public issues.

The bar every change must clear: **run it, do not just read it.**

- `make test` and `make lint` pass.
- A change to the service comes with a pytest case, written to fail without the change. The suite never touches
  the network (a fixture blocks it); fake the page instead (see `tests/python/test_chords.py`).
- A change to timing, chord or tab logic comes with a node test (`tests/js`).
- A UI change comes with before/after renders from `make shots`, and a note of whether it was also loaded in
  `plasmawindowed` ([docs/testing.md](docs/testing.md)). Say what you verified and how.
- "Wrong chord / wrong song" reports are most useful with the output of
  `python3 -m chordist chords "<artist>" "<title>" --json` and the track's metadata as the player reports it.

Deliberate choices, not oversights, so please discuss before "fixing": no Python dependencies in the service,
the service on loopback with no CORS, chart scraping paced and cached, audio
identification off the critical path. [AGENTS.md](AGENTS.md) explains each.

By contributing you agree to license your work under the project's MIT licence. This project is developed with AI
assistance under human direction; disclose AI-generated contributions as such.

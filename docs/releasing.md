# Releasing

A release is a version bump, a changelog entry, a green tree and a tag. Nothing here publishes anything by itself.

1. **One version, five places.** `VERSION`, `pyproject.toml`, `chordist/__init__.py`, `applet/metadata.json` and
   `pkgver` in `packaging/PKGBUILD`. `tests/python/test_project.py` fails if they disagree.
2. **CHANGELOG.md.** Move what is under the top heading into a dated `## [X.Y.Z]` section, in the Keep a Changelog
   groups (Added, Changed, Fixed, Security). Say what a user would notice, not what files changed.
3. **Check everything.**

   ```sh
   make lint test check-build
   make shots demo          # if the UI changed: look at the renders, refresh docs/images
   ```

   Then load the widget in a real Plasma host (the recipe in [testing.md](testing.md)) and, for a change to the unit
   file, run the service under its real sandbox.
4. **Merge through a merge request.** Pipelines run the same `make` targets.
5. **Tag the merge commit** and build the artefacts from it:

   ```sh
   git tag -a vX.Y.Z -m "Chordist X.Y.Z"
   make dist pkgbuild      # dist/chordist-X.Y.Z.tar.gz, build/pkg/ with the PKGBUILD
   ```

   Push the tag, and attach the tarball to the GitLab release with the changelog section as its notes.

The version follows [Semantic Versioning](https://semver.org): a change to the HTTP API's shape, to the config keys
or to the on-disk layout (`~/.config|.local/share|.cache/chordist`) is a major version, and ships with a migration.

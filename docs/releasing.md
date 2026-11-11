# Releasing

A release is a version bump, a changelog entry, a green tree and a tag. The tag pipeline builds the tarball, uploads it
to the project's package registry, creates the GitLab release and generates the AUR files; you push the AUR repository.

**Project settings the release depends on** (set once, by a maintainer; nothing in the repository can set them):

- **Package registry enabled** (Settings → General → Visibility, project features, permissions). The release job uploads
  the tarball to the project's generic registry (`PUT /projects/:id/packages/generic/chordist/X.Y.Z/chordist-X.Y.Z.tar.gz`
  with the job's token) and the release links that file, so the AUR source URL outlives the pipeline's artifacts. With the
  registry off, the job fails at the upload and says so; nothing has been released yet.
- **`v*` protected tags** (Settings → Repository → Protected tags, allowed to create: Maintainers). The job token of a
  tag pipeline can publish releases, so only people who may push a release tag should be able to start one.
- If the job token is refused when creating the release, set a CI/CD variable `RELEASE_TOKEN` to a project access token
  with the `api` scope; `tools/gitlab-release.py` then uses it for the upload and the release instead.

1. **One version, five places.** `VERSION`, `pyproject.toml`, `chordist/__init__.py`, `applet/metadata.json` and
   `pkgver` in `packaging/PKGBUILD`. `tests/python/test_project.py` fails if they disagree.
2. **CHANGELOG.md.** Move what is under the top heading into a dated `## [X.Y.Z]` section, in the Keep a Changelog
   groups (Added, Changed, Fixed, Security). Say what a user would notice, not what files changed. That section is the
   release's notes; the release job fails without it.
3. **Check everything.**

   ```sh
   make lint test check-build
   make shots demo          # if the UI changed: look at the renders, refresh docs/images
   ```

   Then load the widget in a real Plasma host (the recipe in [testing.md](testing.md)) and, for a change to the unit
   file, run the service under its real sandbox.
4. **Merge through a merge request.** Pipelines run the same `make` targets, build and namcap the Arch package, and
   test Python 3.12 to 3.14, Debian 13 (including every widget component against its Kirigami 6.13) and Fedora. Tag
   only a green default branch.
5. **Tag the merge commit and push the tag.**

   ```sh
   git tag -a vX.Y.Z -m "Chordist X.Y.Z" && git push origin vX.Y.Z
   ```

   The `release` job checks the tag against `VERSION`, builds `dist/chordist-X.Y.Z.tar.gz` (`make dist`), uploads it to
   the package registry, creates the GitLab release (changelog section as notes, the registry file as the asset, under
   the stable name `chordist-X.Y.Z.tar.gz`), fetches `/-/releases/vX.Y.Z/downloads/chordist-X.Y.Z.tar.gz` to prove it
   serves that tarball, and keeps the AUR files as artifacts for a month. The tarball lives in the package registry, so
   deleting the job or the pipeline does not break `makepkg`; deleting the package would. If the job fails after the
   release exists, delete the release in the UI and retry the job. GitLab pushes the tag on to the GitHub mirror; give
   it a GitHub release with the same notes and tarball (`gh release create`).
6. **AUR.** `packaging/PKGBUILD` is the only PKGBUILD: the AUR copy is generated from it (`tools/aur-pkgbuild.py`
   swaps in the download URL and the tarball's checksum, and `makepkg --printsrcinfo` writes `.SRCINFO`). Take the
   files from the release job, into a clone of `ssh://aur@aur.archlinux.org/chordist.git`:

   ```sh
   curl -fL "https://gitlab.com/ritwick7/chordist/-/jobs/artifacts/vX.Y.Z/download?job=release" -o aur.zip
   unzip -oj aur.zip 'build/aur/*' -d chordist-aur && cd chordist-aur
   git add PKGBUILD chordist.install .SRCINFO && git commit -m "chordist X.Y.Z" && git push
   ```

   A packaging-only fix to a released version: fix `packaging/PKGBUILD` on `main`, then on Arch run
   `tools/aur-pkgbuild.py --tarball chordist-X.Y.Z.tar.gz --pkgrel 2 --out build/aur` with the released tarball
   (`make aur` does the same for the current tree, pkgrel 1).

The version follows [Semantic Versioning](https://semver.org): a change to the HTTP API's shape, to the config keys
or to the on-disk layout (`~/.config|.local/share|.cache/chordist`) is a major version, and ships with a migration.

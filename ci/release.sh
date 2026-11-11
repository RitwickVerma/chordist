#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
#
# SPDX-License-Identifier: MIT
# The `release` job (tag pipelines only): the tarball from the tagged tree, the AUR files for it, the GitLab release.
# Needs CI_COMMIT_TAG, CI_JOB_TOKEN, CI_API_V4_URL, CI_PROJECT_ID, CI_PROJECT_URL (GitLab sets them), and the project's
# generic package registry enabled: the tarball is uploaded there (docs/releasing.md).
set -euo pipefail
# shellcheck source=ci/arch-lib.sh
. ci/arch-lib.sh

version=$(cat VERSION)
[ "${CI_COMMIT_TAG:-}" = "v$version" ] || { echo "tag '${CI_COMMIT_TAG:-}' is not v$version (VERSION)" >&2; exit 1; }
tarball=dist/chordist-$version.tar.gz

# shellcheck disable=SC2119  # no extra packages
install_packages
setup_builder
# `make aur` runs `make dist` (git archive of the tag) and then tools/aur-pkgbuild.py on that tarball.
as_builder make -C "$SRC" aur
mkdir -p dist build/aur
cp "$SRC/$tarball" dist/
cp "$SRC"/build/aur/PKGBUILD "$SRC"/build/aur/chordist.install "$SRC"/build/aur/.SRCINFO build/aur/
sha256sum "$tarball"
python3 tools/gitlab-release.py publish "$tarball"

# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: MIT
# CI image for Chordist's GitLab jobs: the packages every job needs, installed once.
#
# Built on the runner host (CT115) by ci-image-build.service from a fresh clone of the default
# branch, tagged localhost/chordist-ci:latest (rebuilt weekly, and hourly if missing). `localhost/` is
# deliberate: if the image is ever absent Docker tries localhost:443 and the job fails, instead of
# pulling a stranger's image of the same name from Docker Hub. The label keeps the host's
# `docker image prune -a` away from it. Stale (ci/packages.txt changed since the build): the
# before_script in .gitlab-ci.yml reinstalls. Absent: start the pipeline with
# CHORDIST_CI_IMAGE=archlinux:latest and the before_script installs everything.
FROM archlinux:latest
LABEL ci.keep="true"
COPY ci/packages.txt /etc/ci-packages
RUN pacman -Syu --noconfirm --needed --quiet $(cat /etc/ci-packages) \
 && pacman -Scc --noconfirm >/dev/null \
 && git config --system --add safe.directory '*'

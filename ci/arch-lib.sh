# shellcheck shell=bash
# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
#
# SPDX-License-Identifier: MIT
# Shared by ci/package-arch.sh and ci/release.sh (sourced, in an Arch container, as root, from the repo root).
# makepkg refuses to run as root, so the builds happen as an unprivileged `builder` in a copy of the checkout.

BUILDER_HOME=/home/builder
SRC=$BUILDER_HOME/src

as_builder() { runuser -u builder -- env HOME="$BUILDER_HOME" "$@"; }

# Packages: what the CI image has, what makepkg and namcap need, and extra names from the arguments.
# A full -Syu, not -Sy: the image's package database is not synced, and a partial upgrade breaks things.
install_packages() {
    pacman -Syu --noconfirm --needed --quiet git make python diffutils fakeroot binutils debugedit namcap kpackage "$@"
}

# The package's own `depends`, read from the PKGBUILD that will be built.
pkgbuild_depends() {
    bash -c '. packaging/PKGBUILD && echo "${depends[@]}"'
}

setup_builder() {
    id builder >/dev/null 2>&1 || useradd --create-home builder
    rm -rf "$SRC"
    cp -a "$PWD" "$SRC"
    chown -R builder: "$SRC"
    as_builder git config --global --add safe.directory '*'
}

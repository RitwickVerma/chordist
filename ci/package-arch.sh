#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
#
# SPDX-License-Identifier: MIT
# The `package-arch` job: build the Arch package from this tree as a normal user, lint it, install it, run it,
# then prove the AUR files generated for the same tarball build into the same package.
# Run it from the repo root in an Arch container (as root):  docker run --rm -v "$PWD":/src -w /src archlinux ci/package-arch.sh
set -euo pipefail
# shellcheck source=ci/arch-lib.sh
. ci/arch-lib.sh

version=$(cat VERSION)
# shellcheck disable=SC2046  # the depends are a word list
install_packages $(pkgbuild_depends)
setup_builder

echo "::: makepkg, from the tree (make pkgbuild)"
as_builder make -C "$SRC" pkgbuild
pkg=$SRC/build/pkg
(cd "$pkg" && as_builder makepkg --force --noconfirm)

# namcap does not fail on errors by itself. E: fails the job; W: is printed (the one expected is `bash`
# referenced through `#!/usr/bin/env bash`).
namcap_check() {
    local log=$1
    shift
    as_builder namcap "$@" | tee "$log"
    if grep -E ' E: ' "$log"; then
        echo "namcap reported errors (E:) in $log" >&2
        return 1
    fi
}
echo "::: namcap"
(cd "$pkg" && namcap_check "$SRC/namcap-pkg.log" PKGBUILD "chordist-$version-1-any.pkg.tar.zst")

echo "::: install and smoke-test"
pacman -U --noconfirm "$pkg/chordist-$version-1-any.pkg.tar.zst"
chordist --help >/dev/null
chordistd --help >/dev/null
test -L /usr/bin/chordist
plasmoid=/usr/share/plasma/plasmoids/com.ritwick.chordist
for f in metadata.json contents/ui/main.qml contents/ui/SongModel.qml contents/js/theory.js \
         contents/config/main.xml contents/config/config.qml; do
    test -f "$plasmoid/$f" || { echo "missing from the package: $plasmoid/$f" >&2; exit 1; }
done
test -f /usr/lib/chordist/chordist/data/guitar-chords.json
test -f /usr/share/icons/hicolor/scalable/apps/chordist.svg
test -f /usr/share/licenses/chordist/LICENSE
grep -qx 'ExecStart=/usr/bin/chordistd serve' /usr/lib/systemd/user/chordistd.service
# Plasma itself accepts it as an applet package: it is found in the system plasmoid directory.
kpackagetool6 --type Plasma/Applet --global --list | grep -q com.ritwick.chordist
[ "$(chordist --version)" = "chordist $version" ]

echo "::: the AUR files, generated for this tarball"
as_builder make -C "$SRC" aur
aur=$SRC/build/aur
for f in PKGBUILD chordist.install .SRCINFO; do test -s "$aur/$f"; done
sha=$(sha256sum "$SRC/dist/chordist-$version.tar.gz" | cut -d' ' -f1)
grep -qxF "	sha256sums = $sha" "$aur/.SRCINFO"
grep -qxF "	source = chordist-$version.tar.gz::https://gitlab.com/ritwick7/chordist/-/releases/v$version/downloads/chordist-$version.tar.gz" "$aur/.SRCINFO"
grep -qxF "	install = chordist.install" "$aur/.SRCINFO"
# .SRCINFO must be what makepkg prints for that PKGBUILD, not a stale copy.
(cd "$aur" && as_builder makepkg --printsrcinfo | diff - .SRCINFO)
# Build the AUR PKGBUILD for real: the tarball next to it satisfies `source` (so nothing is downloaded) and
# makepkg verifies the checksum we wrote. Then the two packages must contain the same files.
cp "$SRC/dist/chordist-$version.tar.gz" "$aur/"
(cd "$aur" && as_builder makepkg --force --noconfirm && namcap_check "$SRC/namcap-aur.log" PKGBUILD "chordist-$version-1-any.pkg.tar.zst")
diff <(pacman -Qlp "$pkg/chordist-$version-1-any.pkg.tar.zst" | sed 's/^chordist //' | sort) \
     <(pacman -Qlp "$aur/chordist-$version-1-any.pkg.tar.zst" | sed 's/^chordist //' | sort)
diff <(sed -n '/^package() {/,$p' packaging/PKGBUILD) <(sed -n '/^package() {/,$p' "$aur/PKGBUILD")
diff <(grep '^depends=' packaging/PKGBUILD) <(grep '^depends=' "$aur/PKGBUILD")

# Hand back what the pipeline publishes as artifacts.
mkdir -p build/aur build/pkg
cp "$aur/PKGBUILD" "$aur/chordist.install" "$aur/.SRCINFO" build/aur/
cp "$pkg/chordist-$version-1-any.pkg.tar.zst" build/pkg/
cp "$SRC"/namcap-*.log build/
echo "package-arch: ok"

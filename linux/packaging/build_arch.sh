#!/usr/bin/env bash
# Packages the release tarball as an Arch Linux package (.pkg.tar.zst) with
# makepkg in an archlinux:base-devel container, from linux/packaging/arch/PKGBUILD.
# Usage: linux/packaging/build_arch.sh <version> <Riflay-linux-x64.tar.gz> <output.pkg.tar.zst> [aur dir]
# Every source is given to makepkg locally (no download), under the names the
# PKGBUILD's URLs would give them, so the checksums written into it also match
# the release assets: the filled PKGBUILD and .SRCINFO go to [aur dir] when given.
# Needs: docker.
set -euo pipefail
cd "$(dirname "$0")/../.."
version=$1 tarball=$2 out=$(realpath -m "$3") aur=${4:-}
work=build/arch
rm -rf "$work"
mkdir -p "$work"

cp "$tarball" "$work/Riflay-linux-x64-$version.tar.gz"
cp linux/packaging/riflay.desktop "$work/riflay-$version.desktop"
cp linux/runner/riflay.png "$work/riflay-$version.png"
cp linux/runner/riflay.svg "$work/riflay-$version.svg"
sums=$(cd "$work" && sha256sum "Riflay-linux-x64-$version.tar.gz" "riflay-$version.desktop" \
  "riflay-$version.png" "riflay-$version.svg" | awk '{printf "%s\x27%s\x27", (NR > 1 ? "\n            " : ""), $1}')
# pkgver, and the sha256sums array (from its line to the closing parenthesis) replaced.
awk -v ver="$version" -v sums="$sums" '
  /^pkgver=/ { print "pkgver=" ver; next }
  /^sha256sums=\(/ { print "sha256sums=(" sums ")"; skip = !/\)$/; next }
  skip { if (/\)$/) skip = 0; next }
  { print }
' linux/packaging/arch/PKGBUILD > "$work/PKGBUILD"

# makepkg refuses to run as root: build as a user with this machine's uid, so the
# results stay ours.
docker run --rm -v "$PWD/$work:/build" -w /build -e HOST_UID="$(id -u)" archlinux:base-devel bash -euc '
  useradd -m -u "$HOST_UID" builder
  su builder -c "makepkg --nodeps --noconfirm --force && makepkg --printsrcinfo > .SRCINFO"
'

pkg=$(ls "$work"/riflay-bin-"$version"-*-x86_64.pkg.tar.zst)
cp "$pkg" "$out"
if [ -n "$aur" ]; then
  mkdir -p "$aur"
  cp "$work/PKGBUILD" "$work/.SRCINFO" "$aur/"
fi

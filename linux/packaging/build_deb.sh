#!/usr/bin/env bash
# Packages the release bundle as a .deb (Debian, Ubuntu, Mint...).
# Usage: linux/packaging/build_deb.sh <version> <output.deb>
# Run after `flutter build linux --release`.
set -euo pipefail
cd "$(dirname "$0")/../.."
version=$1 out=$2
bundle=build/linux/x64/release/bundle
pkg=$(mktemp -d)
trap 'rm -rf "$pkg"' EXIT

mkdir -p "$pkg/DEBIAN" "$pkg/opt/riflay" "$pkg/usr/bin" \
  "$pkg/usr/share/applications" "$pkg/usr/share/icons/hicolor/256x256/apps" \
  "$pkg/usr/share/icons/hicolor/scalable/apps"
cp -r "$bundle"/. "$pkg/opt/riflay/"
ln -s /opt/riflay/riflay "$pkg/usr/bin/riflay"
cp linux/packaging/riflay.desktop "$pkg/usr/share/applications/"
cp linux/runner/riflay.png "$pkg/usr/share/icons/hicolor/256x256/apps/riflay.png"
cp linux/runner/riflay.svg "$pkg/usr/share/icons/hicolor/scalable/apps/riflay.svg"

# Replaces / Conflicts: OpenMusic is Riflay's old name, and installing Riflay takes its place.
cat > "$pkg/DEBIAN/control" <<CONTROL
Package: riflay
Version: $version
Section: sound
Priority: optional
Architecture: amd64
Maintainer: Araryarch67 <noreply@github.com>
Depends: libgtk-3-0t64 | libgtk-3-0, libmpv2 | libmpv1
Recommends: libwebkit2gtk-4.1-0, ffmpeg
Replaces: openmusic
Conflicts: openmusic
Installed-Size: $(du -sk "$pkg/opt" | cut -f1)
Homepage: https://github.com/Araryarch67/Riflay
Description: Music player for your own music and YouTube Music
 Free, open-source music player with hi-fi audio: bit-perfect output,
 equalizer, ReplayGain, gapless playback and a signal path view.
CONTROL

dpkg-deb --build --root-owner-group "$pkg" "$out"

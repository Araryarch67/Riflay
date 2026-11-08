#!/usr/bin/env bash
# Packages the release bundle as a .deb (Debian, Ubuntu, Mint...) and an .rpm
# (Fedora, openSUSE...) with nfpm (linux/packaging/nfpm.yaml).
# Usage: linux/packaging/build_packages.sh <version> <output dir>
# Run after `flutter build linux --release`. nfpm is downloaded (pinned, checked)
# when it isn't on PATH.
set -euo pipefail
cd "$(dirname "$0")/../.."
export VERSION=$1
out=$2
nfpm_version=2.48.0
nfpm_sha256=6d7f9a28b2f397934403950fcbba83f598b08d02edbe79a0815b3b4897341750

[ -d build/linux/x64/release/bundle ] || { echo "No release bundle: run flutter build linux --release" >&2; exit 1; }
nfpm=$(command -v nfpm || true)
if [ -z "$nfpm" ]; then
  tools=build/packaging-tools
  nfpm=$tools/nfpm
  if [ ! -x "$nfpm" ]; then
    mkdir -p "$tools"
    python3 tool/download_release_asset.py \
      "https://github.com/goreleaser/nfpm/releases/download/v$nfpm_version/nfpm_${nfpm_version}_Linux_x86_64.tar.gz" \
      "$tools/nfpm.tar.gz" --sha256 "$nfpm_sha256"
    echo "$nfpm_sha256  $tools/nfpm.tar.gz" | sha256sum -c --quiet
    tar -xzf "$tools/nfpm.tar.gz" -C "$tools" nfpm
  fi
fi

mkdir -p "$out"
"$nfpm" package --config linux/packaging/nfpm.yaml --packager deb --target "$out/Riflay-linux-amd64.deb"
"$nfpm" package --config linux/packaging/nfpm.yaml --packager rpm --target "$out/Riflay-linux-x86_64.rpm"

#!/usr/bin/env bash
# Puts a release's Scoop manifest in Araryarch67/scoop-riflay (bucket/) and its Homebrew cask in
# Araryarch67/homebrew-riflay (Casks/), with your own Git access: run it on your computer once the release's
# package-manifests job has attached riflay.json and riflay.rb to it.
#
#   packaging/publish_taps.sh 1.5.0
#
# The release workflow doesn't push them itself: that needed a token kept as a repository secret, and an expired
# one failed the release.
set -euo pipefail

version="${1:?usage: packaging/publish_taps.sh <version, e.g. 1.5.0>}"
version="${version#v}"
release="https://github.com/Araryarch67/Riflay/releases/download/v${version}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

for file in riflay.json riflay.rb; do
  if ! curl -fsSL "$release/$file" -o "$work/$file"; then
    echo "v${version} has no $file yet: wait for its package-manifests job." >&2
    exit 1
  fi
done

publish() { # <repository> <folder> <file>
  local repo="$work/$1"
  git clone -q --depth 1 "https://github.com/Araryarch67/$1.git" "$repo"
  mkdir -p "$repo/$2"
  cp "$work/$3" "$repo/$2/"
  git -C "$repo" add -A
  if git -C "$repo" diff --cached --quiet; then
    echo "$1 already has Riflay $version"
    return
  fi
  git -C "$repo" commit -qm "riflay $version"
  git -C "$repo" push -q origin HEAD
  echo "$1: Riflay $version"
}

publish scoop-riflay bucket riflay.json
publish homebrew-riflay Casks riflay.rb

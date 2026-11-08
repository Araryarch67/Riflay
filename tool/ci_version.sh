#!/usr/bin/env bash
# Prints `flutter build` version flags for CI: the tag's version (v1.2.3 ->
# 1.2.3) and a build number from the workflow run. Prints nothing when the
# build isn't for a version tag, so pubspec.yaml's version is used.
#
# The build number is also Android's versionCode, the same for every APK
# (see the Android job). It starts at 10000: up to 1.6.0 the per-ABI APKs got
# 1000-4000 added to the run number, and a phone that installed one of those
# must see every later APK as newer, or it refuses to update.
set -euo pipefail
release_tag=${RIFLAY_RELEASE_TAG:-}
if [[ -z "$release_tag" && "${GITHUB_REF:-}" == refs/tags/v* ]]; then
  release_tag=$GITHUB_REF_NAME
fi
if [[ -n "$release_tag" ]]; then
  [[ "$release_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid release tag' >&2; exit 1; }
  version=$(sed -nE 's/^version: ([^+ ]+).*/\1/p' pubspec.yaml)
  [[ "${release_tag#v}" == "$version" ]] || { echo 'Release tag differs from pubspec.yaml' >&2; exit 1; }
  echo "--build-name=${release_tag#v} --build-number=$((10000 + GITHUB_RUN_NUMBER))"
fi

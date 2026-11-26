#!/usr/bin/env bash
# Prints `flutter build` version flags for CI: the tag's version (v1.2.3 ->
# 1.2.3, or a release candidate: v1.3.0-rc1 -> 1.3.0-rc1) and a build number
# from the workflow run. Nightly builds use the version in pubspec.yaml.
# Other builds use Flutter's default version flags.
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
  [[ "$release_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-rc[0-9]+)?$ ]] || { echo 'Invalid release tag' >&2; exit 1; }
  version=$(sed -nE 's/^version: ([^+ ]+).*/\1/p' pubspec.yaml)
  [[ "${release_tag#v}" == "$version" ]] || { echo 'Release tag differs from pubspec.yaml' >&2; exit 1; }
  # The build after the version in pubspec.yaml (1.9.0+126): the app compares it with the release's title.
  build=$(grep -m1 '^version:' pubspec.yaml | cut -s -d+ -f2 | tr -d '[:space:]')
  echo "--build-name=${release_tag#v} --build-number=$((10000 + GITHUB_RUN_NUMBER)) --dart-define=RIFLAY_BUILD=${build:-0}"
elif [[ "${RIFLAY_NIGHTLY:-}" == true ]]; then
  # Nightly and stable APKs share the same package ID and signing key.
  version=$(sed -nE 's/^version: ([^+ ]+).*/\1/p' pubspec.yaml)
  echo "--build-name=$version --build-number=$((10000 + GITHUB_RUN_NUMBER)) --dart-define=RIFLAY_NIGHTLY=true"
fi

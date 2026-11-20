#!/usr/bin/env bash
# Promotes a complete main-branch build to the rolling GitHub prerelease.
set -euo pipefail

tag=nightly
ref="repos/$GH_REPO/git/refs/tags/$tag"
current=
if draft=$(gh release view "$tag" --json isDraft --jq '.isDraft' 2>/dev/null); then
  if [[ "$draft" == false ]]; then
    current=$(gh api "$ref" --jq '.object.sha')
    if [[ "$current" == "$GITHUB_SHA" ]]; then exit 0; fi
    status=$(gh api "repos/$GH_REPO/compare/$current...$GITHUB_SHA" --jq '.status')
    if [[ "$status" != ahead ]]; then
      echo "Nightly already points to a different or newer build ($current)."
      exit 0
    fi
  fi
else
  draft=missing
fi

mkdir dist
for platform in android windows linux macos ios; do
  cp -- "artifacts/$platform/"* dist/
done
(cd dist && sha256sum -- *) > SHA256SUMS
printf 'Rolling build from `main` at [`%s`](https://github.com/%s/commit/%s).\n\nNew builds replace the downloads on this page. Nightly uses the same app identity and settings as the stable app.\n' \
  "$GITHUB_SHA" "$GH_REPO" "$GITHUB_SHA" > nightly.md

if [[ "$draft" == missing ]]; then
  gh release create "$tag" --target "$GITHUB_SHA" --draft --prerelease --latest=false \
    --title 'Riflay Nightly' --notes-file nightly.md
fi

gh release upload "$tag" dist/* --clobber
gh release upload "$tag" SHA256SUMS --clobber
if [[ "$draft" == false ]]; then
  gh release edit "$tag" --title 'Riflay Nightly' --notes-file nightly.md --prerelease --latest=false
  # Move the source tag only after all assets and their checksums are in place.
  gh api --method PATCH "$ref" -f sha="$GITHUB_SHA" -F force=true --silent
else
  gh release edit "$tag" --target "$GITHUB_SHA" --title 'Riflay Nightly' --notes-file nightly.md \
    --draft=false --prerelease --latest=false
fi

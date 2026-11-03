#!/usr/bin/env bash
# Writes the release's checksums and the package manager manifests for it.
# Usage: packaging/update_manifests.sh <version> <dist dir> <output dir>
#   <dist dir>/SHA256SUMS      every file in <dist dir> (Scoop's autoupdate reads it too)
#   <output dir>/riflay.json   Scoop manifest (from packaging/scoop/riflay.json)
#   <output dir>/riflay.rb     Homebrew cask (from packaging/homebrew/Casks/riflay.rb),
#                              only when <dist dir> has Riflay-macos.dmg
set -euo pipefail
cd "$(dirname "$0")/.."
version=$1 dist=$2 out=$3
mkdir -p "$out"

rm -f "$dist/SHA256SUMS"
sums=$(cd "$dist" && sha256sum -- *)
echo "$sums" > "$dist/SHA256SUMS"
sum_of() { awk -v f="$1" '$2 == f || $2 == "*" f { print $1 }' <<< "$sums"; }

zip_sha=$(sum_of Riflay-windows-x64.zip)
[ -n "$zip_sha" ] || { echo "Riflay-windows-x64.zip is missing from $dist" >&2; exit 1; }
VERSION=$version SHA=$zip_sha python3 - packaging/scoop/riflay.json "$out/riflay.json" <<'PY'
import json, os, sys
manifest = json.load(open(sys.argv[1], encoding='utf-8'))
version = os.environ['VERSION']
manifest['version'] = version
x64 = manifest['architecture']['64bit']
x64['url'] = f'https://github.com/Araryarch67/Riflay/releases/download/v{version}/Riflay-windows-x64.zip'
x64['hash'] = os.environ['SHA']
with open(sys.argv[2], 'w', encoding='utf-8', newline='\n') as f:
    json.dump(manifest, f, indent=4, ensure_ascii=False)
    f.write('\n')
PY

dmg_sha=$(sum_of Riflay-macos.dmg)
if [ -n "$dmg_sha" ]; then
  sed -e "s/^  version \".*\"/  version \"$version\"/" -e "s/^  sha256 .*/  sha256 \"$dmg_sha\"/" \
    packaging/homebrew/Casks/riflay.rb > "$out/riflay.rb"
else
  echo "No Riflay-macos.dmg in this release: the Homebrew cask is left as it is." >&2
fi

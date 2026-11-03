#!/usr/bin/env bash
# Writes the release's checksums and the package manager manifests for it.
# Usage: packaging/update_manifests.sh <version> <dist dir> <output dir>
#   <dist dir>/SHA256SUMS      every file in <dist dir> (Scoop's autoupdate reads it too)
#   <output dir>/riflay.json   Scoop manifest (from packaging/scoop/riflay.json)
#   <output dir>/riflay.rb     Homebrew cask, macOS and Linux (from packaging/homebrew/Casks/riflay.rb)
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

# The cask's sha256 lines end with the file they check; one missing from the release is left unchecked.
appimage_sha=$(sum_of Riflay-linux-x86_64.AppImage)
[ -n "$appimage_sha" ] || { echo "Riflay-linux-x86_64.AppImage is missing from $dist" >&2; exit 1; }
dmg_sha=$(sum_of Riflay-macos.dmg)
dmg_check=\"$dmg_sha\"
if [ -z "$dmg_sha" ]; then
  dmg_check=:no_check
  echo "No Riflay-macos.dmg in this release: the cask's macOS sha256 stays unchecked." >&2
fi
sed -e "s/^  version \".*\"/  version \"$version\"/" \
  -e "s/^\( *\)sha256 .* # Riflay-macos\.dmg$/\1sha256 $dmg_check # Riflay-macos.dmg/" \
  -e "s/^\( *\)sha256 .* # Riflay-linux-x86_64\.AppImage$/\1sha256 \"$appimage_sha\" # Riflay-linux-x86_64.AppImage/" \
  packaging/homebrew/Casks/riflay.rb > "$out/riflay.rb"

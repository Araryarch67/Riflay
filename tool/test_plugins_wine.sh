#!/usr/bin/env bash
# End-to-end test of audio plugins on Windows, run on Linux under Wine: Carla
# for Windows (its official zip), the bridge DLL (linux/carla_bridge), and
# Riflay's libmpv-2.dll play a tone through the same filter the app builds
# (AudioEngine: @plugins:lavfi=graph=...ladspa...) into a WAV file, with and
# without a project. The project (test/fixtures/half_gain_internal.carxp) is
# Carla's own gain at 0.5, so the level must fall by about 6 dB.
#
#   CARLA_DIR=<unzipped Carla-x-win64/Carla> tool/test_plugins_wine.sh
#
# Without CARLA_DIR the pinned official zip is downloaded to ~/.cache/riflay-build.
# Needs x86_64-w64-mingw32-g++, wine, ffmpeg, curl, unzip, the libmpv build
# (tool/build_libmpv_windows.sh). Run it on a display that is not your desktop
# (a headless Weston with --xwayland), with WINEPREFIX set to a throwaway one.
set -euo pipefail
cd "$(dirname "$0")/.."
build=${RIFLAY_BUILD_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/riflay-build}/libmpv
dll=windows/libmpv/libmpv-2.dll
if [[ ! -f $dll || ! -f $build/build/mpv/libmpv.dll.a ]]; then
  echo "Build libmpv first: tool/build_libmpv_windows.sh" >&2
  exit 1
fi
: "${WINEPREFIX:?set WINEPREFIX to a throwaway prefix}"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

carla=${CARLA_DIR:-}
if [[ -z $carla ]]; then
  zip=${RIFLAY_BUILD_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/riflay-build}/Carla-2.5.10-win64.zip
  sum=56264cd860b3e6e7b29221fb1e46d7d8a288fb001500f830bcd739ec7b115650
  [[ -f $zip ]] || curl -fsSL -o "$zip" https://github.com/falkTX/Carla/releases/download/v2.5.10/Carla-2.5.10-win64.zip
  echo "$sum  $zip" | sha256sum -c --quiet
  unzip -q "$zip" -d "$work/carla-zip"
  carla=$work/carla-zip/Carla-2.5.10-win64/Carla
fi
[[ -f $carla/libcarla_native-plugin.dll ]]

cxx=(x86_64-w64-mingw32-g++ -std=c++17 -O2 -Wall -Werror -static)
"${cxx[@]}" -shared linux/carla_bridge/riflay_carla.cc -o "$work/riflay_carla.dll"
mkdir -p "$work/include/mpv"
cp "$build/src/mpv/libmpv/client.h" "$work/include/mpv/"
"${cxx[@]}" -I"$work/include" tool/wine/mpv_plugins_test.cpp "$build/build/mpv/libmpv.dll.a" -o "$work/mpv_plugins_test.exe"
ffmpeg -v error -f lavfi -i "aevalsrc=0.5*sin(2*PI*997*t)|0.5*sin(2*PI*997*t):s=44100:d=2" -c:a pcm_s16le "$work/tone.wav"

export WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml="
wineboot -i >/dev/null 2>&1
# Wine links the user's real folders into the prefix; the test must not reach them.
for d in Music Documents Downloads Desktop Pictures Videos; do
  link=$WINEPREFIX/drive_c/users/$USER/$d
  if [[ -L $link ]]; then
    unlink "$link"
    mkdir "$link"
  fi
done
c=$WINEPREFIX/drive_c
rm -rf "$c/riflay" "$c/Carla"
mkdir -p "$c/riflay"
cp -r "$carla" "$c/Carla"
cp "$work/riflay_carla.dll" "$work/mpv_plugins_test.exe" "$work/tone.wav" "$dll" "$c/riflay/"
# The app's folder, as AudioEngine and the bridge agree on it (%APPDATA%\dev.riflay\riflay).
appdata=$(wine cmd /c 'echo %APPDATA%' 2>/dev/null | tr -d '\r')
app=$(winepath -u "$appdata")/dev.riflay/riflay
rm -rf "$app" && mkdir -p "$app"

# The filter as the app writes it: graphPath(bridge) inside mpv's lavfi graph=%length%.
bridge='C:/riflay/riflay_carla.dll'
escaped=${bridge//:/\\\\:} # "C:" -> "C\\:" (once for the option, once more for the graph)
graph="ladspa=file=$escaped:plugin=riflay_carla"
af="@plugins:lavfi=graph=%${#graph}%$graph"

level() { # wav -> mean dB
  ffmpeg -hide_banner -i "$1" -af volumedetect -f null - 2>&1 | sed -n 's/.*mean_volume: \(-\?[0-9.]*\) dB.*/\1/p'
}
play() { # out-name project-or-empty
  rm -f "$c/riflay/$1.wav"
  if [[ -n $2 ]]; then cp "$2" "$app/plugins.carxp"; else rm -f "$app/plugins.carxp"; fi
  (cd "$c/riflay" && wine mpv_plugins_test.exe 'C:\riflay\tone.wav' "C:\\riflay\\$1.wav" "$af") || true
  [[ -s $c/riflay/$1.wav ]]
}

status=0
check() { # name ok
  if [[ $2 == ok ]]; then echo "ok   $1"; else echo "FAIL $1"; status=1; fi
}

play plain ''
plain=$(level "$c/riflay/plain.wav")
echo "no project: $plain dB (the tone itself: $(level "$work/tone.wav") dB)"
check "audio passes through without a project" \
  "$(awk -v a="$plain" -v b="$(level "$work/tone.wav")" 'BEGIN { d = a - b; print (d < 0.1 && d > -0.1) ? "ok" : "no" }')"

# Where Carla is, found by searching: the app writes carla_dir.txt in its folder.
echo 'C:\Carla' >"$app/carla_dir.txt"
play halved test/fixtures/half_gain_internal.carxp
halved=$(level "$c/riflay/halved.wav")
delta=$(awk -v a="$halved" -v b="$plain" 'BEGIN { printf "%.2f", a - b }')
echo "gain 0.5 project: $halved dB (change $delta dB)"
check "the project's gain halves the level (-6 dB)" "$(awk -v d="$delta" 'BEGIN { print (d < -5.8 && d > -6.2) ? "ok" : "no" }')"
exit $status

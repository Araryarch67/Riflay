#!/usr/bin/env bash
# Measures the real app's CPU use (tool/cpu_app.dart) in profile mode, in a
# headless Weston on the GPU with throwaway data: idle, a song playing and
# paused, on Home and Now Playing. Songs are silent FLAC files with long titles
# (so the card and player marquees are in play), played through the system's
# audio output as usual. Prints "CPU ..." lines.
# Usage: tool/cpu.sh [runs]   (default 1)
#        RIFLAY_CPU_WIDTH=1280 RIFLAY_CPU_HEIGHT=800 tool/cpu.sh   (another screen size)
#        RIFLAY_CPU_LAYOUT='{"visualizer": false}' tool/cpu.sh   (start with other Layout settings)
#        RIFLAY_CPU_ENV='NAME=value' tool/cpu.sh   (an environment variable for the app, e.g. a probe)
#        RIFLAY_CPU_SOURCE='anoisesrc=r=44100:c=pink:a=0.3' RIFLAY_CPU_ENV='RIFLAY_MPV_OPTIONS=ao=null' tool/cpu.sh
#            (songs with sound, so the visualizer moves; ao=null keeps them off the speakers, and PipeWire's ~1.2%)
set -euo pipefail
cd "$(dirname "$0")/.."
runs=${1:-1}

scratch=$(mktemp -d)
trap 'kill $weston 2>/dev/null || true; rm -rf "$scratch"' EXIT
mkdir -p "$scratch/songs"
for i in 1 2 3; do
  ffmpeg -loglevel error -y -f lavfi -i "${RIFLAY_CPU_SOURCE:-anullsrc=r=44100:cl=stereo}" -t 300 \
    -metadata "title=A rather long song title that never fits on one card, part $i" \
    -metadata artist="Some Artist With A Long Name" -metadata album="An Album $i" "$scratch/songs/song$i.flac"
done

flutter build linux --profile --dart-define=RIFLAY_NO_UPDATE_CHECK=true -t tool/cpu_app.dart >/dev/null
weston --backend=headless --renderer=gl --socket=om-cpu --width=${RIFLAY_CPU_WIDTH:-2560} --height=${RIFLAY_CPU_HEIGHT:-1600} >/dev/null 2>&1 &
weston=$!
sleep 1

for i in $(seq 1 "$runs"); do
  [ "$runs" -gt 1 ] && echo "── run $i"
  rm -rf "$scratch/data"
  mkdir -p "$scratch/data/dev.riflay.riflay"
  # The library as SharedPreferences held it before library.json; the app moves it over on start.
  python3 - "$scratch" <<'EOF'
import json, os, sys, pathlib
scratch = sys.argv[1]
songs = sorted(pathlib.Path(scratch, 'songs').glob('*.flac'))
tracks = [{'id': s.as_uri(), 'uri': s.as_uri(), 'title': s.stem, 'artist': '', 'album': '', 'tagged': False} for s in songs]
tracks += [{'id': f'file:///nonexistent/{i}.flac', 'uri': f'file:///nonexistent/{i}.flac',
            'title': f'Song {i} with a title long enough to scroll on a card', 'artist': f'Artist {i % 100}',
            'album': f'Album {i // 10}', 'durationMs': 180000, 'tagged': True} for i in range(2000)]
prefs = {'flutter.library.v1': json.dumps(tracks), 'flutter.deviceSetup.v1': True}  # no setup page in the way
# RIFLAY_CPU_LAYOUT: Layout preferences to start with, as JSON (e.g. '{"visualizer": false}').
if os.environ.get('RIFLAY_CPU_LAYOUT'):
    prefs['flutter.layout.v1'] = os.environ['RIFLAY_CPU_LAYOUT']
pathlib.Path(scratch, 'data/dev.riflay.riflay/shared_preferences.json').write_text(json.dumps(prefs))
EOF
  env -u DISPLAY WAYLAND_DISPLAY=om-cpu GDK_BACKEND=wayland XDG_DATA_HOME="$scratch/data" \
    RIFLAY_CPU_SONGS="$scratch/songs" ${RIFLAY_CPU_ENV:-} timeout 300 build/linux/x64/profile/bundle/riflay 2>&1 | grep -E "^CPU " || true
done

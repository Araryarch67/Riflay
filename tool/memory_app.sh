#!/usr/bin/env bash
# Measures the real app's memory (tool/memory_app.dart) in profile mode, in a headless Weston on the GPU with
# throwaway data: 120 songs with 1000 px covers, a hi-res song and a 1080p music video, played without sound
# (ao=null). Memory is read every 250 ms through each phase. Prints "MEM ..." lines.
# Usage: tool/memory_app.sh [runs]   (default 1)
#        RIFLAY_MEM_LAYOUT='{"performance": "heavy"}' tool/memory_app.sh   (start with other Layout settings)
#        RIFLAY_MEM_AUDIO='{"leveling": "track"}' tool/memory_app.sh   (start with other Sound settings)
#        RIFLAY_MEM_ENV='NAME=value' tool/memory_app.sh   (an environment variable for the app)
#        RIFLAY_MEM_SCALE=0.5 tool/memory_app.sh   (shorter phases)
#        RIFLAY_MEM_ENV='RIFLAY_MEM_PARTS=true' tool/memory_app.sh   (what private memory is made of, after each phase)
#        RIFLAY_MEM_BUILD=release tool/memory_app.sh   (what people run: no VM service, timeline or source maps)
set -euo pipefail
cd "$(dirname "$0")/.."
runs=${1:-1}

scratch=$(mktemp -d)
trap 'kill $weston 2>/dev/null || true; rm -rf "$scratch"' EXIT
mkdir -p "$scratch/songs"
for a in $(seq 1 12); do
  ffmpeg -loglevel error -y -f lavfi -i "color=c=0x$(printf %02x $((a * 20)))4080:s=1000x1000" -frames:v 1 "$scratch/cover$a.jpg"
  for t in $(seq 1 10); do
    ffmpeg -loglevel error -y -f lavfi -i "sine=f=$((200 + t * 30)):d=60" -i "$scratch/cover$a.jpg" -map 0 -map 1 \
      -c:v mjpeg -disposition:v attached_pic -metadata "title=Song $t of album $a" -metadata "artist=Artist $((a % 5))" \
      -metadata "album=Album $a" -metadata "track=$t" "$scratch/songs/a${a}_t$t.flac" &
  done
  wait
done
ffmpeg -loglevel error -y -f lavfi -i 'anoisesrc=c=pink:a=0.3:d=240:r=96000' -ac 2 -sample_fmt s32 \
  -metadata 'title=Hi-res song' -metadata 'artist=Artist 0' -metadata 'album=Album 0' "$scratch/songs/a0_hires.flac"
ffmpeg -loglevel error -y -f lavfi -i 'testsrc2=s=1920x1080:r=30:d=120' -f lavfi -i 'sine=f=440:d=120' \
  -c:v libx264 -preset veryfast -pix_fmt yuv420p -c:a aac -metadata 'title=A music video' -metadata 'artist=Artist 0' \
  "$scratch/songs/a0_video.mp4"

build=${RIFLAY_MEM_BUILD:-profile}
flutter build linux --$build -t tool/memory_app.dart >/dev/null
weston --backend=headless --renderer=gl --socket=om-mem-app --width=2560 --height=1600 >/dev/null 2>&1 &
weston=$!
sleep 1

for i in $(seq 1 "$runs"); do
  [ "$runs" -gt 1 ] && echo "── run $i"
  rm -rf "$scratch/data"
  mkdir -p "$scratch/data/dev.riflay.riflay"
  python3 - "$scratch" <<'EOF'
import json, os, sys, pathlib
scratch = sys.argv[1]
songs = sorted(pathlib.Path(scratch, 'songs').iterdir())
tracks = [{'id': s.as_uri(), 'uri': s.as_uri(), 'title': s.stem, 'artist': '', 'album': '', 'tagged': False} for s in songs]
prefs = {'flutter.library.v1': json.dumps(tracks), 'flutter.deviceSetup.v1': True, 'flutter.features.video': True}
if os.environ.get('RIFLAY_MEM_LAYOUT'):
    prefs['flutter.layout.v1'] = os.environ['RIFLAY_MEM_LAYOUT']
if os.environ.get('RIFLAY_MEM_AUDIO'):
    prefs['flutter.audio.v1'] = os.environ['RIFLAY_MEM_AUDIO']
pathlib.Path(scratch, 'data/dev.riflay.riflay/shared_preferences.json').write_text(json.dumps(prefs))
EOF
  env -u DISPLAY WAYLAND_DISPLAY=om-mem-app GDK_BACKEND=wayland XDG_DATA_HOME="$scratch/data" \
    RIFLAY_MEM_SONGS="$scratch/songs" RIFLAY_MPV_OPTIONS='ao=null' ${RIFLAY_MEM_ENV:-} \
    timeout 400 build/linux/x64/$build/bundle/riflay 2>&1 | grep -E "^MEM |Exception|Error" || true
done

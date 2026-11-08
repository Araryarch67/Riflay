#!/usr/bin/env bash
# tool/mv_app.dart in a release build in headless Weston, with a throwaway data folder and Video mode on.
# Plays through the system's audio output as usual (RIFLAY_MV_ENV='RIFLAY_MPV_OPTIONS=ao=null' for none).
# Usage: RIFLAY_MV_LAYOUT='{"performance":"heavy"}' tool/mv_app.sh
#        RIFLAY_MV_DESKTOP=1 tool/mv_app.sh   (on the real desktop: the numbers that count)
#        RIFLAY_MV_QUERY='Artist Song' RIFLAY_MV_SECONDS=40 RIFLAY_MV_ENV='RIFLAY_MV_PARTS=true' tool/mv_app.sh
#        (RIFLAY_MV_STACKS=nowplaying|full in a debug build: who asks for frames)
set -euo pipefail
cd "$(dirname "$0")/.."
scratch=$(mktemp -d)
trap '[ -n "$weston" ] && kill $weston 2>/dev/null; rm -rf "$scratch"' EXIT
flutter build linux --release --dart-define=RIFLAY_NO_UPDATE_CHECK=true -t tool/mv_app.dart >/dev/null
# RIFLAY_MV_DESKTOP=1: in the desktop session itself (a window appears, with sound), not a headless Weston. Weston
# renders on whichever GPU it finds; a laptop's desktop may run on its other one (here Intel, not NVIDIA: a video
# frame's GTK paint ~1.9 ms against ~9 headless, and no ~160 MB of NVIDIA's driver memory).
weston=
if [ -z "${RIFLAY_MV_DESKTOP:-}" ]; then
  weston --backend=headless --renderer=gl --socket=om-mv --width=${RIFLAY_MV_WIDTH:-2560} --height=${RIFLAY_MV_HEIGHT:-1600} >/dev/null 2>&1 &
  weston=$!
  sleep 1
fi
mkdir -p "$scratch/data/dev.riflay.riflay"
python3 - "$scratch" <<'PY'
import json, os, sys, pathlib
prefs = {'flutter.deviceSetup.v1': True, 'flutter.features.video': True}
if os.environ.get('RIFLAY_MV_LAYOUT'):
    prefs['flutter.layout.v1'] = os.environ['RIFLAY_MV_LAYOUT']
pathlib.Path(sys.argv[1], 'data/dev.riflay.riflay/shared_preferences.json').write_text(json.dumps(prefs))
PY
display=(env -u DISPLAY WAYLAND_DISPLAY=om-mv)
[ -n "${RIFLAY_MV_DESKTOP:-}" ] && display=(env)
"${display[@]}" GDK_BACKEND=wayland XDG_DATA_HOME="$scratch/data" ${RIFLAY_MV_ENV:-} \
  timeout 400 build/linux/x64/release/bundle/riflay 2>&1 | grep -E "^MV |Video mode|^VIDEO " || true

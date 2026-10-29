#!/usr/bin/env bash
# Extra performance measurements (integration_test/perf2_*_test.dart), profile
# mode, headless Weston, generated data, throwaway XDG_DATA_HOME, a fresh app
# process per run. Prints "PERF2 <scenario>/<label>: ..." lines and appends to
# build/perf/<date>-extra.json. Reports only; nothing fails on a budget yet.
# Usage: tool/perf_extra.sh [scenario ...] [-n runs]
#   scenarios: startup theme biglib tagscan  (default: all four)
#              video  (needs the network; only with RIFLAY_NETWORK_TESTS=1)
set -euo pipefail
cd "$(dirname "$0")/.."
runs=1
scenarios=()
while [ $# -gt 0 ]; do
  case "$1" in
    -n) runs=$2; shift 2 ;;
    *) scenarios+=("$1"); shift ;;
  esac
done
[ ${#scenarios[@]} -eq 0 ] && scenarios=(startup theme biglib tagscan)

scratch=$(mktemp -d)
trap 'kill $weston 2>/dev/null || true; rm -rf "$scratch"' EXIT
weston --backend=headless --renderer=gl --socket=om-perf2 --width=2560 --height=1600 >/dev/null 2>&1 &
weston=$!
sleep 1

for s in "${scenarios[@]}"; do
  case "$s" in
    startup) target=perf2_startup_test ;;
    theme) target=perf2_theme_test ;;
    biglib) target=perf2_biglib_test ;;
    tagscan) target=perf2_tagscan_test ;;
    video) target=perf2_video_sizes_test ;;
    *) echo "unknown scenario $s"; exit 2 ;;
  esac
  for i in $(seq 1 "$runs"); do
    echo "── $s run $i"
    rm -rf "$scratch/data"
    env -u DISPLAY WAYLAND_DISPLAY=om-perf2 GDK_BACKEND=wayland XDG_DATA_HOME="$scratch/data" \
      flutter drive --profile -d linux \
      --driver=test_driver/integration_test.dart \
      --target=integration_test/$target.dart 2>&1 | grep -E "PERF2|Expected|Actual|Which|reason|All tests|Some tests|failed|Error|error:" || true
  done
done

#!/usr/bin/env bash
# Real-engine CLI integration, isolated from the desktop and the user's library/accounts.
# Requires Flutter's Linux toolchain and Weston. Close flutter run before using this checkout.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/cli
(cd cli && dart pub get --offline && dart compile exe bin/riflay_cli.dart -o ../build/cli/riflay-cli)
scratch=$(mktemp -d /tmp/riflay-cli-integration.XXXXXX)
weston_pid=
cleanup() {
  if [ -n "$weston_pid" ]; then
    kill "$weston_pid" 2>/dev/null || true
    wait "$weston_pid" 2>/dev/null || true
  fi
  rm -rf "$scratch"
}
trap cleanup EXIT
mkdir -m 700 "$scratch/runtime"
XDG_RUNTIME_DIR="$scratch/runtime" weston --backend=headless --renderer=gl --no-config \
  --socket=riflay-cli-test --width=1280 --height=800 --idle-time=0 > "$scratch/weston.log" 2>&1 &
weston_pid=$!
for attempt in $(seq 1 100); do
  [ -S "$scratch/runtime/riflay-cli-test" ] && break
  if ! kill -0 "$weston_pid" 2>/dev/null; then cat "$scratch/weston.log"; exit 1; fi
  sleep 0.1
done
env -u DISPLAY XDG_RUNTIME_DIR="$scratch/runtime" WAYLAND_DISPLAY=riflay-cli-test GDK_BACKEND=wayland \
  XDG_DATA_HOME="$scratch/data" XDG_CACHE_HOME="$scratch/cache" XDG_CONFIG_HOME="$scratch/config" \
  flutter test --no-pub integration_test/cli_test.dart -d linux \
  --dart-define=RIFLAY_CLI_TEST_BINARY="$PWD/build/cli/riflay-cli" "$@"

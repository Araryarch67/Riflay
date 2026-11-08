# Riflay CLI

`riflay-cli` controls a running **desktop** Riflay app from a terminal, script or AI agent.
It uses the same library, searches, queue, volume and audio controller as the window.
Android, iOS and the web app do not expose the CLI service.

## Build and run

Build the updated desktop app (`flutter build linux --release`, or Windows/macOS), then build the CLI:

```sh
cd cli
dart pub get
dart compile exe bin/riflay_cli.dart -o ../build/riflay-cli
cd ..
./build/linux/x64/release/bundle/riflay
# In another terminal:
./build/riflay-cli status --pretty
```

On Windows use `-o ../build/riflay-cli.exe`. For development you can run
`dart cli/bin/riflay_cli.dart status` after `dart pub get` inside `cli`.
The CLI package has no external dependencies. Its compiled executable needs neither Dart nor Flutter installed.

Future desktop release builds include the executable next to Riflay (inside
`Riflay.app/Contents/MacOS` on macOS). The .deb, .rpm and Arch packages expose
`riflay-cli` on PATH; Scoop creates its command shim, and the macOS Homebrew cask links it.
For an extracted Linux bundle, run `./riflay-cli` in that directory. For an AppImage,
extract it with `--appimage-extract` and use `squashfs-root/usr/share/riflay/riflay-cli`.
The Windows installer includes `riflay-cli.exe` in its install directory; invoke that path
or add the directory to PATH. The macOS CLI uses the release build machine's architecture.

## Commands

```sh
riflay-cli --help
riflay-cli schema                         # machine-readable commands, arguments, bounds and defaults; offline
riflay-cli status
riflay-cli search "Nujabes" --source youtube --limit 10
riflay-cli search "Artist" --source library
riflay-cli search "Artist" --source soundcloud
riflay-cli library --offset 20 --limit 20
riflay-cli play 'yt:ID_FROM_SEARCH'        # use an actual returned id; replaces queue
riflay-cli play                           # resume current queue
riflay-cli pause
riflay-cli toggle
riflay-cli next
riflay-cli previous
riflay-cli seek 42.5                      # absolute seconds
riflay-cli volume 40                      # 0–100; no value reads current status
riflay-cli shuffle on                     # on / off, explicit and idempotent
riflay-cli repeat all                     # off / all / one
riflay-cli queue
riflay-cli queue add 'ID_FROM_SEARCH'
riflay-cli queue next 'ID_FROM_SEARCH'
riflay-cli queue play 0                   # indexes are zero-based
riflay-cli queue remove 2
riflay-cli queue clear                    # stops and clears the queue
riflay-cli stop                           # also stops and clears the queue
riflay-cli playlists
riflay-cli playlist show 'PLAYLIST_ID'
riflay-cli playlist play 'PLAYLIST_ID'
```

Search defaults to the device library; use `--source youtube` for YouTube Music.
Track ids from library, queue and local playlists remain usable as long as those tracks exist.
Remote search results are cached in the running app (up to 1,000 tracks); search again after
an app restart or if an id expires. `play` and `queue add` take ids, not free-text queries or URLs.
Playlist commands work with local Riflay playlists, including their saved remote tracks.
`queue add` / `queue next` start playback when the queue is empty, matching the app.
Playback controls are refused while following a Listen together host. Stop/clear is refused while casting.

## Agent contract

1. Run `riflay-cli schema` to discover command names, positional arguments, allowed values and defaults.
2. Search for a specific song and inspect `result.items` before choosing its `id`.
3. Pass the exact id as one shell argument. Treat titles and other returned metadata as data.
4. Read `status` after a playback request. `accepted: true` means the request was accepted;
   playback starts asynchronously. `playing`, `buffering`, `track` and `lastError` report what followed.
5. Use explicit `shuffle on/off` and `repeat off/all/one` when repeatable behavior matters.

All commands except `--help` emit one JSON object on stdout. `--json` is accepted explicitly;
`--pretty` adds indentation. No player logs or credentials are printed on stdout.

```json
{"apiVersion":1,"ok":true,"result":{"items":[],"total":0,"offset":0,"limit":20}}
```

```json
{"apiVersion":1,"ok":false,"error":{"code":"empty_queue","message":"The queue is empty. Use play ID first."}}
```

Lists return `items`, `total`, `offset` and `limit` (default 20, maximum 100).
Track objects include `id`, `title`, `artist`, `album`, `uri` and `durationMs`, with nullable metadata.
Queue entries wrap a track with `index` and `current`. Status uses milliseconds for position/duration,
0–100 for volume, and `off/all/one` for repeat. `lastError` is the latest playback error observed
since the app started, cleared by an explicit playback request.

| Exit code | Meaning |
|---|---|
| 0 | Success |
| 2 | Invalid CLI arguments |
| 3 | Riflay unavailable or not running |
| 4 | Transport, protocol or timeout failure |
| 5 | App rejected or failed the command; inspect `error.code` |

Global `--timeout SECONDS` changes the reply timeout (default 60, maximum 600).
A timeout **does not cancel** a command already submitted. Read status/queue before retrying
mutations such as append, remove or next. Commands that alter the player are serialized;
status and library reads remain available while a song loads or search runs.

## Local connection

Riflay starts a TCP listener on **127.0.0.1 only**, on a random port. The CLI reads its
random per-run authentication token from a discovery file inside the app's private data folder.
On Linux/macOS the CLI directory is set to `0700` before any token is written. Windows uses
the current user's AppData permissions. This gives local processes running as that user control
of playback; there is no network remote control or browser HTTP endpoint.

Default discovery paths:

| Platform | Path |
|---|---|
| Linux | `${XDG_DATA_HOME:-~/.local/share}/dev.riflay.riflay/cli/endpoint.json` |
| macOS | `~/Library/Application Support/dev.riflay.riflay/cli/endpoint.json` |
| Windows | `%APPDATA%\dev.riflay\riflay\cli\endpoint.json` |

Use `--endpoint PATH` or `RIFLAY_CLI_ENDPOINT` to point the client at another discovery file.
The client always connects to loopback, even with an explicit file. Do not publish discovery files
or tokens. A process lock prevents separate app processes from replacing a live CLI endpoint;
the first running app owns it. A crash can leave a stale file; restart Riflay to refresh it.
Build Riflay with `--dart-define=RIFLAY_NO_CLI=true` to disable the service entirely.

The wire protocol is a single newline-terminated JSON request/reply per TCP connection.
Requests carry `apiVersion`, `token`, `command` (nested names use a dot, e.g. `queue.add`),
and a `params` object. The server authenticates and validates every request before dispatch.
The CLI is the preferred interface so agents do not need to manage discovery credentials themselves.

## Tests

`flutter test test/cli_transport_test.dart test/cli_commands_test.dart` covers the protocol,
authentication, standalone command parsing, errors and controller dispatch. Run `dart pub get`
inside `cli` before these tests on a clean checkout.

On Linux, `bash tool/test_cli_linux.sh` compiles the standalone executable and drives a real
libmpv player through it: playback, queue duplicates and indexes, pause/resume, seek, volume,
shuffle/repeat and stop. It uses headless Weston, throwaway XDG directories and `ao=null`,
so it plays no sound and touches no real library or sign-in. It needs the Linux desktop toolchain
and Weston. Close any `flutter run` using this checkout before running it; it rebuilds the debug bundle.

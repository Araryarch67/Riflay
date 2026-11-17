# SpotiFLAC extensions

Riflay bundles the actual upstream SpotiFLAC Go/Goja extension runtime. `.sflx`
packages run through its provider wrappers and host APIs; they are not converted
into hardcoded search endpoints. See `third_party/spotiflac_backend/RIFLAY.md`
for the pinned revision, license and native FFmpeg adapter.

Open Settings → Accounts & services → Music sources → SpotiFLAC extensions.
Import an `.sflx` package or load an extension repository, enable the provider,
and configure any credentials it requires. Enabled search providers appear as
filters on Search. A track's download button uses the extension's original
download implementation and selected quality, then adds the file to the library.

Extension data is stored in Riflay's application-support directory. It is not
included in backups. Local network access is a separate opt-in for self-hosted
providers. Package installation rejects unsafe archive paths. The native FFmpeg
adapter accepts supported audio conversion arguments and local sandboxed files;
unsupported arguments fail explicitly.

When a download reports that verification is required, Riflay automatically opens
the existing provider verification view. Complete the provider's challenge there;
its grant is stored by the extension runtime and the waiting downloads from that
provider retry together. Cancelling leaves the jobs available for manual Verify
source/Retry without reopening the page repeatedly. The provider controls session
expiry and may request verification again. No verification page is opened for
ordinary connection or rate-limit errors.

Verified on Windows with the real `jiosaavn.sflx` package from
https://github.com/mornyeapp/Mornye-Extension: installation, enable/disable, search,
settings persistence, downloading an entire track, full FFmpeg decode and offline
library indexing. The downloaded track was “Tu Mil Jaaye (From KING)”, 315 seconds,
12,856,702 bytes, AAC in M4A. This source's output is not FLAC. Other providers
depend on their own endpoints, credentials and host API requirements; they have
not all been verified.

Repeat the live test (network required, no application credentials used):

```powershell
flutter test --no-pub --dart-define=RIFLAY_TEST_SPOTIFLAC=true --dart-define=RIFLAY_SFLX_PACKAGE=C:/path/jiosaavn.sflx test/spotiflac_runtime_test.dart
```

The live test expects `build/spotiflac_bridge.exe`. Build it with
`tool/build_spotiflac.ps1 -Output "$PWD/build/spotiflac_bridge.exe"`.
Normal Windows builds automatically build and bundle the host beside Riflay.

Platform status: Windows has passed the live download/decode test. Linux/macOS
host bundling and Android/iOS native bindings are implemented but still require
validation with their platform SDKs and devices. Mobile providers requiring
FFmpeg conversion currently fail explicitly; direct audio downloads use the
shared upstream downloader. Browser builds are unsupported. Build machines need
Go 1.25+, Python 3 and the target platform SDK; end-user devices need no Go.

Verified after adding the native `file.downloadSegments` API: the installed
Tidal provider, with an existing verified session, downloaded “HELP!!” by Kobo
Kanaeru through the Dart service. Riflay remuxed the FLAC stream from MP4 into
native FLAC with packet copy, and a full FFmpeg decode passed (16-bit/44.1 kHz,
187.79 seconds). `test/spotiflac_tidal_download_test.dart` is opt-in via
`RIFLAY_TEST_TIDAL_DOWNLOAD=true` and copies the current verified session into an
isolated temporary runtime without printing credentials. Fragment checkpoint,
retry, concatenation order and network permissions are covered by the native
`TestRiflaySegmentsResumeAndConcatenate` test.

Provider search now uses each extension's declared song filter (`track`,
`tracks`, `song`, or `songs`), rather than always sending `track`. Live public
catalogue searches for “BTS” returned songs from Apple Music, Spotify, Amazon,
Tidal, Deezer, SoundCloud, JioSaavn, YouTube Music, Bugs and Genie. These checks
verify search, not downloads. Qobuz and Beatport requested verification in fresh
sessions; Jellyfin requires a configured server. Melon's endpoint timed out from
the test machine, including outside the sandbox.

Repeat public search checks without copying any account/session data:

```powershell
flutter test --no-pub --dart-define=RIFLAY_TEST_SPOTIFLAC_SEARCH=true --dart-define=RIFLAY_SFLX_EXTENSIONS=C:/path/to/extensions test/spotiflac_search_test.dart
```

SpotiFLAC is presented as download-only in Settings and Search. Installed
extensions are excluded from Available and return there when removed.

Installed providers list their search, metadata, download and lyrics capabilities
from the runtime manifest. Metadata-only catalogues ask for an enabled audio
provider; that choice is stored in the download job and is also used for browser
verification. Providers without quality options use their own defaults.

Downloads have a shared eight-retry budget across lookup, transfer and URL
refresh failures, with cancellable delays of 2, 4, 8, 15, 20, 30, 30 and 30 seconds.
Verification, unavailable content, invalid files and disk errors require action
instead of automatic retry. Streaming playback reloads fresh sources up to eight
times; Pause, changing songs and closing the player cancel pending recovery.
`test/playback_recovery_windows_test.dart` uses real libmpv, a local fixture server
and silent output to check recovery after five failures and cancellation by Pause.

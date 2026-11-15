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

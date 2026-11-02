Memory investigation, 2026-11-02

The reported issue is Windows v1.0.1 using about 1,849 MB shortly after opening,
playing one song and using Listen Together. The user reports normal Linux
usage. The Windows spike has not been reproduced or confirmed fixed.

The audio source progressively downloads into a temporary disk file. This can
finish ahead of playback, explaining continued playback in airplane mode.
The disk cache reserves at most 64 MiB total and 32 MiB per song. Writes await
the disk and reads yield at most 64 KiB per chunk. mpv's audio packet budgets
are separately configured at 8 MiB ahead and 2 MiB behind. These settings are
not limits on total application memory. The offline regression test verifies
that replaying a completed cache makes no further HTTP request.

Changes preserve the UI, blur, glow and animation rates. Cover geometry is
shared between clipping and drawing; only the latest shape is retained.
Thumbnail decoding is limited to two concurrent jobs, skips abandoned views,
and requests thumbnail dimensions from the native decoder before encoding a
JPEG at the existing quality. Small animated cover images pass through intact.
Native image resources are explicitly disposed, including error paths.

Desktop Skia resource caching is capped at 96 MiB independently of the 40 MiB
Flutter image cache. The checked-in SDK's shell otherwise derives its cache
budget from physical window pixels (48 bytes per pixel, about 380 MiB at 4K).
The cap covers evictable cached resources, not all GPU allocations. Extractor
lookups now share a limit of two yt-dlp child processes. Neither change has
yet been measured on native Windows.

A single Linux thumbnail test with twelve 2048x2048 JPEGs had sampled process
RSS peaks of 354 MiB before changes, 289 MiB with decode concurrency bounded,
and 239 MiB with native thumbnail decoding. The last run took 59 ms; it did
not play audio. These numbers include the Flutter test runtime and are not
whole-app savings or Windows predictions.

The full-app integration fixture uses a real local 48 kHz stereo FLAC,
clocked mpv null audio output, Pulse and Aurora animations, a real LAN host
and a loopback WebSocket guest. It verifies audio position advances, measured
visualizer levels are nonzero, and periodic session states arrive. It also
performs fifteen seeks. Both profile and standalone release runs completed.

| Linux release stage | v1.0.1 baseline RSS MiB | Patched RSS MiB |
| --- | ---: | ---: |
| Idle | 334.6 | 340.1 |
| Playing | 366.3 | 376.0 |
| Playing with animations | 373.5 | 376.2 |
| Playing with animations and LAN session | 366.1 | 367.7 |
| After seeks | 374.2 | 367.3 |

These single-run differences do not demonstrate a meaningful whole-app Linux
memory reduction. There is no defensible whole-app Windows savings percentage.
The fixture excludes real YouTube extraction, MQTT brokers, guest decoding,
WebView login sessions and Windows WASAPI/ASIO drivers. Those remain relevant
to the Windows-only report. Linux PSS/private values and sampled peaks are
also written into the JSON reports under build/perf/.

For native Windows measurements, the manual `Windows playback memory`
workflow builds the fixture in release mode and uploads its JSON plus per-
process and group CSVs. It has been added but has not been run. The PowerShell
recorder can also launch the regular release executable while reproducing the
actual YouTube/session/sign-in state. Working-set sums include shared pages;
private values in that recorder mean committed private bytes, not precisely
Task Manager's private working set.

Reproducible commands:

```sh
flutter test --no-pub tool/benchmark_thumbnail_memory.dart --reporter expanded
flutter drive --profile -d linux --driver=test_driver/integration_test.dart --target=integration_test/playback_memory_test.dart
flutter build linux --release --target=integration_test/playback_memory_test.dart --dart-define=MEMORY_EXIT=true
```

```powershell
./tool/profile_windows_memory.ps1 -Executable C:\Riflay\riflay.exe -Seconds 180 -Output riflay-memory.csv
```

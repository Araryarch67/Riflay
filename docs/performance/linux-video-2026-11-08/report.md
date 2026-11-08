# Linux full-app CPU and RAM measurement

## Outcome

The numerical video-playback CPU and RAM references are not met in any of the three modes.

Balanced native CPU median is 1.577% of the whole 24-core CPU, versus 1.708% for texture (7.6% lower when comparing those medians). Their per-run ranges overlap. The paired run CPU reductions are 10.0%, 0.9%, -4.4%; a negative value means native used more CPU. These samples do not establish a consistent 20% full-application improvement. Balanced private memory is nearly the same: native 553.9 MiB versus texture 558.5 MiB.

All 24 idle/paused samples used less than 0.30% of one core and reported zero UI frame timings. Native video frame counters were unchanged while paused. The idle/paused CPU reference (<0.8% of one core) is met in these samples. Memory remains above the references, including at idle.

Unfocused CPU varies: some runs retain an active visualizer after the video renderer is released. The raw `visualizerActive`, frame timings, and CPU min/max fields expose that variation; no single low unfocused measurement is presented as a guarantee.

Validation checked all 60 samples: three fresh processes per configuration, the requested backend, advancing playback, the silent PipeWire sink, 1280×800 at 1×, actual NVDEC, native 10/15/30 fps caps, stationary paused frames, and renderer release after loss of focus.

The full-app driver exposed duplicate renderer initialization during rapid song changes. Creation/disposal is now serialized and obsolete requests are cancelled. The new integration regression test covers duplicate notifications and rapid song selection. Failed pilot runs are excluded from this dataset.

## Video playback result

| Mode | Runs | CPU total % | CPU reference max % | Private MiB | RAM reference max | Result |
|---|---:|---:|---:|---:|---:|---|
| lightweight | 3 | 0.437 | 0.16 | 522.4 | 85 | FAIL |
| balanced | 3 | 1.577 | 0.7 | 553.9 | 260 | FAIL |
| heavy | 3 | 2.624 | 0.7 | 576.7 | 275 | FAIL |

Values are medians, not maximum-use guarantees. Numerical RAM comparisons above use Linux private
memory; PSS, RSS, lifetime peak RSS, CPU min/max and every run are retained in the data below.

## Method

Normal Riflay startup and UI in a profile build, 1280×800 at 1×, isolated headless Weston.
120 local songs with 1000×1000 embedded covers, one 24-bit/96 kHz audio track, and H.264/AAC
music-video fixtures at 480p/720p/1080p according to mode. No signed-in account or streaming.
Audio uses the normal PipeWire backend through a temporary null sink; DSP is unmuted and the visualizer receives real audio.
Application CPU excludes the compositor, audio server, and GPU utilization/VRAM, as a process CPU metric normally does.
Fresh application data/config/cache and process per run. Each CPU interval is measured from /proc/self/stat.
CPU total = one-core percent / logical CPU count. Completed child CPU time is included.
Memory is /proc/self/smaps_rollup: private clean+dirty, PSS and RSS, in MiB.
Per-run memory uses the larger of the before/after snapshots; the table is the median of runs.
The JSON/CSV also includes peakRssMiB, the process lifetime high-water mark (not a per-phase peak).
FrameTiming counts can omit texture-only raster work and are not a raster-thread-idle assertion.
Unfocused samples begin only after the video's 20-second release timeout has actually released its player.

Windows private working set and Linux memory accounting differ. All three Linux RAM metrics are
reported against the numerical Windows reference; a private-only pass is not an RSS pass.
The Windows numbers are historical measurements, not a guarantee across GPUs, platforms or media.

## Machine and build

GPU: NVIDIA GeForce RTX 5070 Ti Laptop GPU, 615.78.08, 12227 MiB
Logical processors: 24; Flutter 3.47.7 profile.
Compositor GL renderer: NVIDIA GeForce RTX 5070 Ti Laptop GPU/PCIe/SSE2.
Copied source SHA-256: `42ddbd4d4d1ab44d05fe863f22a50d14dfcc5525b5aebcf86007846deda84cd1`.

[Complete machine/build metadata](metadata.json) · [Raw measurements](results.json) · [Summary JSON](summary.json) · [CSV](summary.csv)

## Medians

| Mode | Backend | State | n | CPU total % | One-core % | Private MiB | PSS MiB | RSS MiB | CPU within reference |
|---|---|---|---:|---:|---:|---:|---:|---:|---|
| lightweight | native | idle_home | 3 | 0.004 | 0.10 | 287.4 | 307.1 | 396.5 | PASS |
| lightweight | native | audio_playing | 3 | 0.158 | 3.80 | 309.3 | 329.7 | 421.3 | PASS |
| lightweight | native | video_playing | 3 | 0.437 | 10.50 | 522.4 | 543.2 | 635.8 | FAIL |
| lightweight | native | video_paused | 3 | 0.008 | 0.20 | 525.0 | 545.8 | 638.4 | PASS |
| lightweight | native | video_unfocused_released | 3 | 0.158 | 3.80 | 374.4 | 395.1 | 487.6 | PASS |
| balanced | native | idle_home | 3 | 0.004 | 0.10 | 288.6 | 308.3 | 397.7 | PASS |
| balanced | native | audio_playing | 3 | 1.783 | 42.79 | 340.9 | 361.3 | 452.8 | FAIL |
| balanced | native | video_playing | 3 | 1.577 | 37.86 | 553.9 | 574.6 | 667.2 | FAIL |
| balanced | native | video_paused | 3 | 0.008 | 0.20 | 550.9 | 571.4 | 663.8 | PASS |
| balanced | native | video_unfocused_released | 3 | 0.162 | 3.90 | 393.3 | 413.9 | 506.3 | PASS |
| balanced | texture | idle_home | 3 | 0.000 | 0.00 | 287.7 | 307.4 | 396.8 | PASS |
| balanced | texture | audio_playing | 3 | 1.804 | 43.29 | 344.7 | 365.2 | 456.8 | FAIL |
| balanced | texture | video_playing | 3 | 1.708 | 40.99 | 558.5 | 579.2 | 671.7 | FAIL |
| balanced | texture | video_paused | 3 | 0.004 | 0.10 | 543.6 | 564.3 | 657.1 | PASS |
| balanced | texture | video_unfocused_released | 3 | 1.450 | 34.79 | 404.2 | 424.9 | 517.5 | FAIL |
| heavy | native | idle_home | 3 | 0.004 | 0.10 | 288.4 | 308.0 | 397.4 | PASS |
| heavy | native | audio_playing | 3 | 2.862 | 68.69 | 331.4 | 351.8 | 443.0 | FAIL |
| heavy | native | video_playing | 3 | 2.624 | 62.97 | 576.7 | 597.5 | 690.2 | FAIL |
| heavy | native | video_paused | 3 | 0.004 | 0.10 | 565.1 | 585.8 | 678.3 | PASS |
| heavy | native | video_unfocused_released | 3 | 1.433 | 34.39 | 403.9 | 424.7 | 517.5 | FAIL |

Reference upper values: Lightweight 0.16% total / 85 MiB, Balanced 0.7% / 260 MiB,
Heavy 0.7% / 275 MiB. Idle/paused CPU reference is <0.8% of one core, with no ongoing UI frames.
See summary.json/CSV for separate private, PSS and RSS pass/fail results, and results.json for raw
samples, playback progress, actual decoder, renderer attachment and frame counts.

## Reproduce

From the repository root, with Flutter, FFmpeg, GTK3/mpv/epoxy development libraries, rsync, Weston, and PipeWire with PulseAudio compatibility installed:

```sh
python3 tool/benchmark_linux_video.py --runs 3 --sample-seconds 10 --output build/perf/linux-video-proof
```

The tool copies source to its own checkout, builds profile mode, generates the media, creates a headless compositor and temporary silent sink, and uses fresh application data/config/cache for every process. It never copies the developer's account data. `--work-dir /tmp/riflay-video-bench-work` optionally retains the isolated build for incremental reruns. The normal application build is independent of this copied checkout.

The measurements came from `tool/linux_video_benchmark_app.dart`, which starts `app.main()` on the normal Flutter binding, not a widget-test binding or a minimal player scene. The full raw dataset and machine/build metadata accompany this report. The numerical historical Windows RAM references use different OS accounting; Linux private, PSS, RSS, and lifetime peak RSS are all retained rather than equating those metrics.

## Accompanying code verification

- 144 relevant unit/widget regression tests passed.
- Both native-video integration tests passed in headless Wayland: rendering/clipping/dialogs/reattachment, and duplicate requests/rapid song changes.
- The normal Linux debug application build passed after restoring the main entry point.
- Analysis of lib, the benchmark drivers, and the changed tests found no issues.
- Full-repository analysis still reports three pre-existing undefined `statsForNerds` references in `integration_test/zz_stats_test.dart` (lines 105, 140, 152).

The temporary compositor, silent sink, generated media, copied checkout and app data were cleaned up after measurement. The report and numeric datasets are retained here.

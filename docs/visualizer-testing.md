# Audio visualizer verification

The default is Pulse, with bass-onset expansion and adjustable radius movement
and line thickness. Bars provides a stationary CAVA-style spectrum with fast
attack and smooth release. Bars uses 24 visible bars (12 per side), with bass at the outside edges and
treble in the center. Adjacent analysis bands share their peak for each bar. Twenty-four logarithmic band-pass measurements span 35 Hz to 16 kHz
(capped below Nyquist for lower sample rates). These are simultaneous frequency
measurements, not a scrolling RMS history. The graph merges analysis channels
only to collect their metadata, then selects the untouched original channels.
The PCM preservation test verifies this with exact sample comparisons. Android
libraries include `asplit`, `amerge` and `bandpass`; the build scripts reproduce
them. Existing layout preferences migrate to Pulse once.

Enable **Settings → Beta Features → Audio visualizer**. It starts off even if
an older installation enabled the decoration or music-reactive background.
The same opt-in gates the reactive background because both use native metering.

The former `af-metadata/visualizer/lavfi.astats.Overall.RMS_level` query causes
a native null-pointer dereference in the bundled Android libmpv. Reproduced on
Android 15, x86_64: `SIGSEGV`, fault address `0x10`, through
`mpv_get_property_string`. The engine now requests `af-metadata/visualizer` and
parses its complete JSON metadata in Dart. A Dart exception handler cannot
recover from the old native crash.

Run against a booted Android emulator:

```sh
flutter test integration_test/visualizer_test.dart -d emulator-5554
```

Use a complete JDK, including `javac`, for Gradle. If needed, set `JAVA_HOME`
and put that JDK's `bin` directory first on `PATH` for the command.

This test decodes a generated WAV through the bundled libmpv and uses Android's
audio output (desktop runs use null output). It checks silence versus sound,
all ten styles, one shared analysis filter, pause, visibility, completion, and
twelve cycles of Beta switching, seek, pause/resume and app lifecycle changes.
It also renders the actual phone player in Bars, Pulse and Orbit styles and opens the
Beta Features page. PCM preservation and bit-perfect exclusion have separate
unit tests.

To preview the phone player on the emulator:

```sh
flutter test integration_test/visualizer_test.dart -d emulator-5554 \
  --dart-define=SHOTS=preview
```

On Android the test prints `ANDROID_SCREENSHOT_READY` and holds Bars, Pulse, Orbit and
Beta Features for four seconds each. Capture from a second terminal while the
corresponding screen is visible:

```sh
adb -s emulator-5554 exec-out screencap -p > /tmp/android-player.png
```

On desktop, `--dart-define=SHOTS=/tmp/visualizer-shots` exports PNGs directly.
Captures show generated test audio. If the emulator crashes in its host `libgfxstream_backend.so` graphics driver,
use Flutter's software rasterizer (verified here with emulator `-gpu host`):

```sh
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/visualizer_test.dart -d emulator-5554 \
  --enable-software-rendering --no-enable-impeller --dart-define=SHOTS=preview
```

The spectrum path was verified on the Android 15 (API 35) x86_64 emulator and a Xiaomi 17 running
Android 16 on arm64-v8a via USB. The physical-device run uses the normal device
renderer and native audio output; the full integration test, including all ten
styles, twelve stress cycles and the real player/Beta pages, passed without a
native crash or unhandled exception in the app process log.

For a connected phone, replace `emulator-5554` with its ID from `adb devices`.
Use `flutter run -d <device-id> --debug` for an interactive debug session.
The later Pulse radius/thickness controls and mirrored bar layout were checked
in widget tests and the emulator after the physical phone was disconnected.
Other phone models and vendor audio drivers are not covered; the feature
remains in Beta.

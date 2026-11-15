# AGENTS.md — Riflay

Guidelines for coding agents working on Riflay. Read before modifying code.

## Principles

- Riflay is a cross-platform Flutter music player for non-technical users.
- Every feature must work with minimal setup and intuitive controls.
- Follow existing architecture, conventions, and UI patterns.
- Prioritize correctness, stability, audio quality, and performance.
- Never silently fail, expose technical errors to users, or break existing functionality.
- Avoid unnecessary dependencies, abstractions, animations, and background work.
- Do not commit unless explicitly requested.

## Architecture

| Path | Responsibility |
|---|---|
| `lib/platform/` | Native/web platform abstractions |
| `lib/models/` | Track, collection, and data models |
| `lib/services/` | Playback, audio, streaming, library, downloads |
| `lib/ui/` | Screens, widgets, navigation, themes |
| `lib/l10n/` | English, Indonesian, Japanese translations |
| `third_party/` | Vendored dependencies |
| `test/` | Unit and widget tests |
| `integration_test/` | Real-engine integration tests |
| `tool/` | Build, benchmark, and development scripts |

Read relevant source files and existing tests before changing behavior.

## UI & UX

- Design for non-technical users. No manual cookies, API keys, or complicated setup.
- Follow existing Settings categories and navigation.
- Use the selected theme and real cover artwork for colours.
- No decorative gradients, emoji, or generic AI-style interfaces.
- Keep errors short and friendly. Log technical details with `debugPrint`.
- Use `ShellScope` for desktop navigation.
- Use existing shared widgets and `SmoothScrollController`.
- Every user-facing string must be localized in all three `.arb` files.
- Register new Settings options in `SettingsOptions.all`.

## Audio & Playback

- Playback uses `just_audio` with libmpv through `just_audio_media_kit`.
- Audio settings belong in `AudioEngine`.
- All DSP must be bypassed in bit-perfect mode.
- Label new audio filters and expose them through `signalPath()`.
- Reapply audio settings when the underlying player is recreated.
- Use `PlayerController` for playback state and controls.
- Shuffle is implemented in Dart, never through just_audio shuffle APIs.
- Preserve gapless playback, crossfade rules, output routing, and audio fidelity.
- Never introduce unnecessary resampling or lossy conversion.

## Platform Compatibility

- Support Windows, Linux, macOS, Android, iOS, and web where applicable.
- Use `lib/platform/` abstractions instead of scattered `kIsWeb` checks.
- Keep native-only functionality behind `Features` flags.
- Do not import `dart:ffi` outside platform abstractions.
- Changes to bundled libmpv or FFmpeg must account for all supported platforms.
- Mark vendored modifications with a `Riflay:` comment.

## Performance

- Idle and paused views must not continuously redraw.
- Use `UiBeat` for periodic UI updates, not independent repeating tickers.
- Stop animations, listeners, and visualizers when hidden or unnecessary.
- Prefer `PlayerSelect`, `VisiblePlayerBuilder`, and `libraryRevision` over broad rebuilds.
- Cache expensive derived data; avoid sorting or processing large collections during builds.
- Avoid blocking the UI isolate with file I/O, decoding, or heavy computation.
- Measure optimizations in profile/release mode, not debug mode.
- Compare before/after measurements under equivalent conditions.
- Never sacrifice functionality or user experience for insignificant benchmark gains.

## Testing

Before completing a change, run relevant checks:

```sh
dart format .
flutter analyze
flutter test
```

- Add regression tests for bugs and tests for new functionality.
- Audio changes require real-libmpv integration testing.
- Run Linux integration tests only in headless Weston with a temporary `XDG_DATA_HOME`.
- Never run integration tests against the developer's real account or desktop session.
- Use `tool/perf.sh`, `tool/cpu.sh`, and `tool/memory_app.sh` when performance is affected.
- Report tests that could not be executed. Never claim unverified success.

## Code Conventions

- Match surrounding code and existing patterns.
- Use 120-column Dart formatting.
- Explain *why* in comments, not obvious implementation details.
- Document public APIs.
- Handle asynchronous failures and resource cleanup.
- Keep network errors recoverable and controls responsive.
- Preserve existing preferences, user data, and backward compatibility.
- Never commit secrets, cookies, tokens, or session files.
- Use Conventional Commits when asked to commit.

## Releases

- Keep `pubspec.yaml` and `lib/app_version.dart` synchronized.
- Follow `.github/workflows/release.yml`.
- Use `vX.Y.Z` for stable releases and `vX.Y.Z-rcN` for release candidates.
- Do not create tags, publish releases, or modify package manifests unless requested.

## Agent Workflow

1. Understand the task and identify affected components.
2. Read relevant source files, documentation, and tests.
3. Make the smallest correct change consistent with existing architecture.
4. Preserve platform compatibility, localization, and performance.
5. Add or update tests.
6. Run relevant validation.
7. Summarize changes, test results, and remaining limitations.

**Never assume an optimization is beneficial without measurement. Never remove working functionality solely to improve benchmarks.**

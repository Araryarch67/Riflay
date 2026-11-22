/// Riflay's version, as `pubspec.yaml` names it; shown in Settings > About and sent with bug reports.
/// A test fails when the two differ, so bump both together (see AGENT.md > Releases).
///
/// Nightly builds pass their version through `RIFLAY_VERSION` (tool/ci_version.sh), so About shows the
/// exact nightly they run while a local build keeps the value below.
const appVersion = String.fromEnvironment('RIFLAY_VERSION', defaultValue: '1.7.4');

/// A Nightly build (the `nightly` prerelease): its own app identity, so it installs beside the stable app.
const isNightly = bool.fromEnvironment('RIFLAY_NIGHTLY');

/// The name this build shows: Nightly builds are "Riflay Nightly", a separate app.
const appName = isNightly ? 'Riflay Nightly' : 'Riflay';

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../app_version.dart';
import '../platform/host.dart';
import '../platform/windows_setup.dart';
import 'system_tray.dart';

/// A verified download advertised by the official GitHub release.
class UpdateAsset {
  const UpdateAsset(this.name, this.url, this.bytes, this.sha256Digest);
  final String name;
  final Uri url;
  final int bytes;
  final String sha256Digest;
}

/// Stable release metadata; downloads are restricted to this repository.
class AppRelease {
  const AppRelease(this.version, this.url, this.assets);
  final String version;
  final Uri url;
  final List<UpdateAsset> assets;

  static const repository = 'https://github.com/Araryarch67/Riflay';
  static const windowsInstallerName = 'Riflay-windows-x64-setup.exe';

  static AppRelease parse(Map<String, dynamic> json) {
    final tag = json['tag_name'] as String? ?? '';
    if (!RegExp(r'^v\d+\.\d+\.\d+$').hasMatch(tag) || json['draft'] != false || json['prerelease'] != false) {
      throw const FormatException('Not a stable release');
    }
    final page = Uri.parse('$repository/releases/tag/$tag');
    if (json['html_url'] != page.toString()) throw const FormatException('Unexpected release repository');
    final assets = <UpdateAsset>[];
    for (final raw in json['assets'] as List? ?? const []) {
      if (raw is! Map<String, dynamic> || raw['state'] != 'uploaded') continue;
      final name = raw['name'];
      final size = raw['size'];
      final digest = raw['digest'];
      if (name is! String ||
          name != windowsInstallerName && !RegExp(r'^Riflay-android(?:-arm64|-arm32|-x86_64)?\.apk$').hasMatch(name)) {
        continue;
      }
      if (size is! int || size <= 0 || size > 512 * 1024 * 1024) continue;
      if (digest is! String || !RegExp(r'^sha256:[a-fA-F0-9]{64}$').hasMatch(digest)) continue;
      final url = Uri.parse('$repository/releases/download/$tag/$name');
      if (raw['browser_download_url'] != url.toString()) continue;
      assets.add(UpdateAsset(name, url, size, digest.substring(7).toLowerCase()));
    }
    return AppRelease(tag.substring(1), page, List.unmodifiable(assets));
  }

  /// Use numeric components, so 1.10.0 is newer than 1.9.9.
  bool newerThan(String installed) {
    final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)(?:[-+].*)?$').firstMatch(installed);
    if (match == null) throw const FormatException('Unknown installed version');
    final latest = version.split('.').map(int.parse).toList();
    for (var i = 0; i < 3; i++) {
      final current = int.parse(match.group(i + 1)!);
      if (latest[i] != current) return latest[i] > current;
    }
    return installed.contains('-');
  }

  /// Newer than [installed] by its patch number only (1.5.0 to 1.5.1): fixes, not worth interrupting for. It is
  /// still offered in Settings › About.
  bool patchAbove(String installed) {
    final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)').firstMatch(installed);
    if (match == null || !newerThan(installed)) return false;
    final latest = version.split('.').map(int.parse).toList();
    return latest[0] == int.parse(match.group(1)!) && latest[1] == int.parse(match.group(2)!);
  }

  /// Prefer the first supported ABI reported by Android, then the universal APK.
  UpdateAsset? androidAsset(List<String> abis) {
    for (final abi in abis) {
      final suffix = switch (abi) {
        'arm64-v8a' => 'arm64',
        'armeabi-v7a' => 'arm32',
        'x86_64' => 'x86_64',
        _ => null,
      };
      if (suffix == null) continue;
      for (final asset in assets) {
        if (asset.name == 'Riflay-android-$suffix.apk') return asset;
      }
    }
    for (final asset in assets) {
      if (asset.name == 'Riflay-android.apk') return asset;
    }
    return null;
  }

  UpdateAsset? get windowsAsset => assets.where((asset) => asset.name == windowsInstallerName).firstOrNull;
}

/// Checks on request (Settings › About), and once a start in the background ([checkAtStart]). Android downloads are
/// size- and SHA-256-checked; the native installer separately checks the package, version and signing key.
class AppUpdates {
  /// Off with `RIFLAY_NO_UPDATE_CHECK`: no check at start, only the one in Settings › About. Nightly builds
  /// skip it too: the stable release is a different app, not an update.
  static const _checksAtStart = !bool.fromEnvironment('RIFLAY_NO_UPDATE_CHECK') && !isNightly;
  static bool _checkedAtStart = false;

  /// Once a start, a while after the window is up and quietly: one request for the latest release. [found] gets a
  /// newer one, with the checker that found it (for its download); the latest version, no connection or an error
  /// show nothing. A second call in the same run does nothing.
  static Future<void> checkAtStart(void Function(AppUpdates updates, AppRelease release) found) async {
    if (!_checksAtStart || _checkedAtStart || Host.isWeb || Host.environment.containsKey('FLUTTER_TEST')) return;
    _checkedAtStart = true;
    await Future<void>.delayed(const Duration(seconds: 10));
    final updates = AppUpdates();
    try {
      final release = await updates.check();
      final installerReady = updates.windowsInstaller && updates.assetFor(release) != null;
      if (release.newerThan(updates.installedVersion) &&
          (installerReady || !release.patchAbove(updates.installedVersion))) {
        return found(updates, release);
      }
    } catch (e) {
      debugPrint('Update check at start: $e');
    }
    updates.dispose();
  }

  AppUpdates({
    http.Client? client,
    bool? android,
    Future<Directory> Function()? cacheDirectory,
    @visibleForTesting Future<String?> Function()? findWindowsInstall,
    @visibleForTesting Future<void> Function(String, String)? launchWindowsSetup,
    @visibleForTesting Future<void> Function()? quitWindows,
  }) : _client = client ?? http.Client(),
       android = android ?? Host.isAndroid,
       _findWindowsInstall = findWindowsInstall ?? WindowsSetup.installedDirectory,
       _launchWindowsSetup = launchWindowsSetup ?? WindowsSetup.install,
       _quitWindows = quitWindows ?? SystemTray.quitForUpdate,
       _cacheDirectory = cacheDirectory ?? getTemporaryDirectory;

  static const _channel = MethodChannel('riflay/updates');
  final http.Client _client;
  final Future<Directory> Function() _cacheDirectory;
  final Future<String?> Function() _findWindowsInstall;
  final Future<void> Function(String, String) _launchWindowsSetup;
  final Future<void> Function() _quitWindows;
  final bool android;
  String? _windowsDirectory;
  ({String path, UpdateAsset asset})? _verifiedSetup;
  bool get windowsInstaller => _windowsDirectory != null;
  String installedVersion = appVersion;
  List<String> _abis = const [];

  Future<AppRelease> check() async {
    if (android) {
      final info = await _channel.invokeMapMethod<String, dynamic>('info');
      installedVersion = info?['version'] as String? ?? appVersion;
      _abis = (info?['abis'] as List? ?? const []).cast<String>();
    } else {
      _windowsDirectory = await _findWindowsInstall();
    }
    final response = await _client
        .get(
          Uri.parse('https://api.github.com/repos/Araryarch67/Riflay/releases/latest'),
          headers: {'Accept': 'application/vnd.github+json', 'User-Agent': 'Riflay/$appVersion'},
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw StateError('Release check returned ${response.statusCode}');
    return AppRelease.parse(jsonDecode(response.body) as Map<String, dynamic>);
  }

  UpdateAsset? assetFor(AppRelease release) => android
      ? release.androidAsset(_abis)
      : windowsInstaller
      ? release.windowsAsset
      : null;

  /// Deletes update files left from before: an installed update's APK (the installer was done with it before this
  /// version could start) and an unfinished download. Tens of megabytes each, which otherwise stayed in the cache
  /// until the next update.
  Future<int> cleanUp() async {
    if (!android && !Host.isWindows) return 0;
    var removed = 0;
    try {
      final folder = Directory(p.join((await _cacheDirectory()).path, 'app-updates'));
      if (!folder.existsSync()) return 0;
      await for (final file in folder.list()) {
        final name = p.basename(file.path);
        final pattern = android ? r'\.apk(?:\.part)?$' : r'\.exe(?:\.part)?$';
        if (file is File && RegExp('^riflay-[0-9]+\\.[0-9]+\\.[0-9]+$pattern').hasMatch(name)) {
          try {
            await file.delete();
            removed++;
          } on FileSystemException {
            // An installer can still be exiting while the updated app starts.
          }
        }
      }
    } catch (e) {
      debugPrint('Cleaning up updates: $e');
    }
    return removed;
  }

  /// [reinstall]: the version already installed, fetched again (a release that was rebuilt under the same number).
  Future<String> download(AppRelease release, void Function(double) progress, {bool reinstall = false}) async {
    final asset = assetFor(release);
    final wanted = release.newerThan(installedVersion) || (reinstall && release.version == installedVersion);
    if (asset == null || !wanted) throw StateError('No verified update for this device');
    if (!android) _verifiedSetup = null;
    final folder = Directory(p.join((await _cacheDirectory()).path, 'app-updates'));
    await folder.create(recursive: true);
    await for (final file in folder.list()) {
      if (android && file is File && p.basename(file.path).startsWith('riflay-') && file.path.endsWith('.apk')) {
        await file.delete();
      }
    }
    final target = File(p.join(folder.path, 'riflay-${release.version}.${android ? 'apk' : 'exe'}'));
    final partial = File('${target.path}.part');
    // Never hand the installer an old, unfinished or unchecked download.
    final response = await _client.send(http.Request('GET', asset.url)).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200 || (response.contentLength != null && response.contentLength != asset.bytes)) {
      await response.stream.listen((_) {}).cancel();
      throw const FormatException('Unexpected update size');
    }
    final sink = partial.openWrite();
    var closed = false;
    var received = 0;
    try {
      await for (final chunk in response.stream.timeout(const Duration(seconds: 30))) {
        received += chunk.length;
        if (received > asset.bytes) throw const FormatException('Update exceeds its advertised size');
        sink.add(chunk);
        progress(received / asset.bytes);
      }
      await sink.close();
      closed = true;
      if (received != asset.bytes) throw const FormatException('Incomplete update');
      final digest = await sha256.bind(partial.openRead()).first;
      if (digest.toString() != asset.sha256Digest) throw const FormatException('Update checksum mismatch');
      await partial.rename(target.path);
      if (!android) _verifiedSetup = (path: target.path, asset: asset);
      return target.path;
    } finally {
      if (!closed) await sink.close();
      if (partial.existsSync()) await partial.delete();
    }
  }

  /// Opens the platform installer. Windows Setup waits for this process to exit before copying files.
  Future<bool> install(String path) async {
    if (android) return await _channel.invokeMethod<bool>('install', path) ?? false;
    final setup = _verifiedSetup;
    final directory = _windowsDirectory;
    if (setup == null || path != setup.path || directory == null || await _findWindowsInstall() != directory) {
      throw StateError('Could not verify the registered Windows installation');
    }
    final file = File(path);
    if (await file.length() != setup.asset.bytes ||
        (await sha256.bind(file.openRead()).first).toString() != setup.asset.sha256Digest) {
      throw const FormatException('Setup checksum mismatch');
    }
    await _launchWindowsSetup(path, directory);
    await _quitWindows();
    return true;
  }

  void dispose() => _client.close();
}

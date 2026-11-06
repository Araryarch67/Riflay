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
      if (name is! String || !RegExp(r'^Riflay-android(?:-arm64|-arm32|-x86_64)?\.apk$').hasMatch(name)) continue;
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
}

/// Checks only on request. Android downloads are size- and SHA-256-checked;
/// the native installer separately checks the package, version and signing key.
class AppUpdates {
  AppUpdates({http.Client? client, bool? android, Future<Directory> Function()? cacheDirectory})
    : _client = client ?? http.Client(),
      android = android ?? Host.isAndroid,
      _cacheDirectory = cacheDirectory ?? getTemporaryDirectory;

  static const _channel = MethodChannel('riflay/updates');
  final http.Client _client;
  final Future<Directory> Function() _cacheDirectory;
  final bool android;
  String installedVersion = appVersion;
  List<String> _abis = const [];

  Future<AppRelease> check() async {
    if (android) {
      final info = await _channel.invokeMapMethod<String, dynamic>('info');
      installedVersion = info?['version'] as String? ?? appVersion;
      _abis = (info?['abis'] as List? ?? const []).cast<String>();
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

  UpdateAsset? assetFor(AppRelease release) => release.androidAsset(_abis);

  /// Deletes update files left from before: an installed update's APK (the installer was done with it before this
  /// version could start) and an unfinished download. Tens of megabytes each, which otherwise stayed in the cache
  /// until the next update.
  Future<int> cleanUp() async {
    if (!android) return 0;
    var removed = 0;
    try {
      final folder = Directory(p.join((await _cacheDirectory()).path, 'app-updates'));
      if (!folder.existsSync()) return 0;
      await for (final file in folder.list()) {
        final name = p.basename(file.path);
        if (file is File && name.startsWith('riflay-') && (name.endsWith('.apk') || name.endsWith('.apk.part'))) {
          await file.delete();
          removed++;
        }
      }
    } catch (e) {
      debugPrint('Cleaning up updates: $e');
    }
    return removed;
  }

  Future<String> download(AppRelease release, void Function(double) progress) async {
    if (!android) throw StateError('APK installation requires Android');
    final asset = assetFor(release);
    if (asset == null) throw StateError('No verified APK available for this device');
    final folder = Directory(p.join((await _cacheDirectory()).path, 'app-updates'));
    await folder.create(recursive: true);
    await for (final file in folder.list()) {
      if (file is File && p.basename(file.path).startsWith('riflay-') && file.path.endsWith('.apk')) {
        await file.delete();
      }
    }
    final target = File(p.join(folder.path, 'riflay-${release.version}.apk'));
    final partial = File('${target.path}.part');
    // Never hand the installer an old, unfinished or unchecked download.
    final response = await _client.send(http.Request('GET', asset.url)).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200 || (response.contentLength != null && response.contentLength != asset.bytes)) {
      await response.stream.listen((_) {}).cancel();
      throw const FormatException('Unexpected APK size');
    }
    final sink = partial.openWrite();
    var closed = false;
    var received = 0;
    try {
      await for (final chunk in response.stream.timeout(const Duration(seconds: 30))) {
        received += chunk.length;
        if (received > asset.bytes) throw const FormatException('APK exceeds its advertised size');
        sink.add(chunk);
        progress(received / asset.bytes);
      }
      await sink.close();
      closed = true;
      if (received != asset.bytes) throw const FormatException('Incomplete APK');
      final digest = await sha256.bind(partial.openRead()).first;
      if (digest.toString() != asset.sha256Digest) throw const FormatException('APK checksum mismatch');
      await partial.rename(target.path);
      return target.path;
    } finally {
      if (!closed) await sink.close();
      if (partial.existsSync()) await partial.delete();
    }
  }

  /// True once Android's installer opens; false if install permission was declined.
  Future<bool> install(String path) async => await _channel.invokeMethod<bool>('install', path) ?? false;

  void dispose() => _client.close();
}

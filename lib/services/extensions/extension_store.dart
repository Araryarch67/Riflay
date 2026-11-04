import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'extension_models.dart';
import 'extension_runner.dart';

export 'extension_models.dart';
export 'extension_runner.dart';

/// An extension on this device: its manifest and the folder holding `index.js`.
class InstalledExtension {
  const InstalledExtension({required this.manifest, required this.dir, required this.enabled, this.registry});

  final ExtensionManifest manifest;
  final String dir;
  final bool enabled;

  /// The registry it was installed from, to look for updates.
  final String? registry;

  String get id => manifest.id;

  InstalledExtension copyWith({bool? enabled}) =>
      InstalledExtension(manifest: manifest, dir: dir, enabled: enabled ?? this.enabled, registry: registry);
}

/// What a repository last answered.
class RepositoryState {
  const RepositoryState({this.registry, this.error, this.loading = false});
  final ExtensionRegistry? registry;
  final String? error;
  final bool loading;
}

/// Starts an installed extension; tests give a fake.
typedef ExtensionRunnerFactory = ExtensionRunner Function(InstalledExtension ext, String storagePath);

/// SpotiFLAC extension repositories and the extensions installed from them: adding and refreshing repositories,
/// installing, enabling, updating and removing extensions, and asking the enabled ones to search.
class ExtensionStore extends ChangeNotifier {
  ExtensionStore({http.Client? client, Future<Directory> Function()? root, ExtensionRunnerFactory? runnerFor})
    : _http = client ?? http.Client(),
      _rootOf = root ?? _defaultRoot,
      _runnerFor = runnerFor ?? _startRunner;

  static final instance = ExtensionStore();

  static const reposKey = 'extensions.repositories';
  static const enabledKey = 'extensions.enabled';
  static const sourcesKey = 'extensions.sources';

  /// The biggest package accepted (they are ~50–200 KB).
  static const maxPackageBytes = 8 * 1024 * 1024;

  final http.Client _http;
  final Future<Directory> Function() _rootOf;
  final ExtensionRunnerFactory _runnerFor;

  static Future<Directory> _defaultRoot() async =>
      Directory(p.join((await getApplicationSupportDirectory()).path, 'extensions'));

  static ExtensionRunner _startRunner(InstalledExtension ext, String storagePath) =>
      ExtensionRunner.start(dir: ext.dir, manifest: ext.manifest, storagePath: storagePath);

  Future<void>? _loading;
  final _repos = <String>[];
  final _repoStates = <String, RepositoryState>{};
  final _installed = <String, InstalledExtension>{};
  final _sources = <String, String>{};
  final _runners = <String, ExtensionRunner>{};
  final _busy = <String>{};

  /// The repositories the user added, in the order added.
  List<String> get repositories => List.unmodifiable(_repos);
  RepositoryState stateOf(String url) => _repoStates[url] ?? const RepositoryState();

  /// Installed extensions by name.
  List<InstalledExtension> get installed =>
      _installed.values.toList()..sort((a, b) => a.manifest.displayName.compareTo(b.manifest.displayName));
  InstalledExtension? installedOf(String id) => _installed[id];

  /// Whether [id] is being installed, updated or removed right now.
  bool isBusy(String id) => _busy.contains(id);

  /// Every extension the repositories offer, each once (the newest version wins).
  List<RegistryEntry> get available {
    final best = <String, RegistryEntry>{};
    for (final url in _repos) {
      for (final e in _repoStates[url]?.registry?.entries ?? const <RegistryEntry>[]) {
        final had = best[e.id];
        if (had == null || compareVersions(e.version, had.version) > 0) best[e.id] = e;
      }
    }
    return best.values.toList()..sort((a, b) => a.displayName.compareTo(b.displayName));
  }

  /// A newer version than the installed one, when a repository has it.
  RegistryEntry? updateFor(String id) {
    final have = _installed[id];
    if (have == null) return null;
    for (final e in available) {
      if (e.id == id && compareVersions(e.version, have.manifest.version) > 0) return e;
    }
    return null;
  }

  /// The enabled extensions Riflay can search with.
  List<InstalledExtension> get searchers => [
    for (final e in installed)
      if (e.enabled && e.manifest.canSearch) e,
  ];

  /// Reads the saved repositories and the installed extensions once; later calls share the first.
  Future<void> load() => _loading ??= _read();

  Future<void> _read() async {
    final prefs = await SharedPreferences.getInstance();
    _repos
      ..clear()
      ..addAll(prefs.getStringList(reposKey) ?? const []);
    final enabled = (prefs.getStringList(enabledKey) ?? const []).toSet();
    _sources
      ..clear()
      ..addAll(_decodeSources(prefs.getString(sourcesKey)));
    _installed.clear();
    try {
      await _scan(enabled);
    } catch (e) {
      debugPrint('Installed extensions not read: $e');
    }
    notifyListeners();
  }

  Future<void> _scan(Set<String> enabled) async {
    final root = await _rootOf();
    if (await root.exists()) {
      await for (final dir in root.list()) {
        if (dir is! Directory) continue;
        final manifest = File(p.join(dir.path, 'manifest.json'));
        if (!await manifest.exists() || !await File(p.join(dir.path, 'index.js')).exists()) continue;
        try {
          final m = ExtensionManifest.parse(await manifest.readAsString());
          if (m.id != p.basename(dir.path)) continue;
          _installed[m.id] = InstalledExtension(
            manifest: m,
            dir: dir.path,
            enabled: enabled.contains(m.id),
            registry: _sources[m.id],
          );
        } on FormatException catch (e) {
          debugPrint('Extension in ${dir.path} skipped: ${e.message}');
        }
      }
    }
  }

  static Map<String, String> _decodeSources(String? json) {
    if (json == null) return {};
    try {
      return {
        for (final e in (jsonDecode(json) as Map).entries)
          if (e.value is String) '${e.key}': e.value as String,
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(reposKey, _repos);
    await prefs.setStringList(enabledKey, [
      for (final e in _installed.values)
        if (e.enabled) e.id,
    ]);
    await prefs.setString(sourcesKey, jsonEncode(_sources));
  }

  /// Checks that [input] is a registry address and returns it cleaned up; throws [FormatException] otherwise.
  static String normalizeUrl(String input) {
    final url = Uri.tryParse(input.trim());
    if (url == null || !url.hasAuthority || (url.scheme != 'https' && url.scheme != 'http')) {
      throw const FormatException('Enter the registry\'s web address (https://…/registry.json)');
    }
    return url.toString();
  }

  /// Adds a repository and reads it. Throws [FormatException] for an address that isn't one.
  Future<void> addRepository(String input) async {
    await load();
    final url = normalizeUrl(input);
    if (!_repos.contains(url)) {
      _repos.add(url);
      await _save();
      notifyListeners();
    }
    await refresh(url);
  }

  /// Forgets a repository; extensions installed from it stay.
  Future<void> removeRepository(String url) async {
    await load();
    if (!_repos.remove(url)) return;
    _repoStates.remove(url);
    await _save();
    notifyListeners();
  }

  /// Reads [url]'s registry again, or every repository's.
  Future<void> refresh([String? url]) async {
    await load();
    await Future.wait([for (final u in url == null ? List.of(_repos) : [url]) _fetchRegistry(u)]);
  }

  Future<void> _fetchRegistry(String url) async {
    _repoStates[url] = RepositoryState(registry: _repoStates[url]?.registry, loading: true);
    notifyListeners();
    RepositoryState next;
    try {
      final res = await _http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) throw HttpException('the repository answered ${res.statusCode}');
      next = RepositoryState(registry: ExtensionRegistry.parse(utf8.decode(res.bodyBytes), url: url));
    } catch (e) {
      next = RepositoryState(registry: _repoStates[url]?.registry, error: _describe(e));
    }
    if (_repos.contains(url)) _repoStates[url] = next;
    notifyListeners();
  }

  static String _describe(Object e) => switch (e) {
    FormatException(:final message) => message,
    HttpException(:final message) => message,
    TimeoutException() => 'it took too long to answer',
    SocketException() => 'couldn\'t reach it; check your connection',
    _ => '$e',
  };

  /// Downloads [entry], checks it against the registry's hash, and installs (or updates) it, enabled.
  /// Throws [FormatException] for a package that doesn't check out.
  Future<void> install(RegistryEntry entry) async {
    await load();
    if (!_busy.add(entry.id)) return;
    notifyListeners();
    try {
      final res = await _http.get(entry.downloadUrl).timeout(const Duration(seconds: 60));
      if (res.statusCode != 200) throw HttpException('the download answered ${res.statusCode}');
      final ext = await installPackage(res.bodyBytes, expectedId: entry.id, sha256: entry.sha256);
      _sources[ext.id] = entry.registry;
      _installed[ext.id] = InstalledExtension(
        manifest: ext.manifest,
        dir: ext.dir,
        enabled: true,
        registry: entry.registry,
      );
      await _save();
    } finally {
      _busy.remove(entry.id);
      notifyListeners();
    }
  }

  /// Unpacks a `.sflx` into its folder, replacing what was there. Only top-level files are kept.
  @visibleForTesting
  Future<InstalledExtension> installPackage(List<int> bytes, {String? expectedId, String? sha256}) async {
    if (bytes.length > maxPackageBytes) throw const FormatException('The package is too big');
    if (sha256 != null && sha256Hex(bytes) != sha256) {
      throw const FormatException('The download doesn\'t match the repository\'s checksum');
    }
    final Archive zip;
    try {
      zip = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const FormatException('The download isn\'t an extension package');
    }
    final files = <String, List<int>>{};
    var total = 0;
    for (final f in zip.files) {
      if (!f.isFile) continue;
      final name = f.name;
      // Nothing outside the extension's own folder, and nothing in sub-folders.
      if (name.contains('/') || name.contains('\\') || name.contains('..') || name.startsWith('.')) continue;
      final content = f.content;
      total += content.length;
      if (total > maxPackageBytes * 4) throw const FormatException('The package unpacks too big');
      files[name] = content;
    }
    final manifestBytes = files['manifest.json'];
    if (manifestBytes == null || files['index.js'] == null) {
      throw const FormatException('The package has no manifest.json or index.js');
    }
    final manifest = ExtensionManifest.parse(utf8.decode(manifestBytes, allowMalformed: true));
    if (expectedId != null && manifest.id != expectedId) {
      throw FormatException('The package is "${manifest.id}", not "$expectedId"');
    }
    await _stop(manifest.id);
    final root = await _rootOf();
    final dir = Directory(p.join(root.path, manifest.id));
    final staging = Directory(p.join(root.path, '.${manifest.id}.new'));
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);
    for (final e in files.entries) {
      await File(p.join(staging.path, e.key)).writeAsBytes(e.value, flush: true);
    }
    if (await dir.exists()) await dir.delete(recursive: true);
    await staging.rename(dir.path);
    return InstalledExtension(manifest: manifest, dir: dir.path, enabled: true);
  }

  static String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

  /// Turns an extension on or off; off stops its script.
  Future<void> setEnabled(String id, bool on) async {
    await load();
    final ext = _installed[id];
    if (ext == null || ext.enabled == on) return;
    _installed[id] = ext.copyWith(enabled: on);
    if (!on) await _stop(id);
    await _save();
    notifyListeners();
  }

  /// Removes an extension and what it stored.
  Future<void> uninstall(String id) async {
    await load();
    final ext = _installed[id];
    if (ext == null || !_busy.add(id)) return;
    notifyListeners();
    try {
      await _stop(id);
      final dir = Directory(ext.dir);
      if (await dir.exists()) await dir.delete(recursive: true);
      final data = File(await _storagePath(id));
      if (await data.exists()) await data.delete();
      _installed.remove(id);
      _sources.remove(id);
      await _save();
    } finally {
      _busy.remove(id);
      notifyListeners();
    }
  }

  Future<String> _storagePath(String id) async => p.join((await _rootOf()).path, '.data', '$id.json');

  Future<ExtensionRunner> _runner(InstalledExtension ext) async =>
      _runners[ext.id] ??= _runnerFor(ext, await _storagePath(ext.id));

  Future<void> _stop(String id) async {
    await _runners.remove(id)?.dispose();
  }

  /// Asks one enabled extension for songs. A failing extension is stopped, so the next search starts it afresh.
  Future<List<ExtensionSearchHit>> search(String id, String query, {int limit = 20}) async {
    await load();
    final ext = _installed[id];
    if (ext == null || !ext.enabled) return const [];
    final runner = await _runner(ext);
    try {
      return await runner.search(query, limit: limit);
    } on ExtensionError {
      if (_runners[id] == runner) await _stop(id);
      rethrow;
    }
  }

  /// Stops every running extension.
  Future<void> stopAll() async {
    final all = List.of(_runners.keys);
    for (final id in all) {
      await _stop(id);
    }
  }

  /// Forgets what was read and loads again (tests).
  @visibleForTesting
  Future<void> reload() {
    _loading = null;
    return load();
  }
}

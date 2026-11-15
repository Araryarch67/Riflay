import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';
import '../platform/host.dart';
import 'private_files.dart';
import 'metadata.dart';
import 'ffmpeg.dart';

class SpotiflacError implements Exception {
  const SpotiflacError();
  @override
  String toString() => 'Extension request failed';
}

/// The upstream SpotiFLAC engine, isolated from Flutter behind a local pipe.
class Spotiflac extends ChangeNotifier {
  Spotiflac({this.executable, this.directory});
  static final instance = Spotiflac();
  static bool get supported => Host.isWindows;
  final String? executable;
  final Directory? directory;
  Process? _process;
  Future<void>? _starting;
  final _pending = <int, Completer<dynamic>>{};
  int _nextId = 0;
  bool _loaded = false;
  List<Map<String, dynamic>> plugins = [];
  String? selected;
  String registryUrl = '';
  bool localNetwork = false;
  final Map<String, String> qualities = {};

  List<Map<String, dynamic>> get searchProviders => [
    for (final plugin in plugins)
      if (plugin['enabled'] == true &&
          (plugin['has_metadata_provider'] == true ||
              plugin['search_behavior'] is Map && plugin['search_behavior']['enabled'] == true))
        plugin,
  ];

  Map<String, dynamic>? plugin(String id) => plugins.where((e) => e['id'] == id).firstOrNull;
  String nameOf(String id) => (plugin(id)?['display_name'] ?? id).toString();
  String get selectedName => selected == null ? 'SpotiFLAC' : nameOf(selected!);
  Future<Directory> _root() async => directory ?? Directory(p.join((await PrivateFiles.dir()).path, 'spotiflac'));

  Future<void> load() async {
    if (_loaded || !supported) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    selected = prefs.getString('spotiflac.selected');
    registryUrl = prefs.getString('spotiflac.registry') ?? '';
    localNetwork = prefs.getBool('spotiflac.localNetwork') ?? false;
    for (final key in prefs.getKeys().where((key) => key.startsWith('spotiflac.quality.'))) {
      final value = prefs.getString(key);
      if (value != null) qualities[key.substring('spotiflac.quality.'.length)] = value;
    }
    try {
      final installed = Directory(p.join((await _root()).path, 'extensions'));
      if (await installed.exists() && await installed.list().isEmpty == false) await refresh();
    } catch (_) {
      /* Opening the plugin manager offers a retry without breaking Search. */
    }
    notifyListeners();
  }

  Future<void> _start() => _starting ??= _spawn();
  Future<void> _spawn() async {
    final host = executable ?? p.join(File(Platform.resolvedExecutable).parent.path, 'spotiflac_bridge.exe');
    if (!await File(host).exists()) {
      _starting = null;
      throw const SpotiflacError();
    }
    final root = await _root();
    await root.create(recursive: true);
    final process = await Process.start(host, [root.path], runInShell: false);
    _process = process;
    process.stderr.drain<void>().ignore(); // Plugin logs can contain credentials; never forward them to the UI/log.
    process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      try {
        final response = jsonDecode(line) as Map;
        final done = _pending.remove(response['id']);
        if (done == null) return;
        if (response.containsKey('error')) {
          done.completeError(const SpotiflacError());
        } else {
          done.complete(response['result']);
        }
      } catch (_) {
        /* Only protocol replies are consumed. */
      }
    });
    process.exitCode.then((_) {
      if (_process != process) return;
      _process = null;
      _starting = null;
      for (final request in _pending.values) {
        if (!request.isCompleted) request.completeError(const SpotiflacError());
      }
      _pending.clear();
    });
  }

  Future<dynamic> call(
    String method, [
    Map<String, dynamic> params = const {},
    Duration timeout = const Duration(seconds: 60),
  ]) async {
    await _start();
    final id = ++_nextId;
    final request = Completer<dynamic>();
    _pending[id] = request;
    try {
      _process!.stdin.writeln(jsonEncode({'id': id, 'method': method, 'params': params}));
      return await request.future.timeout(timeout);
    } finally {
      _pending.remove(id);
    }
  }

  Future<void> refresh() async {
    await call('privateNetwork', {'enabled': localNetwork});
    final response = await call('list');
    plugins = response is List ? response.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];
    if (!searchProviders.any((e) => e['id'] == selected)) selected = searchProviders.firstOrNull?['id'] as String?;
    notifyListeners();
  }

  Future<void> choose(String id) async {
    if (!searchProviders.any((e) => e['id'] == id)) return;
    selected = id;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString('spotiflac.selected', id);
  }

  Future<void> install(String path) async {
    await call('install', {'path': path});
    await refresh();
  }

  Future<void> enable(String id, bool value) async {
    await call('enable', {'extension': id, 'enabled': value});
    await refresh();
  }

  Future<void> remove(String id) async {
    await call('remove', {'extension': id});
    await refresh();
  }

  Future<Map<String, dynamic>> settings(String id) async =>
      Map<String, dynamic>.from(await call('settings', {'extension': id}) as Map);
  Future<void> saveSettings(String id, Map<String, dynamic> values) async {
    await call('saveSettings', {'extension': id, 'settings': values});
    await refresh();
  }

  Future<List<Map<String, dynamic>>> registry(String url, {http.Client? client}) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw const SpotiflacError();
    }
    final response = await (client?.get(uri) ?? http.get(uri)).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200 || response.bodyBytes.length > 4 * 1024 * 1024) throw const SpotiflacError();
    final data = jsonDecode(response.body);
    if (data is! Map || data['extensions'] is! List) throw const SpotiflacError();
    registryUrl = uri.toString();
    await (await SharedPreferences.getInstance()).setString('spotiflac.registry', registryUrl);
    return (data['extensions'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> installFromRegistry(Map<String, dynamic> entry, {http.Client? client}) async {
    final uri = Uri.tryParse((entry['download_url'] ?? entry['downloadUrl'] ?? '').toString());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw const SpotiflacError();
    }
    final owned = client == null;
    final connection = client ?? http.Client();
    final temp = await Directory.systemTemp.createTemp('riflay-sflx-');
    try {
      final response = await connection.send(http.Request('GET', uri)).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) throw const SpotiflacError();
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(const Duration(seconds: 30))) {
        if (bytes.length + chunk.length > 32 * 1024 * 1024) throw const SpotiflacError();
        bytes.addAll(chunk);
      }
      final expected = entry['sha256'];
      if (expected is String && expected.isNotEmpty && sha256.convert(bytes).toString() != expected.toLowerCase()) {
        throw const SpotiflacError();
      }
      final file = await File(p.join(temp.path, 'package.sflx')).writeAsBytes(bytes, flush: true);
      await install(file.path);
    } finally {
      if (owned) connection.close();
      await temp.delete(recursive: true);
    }
  }

  Future<List<Track>> search(String query, {String? provider}) async {
    final id = provider ?? selected;
    if (id == null) return [];
    final response = await call('call', {
      'extension': id,
      'operation': 'search',
      'args': {'query': query, 'limit': 50},
    });
    final list = response is List
        ? response
        : response is Map
        ? response['tracks']
        : null;
    if (list is! List) throw const SpotiflacError();
    return [
      for (final raw in list)
        if (raw is Map && (raw['item_type'] == null || raw['item_type'] == 'track'))
          ?track(id, Map<String, dynamic>.from(raw)),
    ];
  }

  static Track? track(String provider, Map<String, dynamic> data) {
    final id = data['id']?.toString();
    final title = data['name'] ?? data['title'];
    if (id == null || title is! String || title.isEmpty) return null;
    final uri = Uri(scheme: 'spotiflac', host: provider, pathSegments: [id]);
    final duration = data['duration_ms'];
    return Track(
      id: 'sflx:$provider:${Uri.encodeComponent(id)}',
      uri: uri,
      sourceUrl: uri.toString(),
      title: title,
      artist: data['artists']?.toString() ?? Track.unknownArtist,
      album: data['album_name'] as String?,
      artworkUrl: (data['images'] ?? data['cover_url']) as String?,
      duration: duration is num && duration > 0 ? Duration(milliseconds: duration.toInt()) : null,
      tagged: true,
      extensionData: data,
    );
  }

  static String jobId(Track track) => 'sflx_${sha256.convert(utf8.encode(track.id))}';

  Future<Map<String, dynamic>> stream(Track track) async => Map<String, dynamic>.from(
    await call('call', {
      'extension': track.extensionId,
      'operation': 'stream',
      'args': {'track': track.uri.pathSegments.single, 'quality': qualityOf(track.extensionId!)},
    }) as Map,
  );

  String qualityOf(String id) {
    final quality = plugin(id)?['quality_options'];
    if (quality is List && quality.any((q) => q is Map && q['id'] == qualities[id])) return qualities[id]!;
    return quality is List && quality.isNotEmpty && quality.first is Map ? quality.first['id'].toString() : 'LOSSLESS';
  }

  Future<void> setQuality(String id, String value) async {
    qualities[id] = value;
    await (await SharedPreferences.getInstance()).setString('spotiflac.quality.$id', value);
  }

  Future<void> allowLocalNetwork(bool value) async {
    await call('privateNetwork', {'enabled': value});
    localNetwork = value;
    await (await SharedPreferences.getInstance()).setBool('spotiflac.localNetwork', value);
    notifyListeners();
  }

  Future<Track> download(
    Track source,
    Directory destination, {
    bool Function()? cancelled,
    void Function(double)? progress,
  }) async {
    await load();
    await refresh();
    await call('ffmpegExecutable', {'path': await Ffmpeg.executable()});
    final provider = source.extensionId!;
    final details = plugin(provider);
    final downloader = details?['has_download_provider'] == true
        ? provider
        : plugins.where((e) => e['enabled'] == true && e['has_download_provider'] == true).firstOrNull?['id']
              as String?;
    if (downloader == null) throw const SpotiflacError();
    final item = jobId(source);
    final data = source.extensionData ?? const <String, dynamic>{};
    final request = {
      'service': downloader,
      'source': provider,
      'spotify_id': source.uri.pathSegments.single,
      'track_name': source.title,
      'artist_name': source.artist,
      'album_name': source.album ?? '',
      'isrc': data['isrc'] ?? '',
      'cover_url': source.artworkUrl ?? '',
      'duration_ms': source.duration?.inMilliseconds ?? 0,
      'output_dir': destination.path,
      'filename_format': '{artist} - {title}',
      'item_id': item,
      'quality': qualityOf(downloader),
      'embed_metadata': true,
      'use_fallback': false,
    };
    var polling = false;
    var cancellationSent = false;
    final timer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (polling) return;
      polling = true;
      try {
        if (cancelled?.call() ?? false) {
          if (!cancellationSent) {
            cancellationSent = true;
            await call('cancel', {'item': item});
          }
        } else {
          final state = await call('progress');
          final items = state is Map ? state['items'] : null;
          final current = items is Map ? items[item] : null;
          if (current is Map && current['progress'] is num) {
            progress?.call((current['progress'] as num).toDouble());
          }
        }
      } catch (_) {
        /* The active request reports failures. */
      } finally {
        polling = false;
      }
    });
    try {
      final result = await call('download', {
        'directory': destination.path,
        'request': request,
      }, const Duration(minutes: 30));
      if (result is! Map || result['success'] != true || result['file_path'] is! String || (cancelled?.call() ?? false)) {
        throw const SpotiflacError();
      }
      final path = p.normalize(result['file_path']);
      if (!p.isWithin(p.normalize(destination.absolute.path), File(path).absolute.path) || !await File(path).exists()) {
        throw const SpotiflacError();
      }
      final edit = TagEdit(title: source.title, artist: source.artist, album: source.album)..comment = source.sourceUrl;
      try {
        await Metadata.tagFile(path, edit);
      } catch (_) {
        /* Upstream already tags formats its writer supports. */
      }
      final uri = Uri.file(path);
      return Track(
        id: uri.toString(),
        uri: uri,
        title: source.title,
        artist: source.artist,
        album: source.album,
        duration: source.duration,
        sourceUrl: source.sourceUrl,
        extensionData: source.extensionData,
        tagged: true,
        addedAt: DateTime.now().millisecondsSinceEpoch,
      );
    } finally {
      timer.cancel();
    }
  }

  Future<void> close() async {
    await _process?.stdin.close();
    _process?.kill();
    _process = null;
    _starting = null;
  }
}

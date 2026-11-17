import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'ytdlp.dart';

/// A bounded, persistent cache of original video bytes. mpv reads a loopback
/// range URL; seeks and later plays reuse complete chunks without downloading
/// the entire MV first or keeping it in RAM. Expiring stream URLs aren't saved.
class VideoStreamCache {
  VideoStreamCache({
    this.maxBytes = 384 << 20,
    this.chunkSize = 1 << 20,
    Future<Directory> Function()? directory,
    http.Client? client,
  }) : _directory = directory ?? _defaultDirectory,
       _client = client ?? http.Client();

  static final instance = VideoStreamCache();
  final int maxBytes;
  final int chunkSize;
  final Future<Directory> Function() _directory;
  final http.Client _client;
  Future<Directory>? _folder;
  Future<HttpServer>? _server;
  final _routes = <String, _VideoEntry>{};
  final _pending = <String, Future<Uint8List>>{};
  final _files = <String, ({int size, DateTime used})>{};
  Future<void> _writes = Future.value();
  int _bytes = 0;
  bool _closed = false;

  static Future<Directory> _defaultDirectory() async =>
      Directory('${(await getApplicationCacheDirectory()).path}/video-streams');

  Future<Directory> _initialize() async {
    final dir = await _directory();
    await dir.create(recursive: true);
    await for (final file in dir.list(followLinks: false)) {
      if (file is! File) continue;
      final name = file.uri.pathSegments.last;
      if (!RegExp(r'^[a-f0-9]{64}-\d+\.bin(?:\.part)?$').hasMatch(name)) continue;
      final stat = await file.stat();
      if (name.endsWith('.part') || DateTime.now().difference(stat.modified) > const Duration(days: 7)) {
        await file.delete();
      } else {
        _files[name] = (size: stat.size, used: stat.modified);
        _bytes += stat.size;
      }
    }
    await _makeRoom(dir, 0);
    return dir;
  }

  /// Falls back to the direct URL if storage, byte ranges, or stream length
  /// aren't available. Only fully validated chunks ever enter the cache.
  Future<Uri> open(String videoId, ResolvedVideo stream) async {
    if (_closed || !const {'http', 'https'}.contains(stream.url.scheme)) return stream.url;
    try {
      await (_folder ??= _initialize());
      var total = stream.size ?? int.tryParse(stream.url.queryParameters['clen'] ?? '');
      if (total == null || total <= 0) {
        total = (await _fetch(stream.url, 0, 1)).total;
      }
      if (total <= 0 || _closed) return stream.url;
      final query = stream.url.queryParameters;
      final format = stream.formatId ?? query['itag'];
      // Without a stable format identity the full URL is safer than sharing
      // cached bytes between two different encodes of the same resolution.
      final identity = format == null || query['lmt'] == null ? stream.url.toString() : [format, query['lmt'], total];
      final key = sha256
          .convert(utf8.encode(jsonEncode([videoId, identity, stream.height, stream.codec, chunkSize])))
          .toString();
      final entry = _VideoEntry(key, stream.url, total);
      await _chunk(entry, 0);
      if (_closed) return stream.url;
      final server = await (_server ??= () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen(_serve);
        return server;
      }());
      final token = List.generate(
        16,
        (_) => math.Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      _routes[token] = entry;
      while (_routes.length > 4) {
        _routes.remove(_routes.keys.first);
      }
      return Uri(scheme: 'http', host: '127.0.0.1', port: server.port, path: '/$token');
    } catch (e) {
      debugPrint('Video cache unavailable, streaming directly: $e');
      return stream.url;
    }
  }

  Future<Uint8List> _chunk(_VideoEntry entry, int index) {
    final name = '${entry.key}-$index.bin';
    return _pending[name] ??= _readOrFetch(entry, index, name).whenComplete(() {
      _pending.remove(name);
    });
  }

  Future<({int total, Uint8List bytes})> _fetch(Uri url, int from, int length, {int? total}) async {
    final abort = Completer<void>();
    final timer = Timer(const Duration(seconds: 15), abort.complete);
    try {
      final request = http.AbortableRequest('GET', url, abortTrigger: abort.future)
        ..headers['Range'] = 'bytes=$from-${from + length - 1}';
      final response = await _client.send(request);
      final match = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(response.headers['content-range'] ?? '');
      if (response.statusCode != HttpStatus.partialContent ||
          match == null ||
          int.parse(match[1]!) != from ||
          int.parse(match[2]!) != from + length - 1 ||
          total != null && int.parse(match[3]!) != total) {
        throw HttpException('Video range refused (${response.statusCode})');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.stream) {
        if (bytes.length + chunk.length > length) throw const HttpException('Video exceeds its range');
        bytes.add(chunk);
      }
      if (bytes.length != length) throw const HttpException('Incomplete video range');
      return (total: int.parse(match[3]!), bytes: bytes.takeBytes());
    } finally {
      timer.cancel();
      if (!abort.isCompleted) abort.complete();
    }
  }

  Future<Uint8List> _readOrFetch(_VideoEntry entry, int index, String name) async {
    final dir = await _folder!;
    final from = index * chunkSize, length = math.min(chunkSize, entry.total - index * chunkSize);
    final file = File('${dir.path}/$name');
    try {
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        if (bytes.length == length) {
          _files[name] = (size: length, used: DateTime.now());
          await file.setLastModified(DateTime.now());
          return bytes;
        }
        await file.delete();
        final old = _files.remove(name);
        _bytes -= old?.size ?? 0;
      }
    } on FileSystemException catch (e) {
      debugPrint('Video cache read: $e');
    }
    for (var attempt = 0; ; attempt++) {
      if (_closed) throw StateError('Video cache closed');
      try {
        final bytes = (await _fetch(entry.url, from, length, total: entry.total)).bytes;
        await (_writes = _writes.catchError((Object _) {}).then((_) async {
          if (_closed) return;
          try {
            await dir.create(recursive: true);
            if (!await _makeRoom(dir, length)) return;
            final part = File('${file.path}.part');
            await part.writeAsBytes(bytes, flush: true);
            await part.rename(file.path);
            final old = _files[name];
            _bytes += length - (old?.size ?? 0);
            _files[name] = (size: length, used: DateTime.now());
          } on FileSystemException catch (e) {
            debugPrint('Video cache write: $e');
          }
        }));
        return bytes;
      } catch (_) {
        if (attempt >= 2 || _closed) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 200 * (attempt + 1)));
      }
    }
  }

  Future<bool> _makeRoom(Directory dir, int incoming) async {
    final oldest = _files.keys.toList()..sort((a, b) => _files[a]!.used.compareTo(_files[b]!.used));
    for (final name in oldest) {
      if (_bytes + incoming <= maxBytes) break;
      if (_pending.containsKey(name)) continue;
      final file = File('${dir.path}/$name');
      if (await file.exists()) await file.delete();
      _bytes -= _files.remove(name)!.size;
    }
    return _bytes + incoming <= maxBytes;
  }

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    try {
      final entry = _routes[request.uri.pathSegments.singleOrNull];
      if (entry == null) {
        response.statusCode = HttpStatus.notFound;
      } else if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
      } else {
        final header = request.headers.value(HttpHeaders.rangeHeader);
        final range = parseRange(header, entry.total);
        response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
        if (range == null) {
          response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */${entry.total}');
        } else {
          response.statusCode = header == null ? HttpStatus.ok : HttpStatus.partialContent;
          response.headers.contentType = ContentType.binary;
          response.contentLength = range.$2 - range.$1;
          if (header != null) {
            response.headers.set(HttpHeaders.contentRangeHeader, 'bytes ${range.$1}-${range.$2 - 1}/${entry.total}');
          }
          if (request.method == 'GET') {
            for (var position = range.$1; position < range.$2;) {
              final index = position ~/ chunkSize;
              final bytes = await _chunk(entry, index);
              final end = math.min(range.$2, (index + 1) * chunkSize);
              if (end < range.$2) _chunk(entry, index + 1).ignore();
              response.add(Uint8List.sublistView(bytes, position % chunkSize, end - index * chunkSize));
              await response.flush();
              position = end;
            }
          }
        }
      }
      await response.close();
    } catch (e) {
      // A seek closes the old response. Its bounded in-flight chunk can finish
      // for the next reader; the rest of the old request stops here.
      if (e is! SocketException && e is! HttpException) debugPrint('Video cache stream: $e');
      try {
        await response.close();
      } catch (_) {}
    }
  }

  /// Inclusive HTTP range to an exclusive byte interval; malformed/multiple
  /// and unsatisfiable ranges return null instead of serving the wrong bytes.
  @visibleForTesting
  static (int, int)? parseRange(String? header, int total) {
    if (header == null) return (0, total);
    final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header);
    if (match == null || total <= 0) return null;
    if (match[1]!.isEmpty) {
      final suffix = int.tryParse(match[2]!) ?? 0;
      return suffix > 0 ? (math.max(0, total - suffix), total) : null;
    }
    final from = int.tryParse(match[1]!);
    final to = match[2]!.isEmpty ? total : math.min((int.tryParse(match[2]!) ?? -1) + 1, total);
    return from == null || from < 0 || from >= to ? null : (from, to);
  }

  /// Ends local serving and outstanding network work; complete disk chunks stay.
  Future<void> close() async {
    _closed = true;
    _client.close();
    await (await _server)?.close(force: true);
    await Future.wait(_pending.values.toList().map((future) => future.then<void>((_) {}, onError: (Object _) {})));
    await _writes;
    _routes.clear();
  }
}

class _VideoEntry {
  const _VideoEntry(this.key, this.url, this.total);
  final String key;
  final Uri url;
  final int total;
}

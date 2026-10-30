import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';

// The app's own player request and stream choice (see proxy.dart for why a file import).
// ignore: avoid_relative_lib_imports
import '../../../lib/platform/proxy_route.dart';
// ignore: avoid_relative_lib_imports
import '../../../lib/services/youtube_player_api.dart';
import 'proxy.dart' show RateLimiter;

/// A song's audio stream as YouTube's player API gave it.
class ResolvedStream {
  ResolvedStream(this.url, this.size, this.mimeType, this.expires);

  final Uri url;
  final int size;
  final String mimeType;
  final DateTime expires;
}

/// Looks songs' streams up with YouTube's player API, the way the app does. Keeps each answer until a few minutes
/// before its URL expires (so a song's many Range requests cost one lookup) and the visitor id for a few hours;
/// nothing else, and nothing about who asked.
class StreamResolver {
  StreamResolver(this._client, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final http.Client _client;
  final DateTime Function() _now;
  final _cache = <String, Future<ResolvedStream>>{};
  Future<String?>? _visitor;
  DateTime? _visitorAt;

  static const _cacheCap = 256;
  static const _visitorLife = Duration(hours: 6);
  static const _margin = Duration(minutes: 5);

  /// Whether [videoId]'s stream is known and fresh, so serving it asks YouTube for nothing but bytes.
  bool has(String videoId, {required bool aac}) => _cache.containsKey('$aac:$videoId');

  Future<ResolvedStream> resolve(String videoId, {required bool aac}) async {
    final key = '$aac:$videoId';
    final cached = _cache[key];
    if (cached != null) {
      try {
        final r = await cached;
        if (r.expires.subtract(_margin).isAfter(_now())) return r;
      } catch (_) {
        // Looked up again below.
      }
    }
    final future = _lookUp(videoId, aac: aac).catchError((Object _) => _lookUp(videoId, aac: aac, freshVisitor: true));
    _cache.remove(key);
    _cache[key] = future;
    future.then<void>((_) {}, onError: (Object _) => _cache.remove(key));
    while (_cache.length > _cacheCap) {
      _cache.remove(_cache.keys.first);
    }
    return future;
  }

  /// Forgets [videoId]'s stream (googlevideo refused its URL).
  void forget(String videoId) => _cache
    ..remove('true:$videoId')
    ..remove('false:$videoId');

  Future<ResolvedStream> _lookUp(String videoId, {required bool aac, bool freshVisitor = false}) async {
    final visitor = await _visitorId(fresh: freshVisitor);
    final res = await _client
        .post(
          YoutubePlayerApi.playerUrl,
          headers: YoutubePlayerApi.playerHeaders(visitor),
          body: jsonEncode(YoutubePlayerApi.playerBody(videoId, visitor)),
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw StateError('player ${res.statusCode}');
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (YoutubePlayerApi.unplayable(j) case final reason?) throw StateError(reason);
    final best = YoutubePlayerApi.pickBest(YoutubePlayerApi.adaptiveFormats(j), aacOnly: aac);
    if (best == null) throw StateError('no audio stream');
    final url = Uri.parse(best['url'] as String);
    final size =
        int.tryParse(best['contentLength'] as String? ?? '') ?? int.tryParse(url.queryParameters['clen'] ?? '');
    if (size == null) throw StateError('unknown size');
    final mime = (best['mimeType'] as String).split(';').first;
    return ResolvedStream(url, size, mime, YoutubePlayerApi.urlExpiry(url) ?? _now().add(const Duration(hours: 1)));
  }

  Future<String?> _visitorId({bool fresh = false}) {
    final stale = _visitorAt == null || _now().difference(_visitorAt!) > _visitorLife;
    if (fresh || stale || _visitor == null) {
      _visitorAt = _now();
      _visitor = () async {
        final res = await _client
            .post(
              YoutubePlayerApi.visitorUrl,
              headers: YoutubePlayerApi.visitorHeaders,
              body: jsonEncode(YoutubePlayerApi.visitorBody),
            )
            .timeout(const Duration(seconds: 10));
        return res.statusCode == 200 ? YoutubePlayerApi.visitorFrom(jsonDecode(res.body)) : null;
      }();
      _visitor!.then<void>((_) {}, onError: (Object _) => _visitor = null);
    }
    return _visitor!;
  }
}

/// googlevideo refuses very large single ranges, so a request is served as consecutive ranges of this size.
const audioChunk = 1 << 20;

/// Serves `/audio/<videoId>` (see `proxyAudioPrefix`): the song's audio with Range, fetched from googlevideo in
/// [audioChunk] pieces. A refused URL is looked up again once.
Handler audioHandler({
  required http.Client client,
  required StreamResolver resolver,
  required Map<String, String> cors,
  RateLimiter? limiter,
  required String? Function(Request) clientIp,
}) {
  return (Request request) async {
    final videoId = request.url.pathSegments.length == 2 ? request.url.pathSegments[1] : '';
    if (!isVideoId(videoId) || (request.method != 'GET' && request.method != 'HEAD')) {
      return Response.notFound('Not found', headers: cors);
    }
    final aac = request.url.queryParameters['aac'] == '1';
    // Only a lookup asks YouTube's API; the bytes of a song already looked up are not counted.
    if (!resolver.has(videoId, aac: aac)) {
      final ip = clientIp(request);
      if (limiter != null && ip != null && !limiter.take(ip)) {
        return Response(429, body: 'Too many requests', headers: {...cors, 'retry-after': '10'});
      }
    }
    final ResolvedStream stream;
    try {
      stream = await resolver.resolve(videoId, aac: aac);
    } catch (e) {
      stderr.writeln('riflay-proxy: stream lookup failed (${e.runtimeType})');
      return Response(502, body: 'Couldn\'t find this song\'s audio', headers: cors);
    }
    final range = parseRange(request.headers['range'], stream.size);
    if (range == null) {
      return Response(416, headers: {...cors, 'content-range': 'bytes */${stream.size}'});
    }
    final (from, to) = range;
    final headers = {
      ...cors,
      'content-type': stream.mimeType,
      'accept-ranges': 'bytes',
      'content-length': '${to - from}',
      'cache-control': 'no-store',
      if (request.headers['range'] != null) 'content-range': 'bytes $from-${to - 1}/${stream.size}',
    };
    final status = request.headers['range'] != null ? 206 : 200;
    if (request.method == 'HEAD') return Response(status, headers: headers);
    return Response(
      status,
      headers: headers,
      body: _bytes(client, resolver, videoId, aac, stream, from, to),
      context: {'shelf.io.buffer_output': false},
    );
  };
}

/// The byte range a `Range` header asks for, as [from, to) within [size]: all of it without one, null when it
/// can't be served.
(int, int)? parseRange(String? header, int size) {
  if (header == null) return (0, size);
  final m = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header.trim());
  if (m == null) return null;
  final a = m.group(1)!, b = m.group(2)!;
  if (a.isEmpty && b.isEmpty) return null;
  if (a.isEmpty) {
    final n = int.parse(b);
    return n == 0 ? null : (size - n < 0 ? 0 : size - n, size);
  }
  final from = int.parse(a);
  final to = b.isEmpty ? size : (int.parse(b) + 1 > size ? size : int.parse(b) + 1);
  return from >= size || to <= from ? null : (from, to);
}

Stream<List<int>> _bytes(
  http.Client client,
  StreamResolver resolver,
  String videoId,
  bool aac,
  ResolvedStream first,
  int from,
  int to,
) async* {
  var stream = first;
  var retried = false;
  var pos = from;
  while (pos < to) {
    final last = (pos + audioChunk < to ? pos + audioChunk : to) - 1;
    final req = http.Request('GET', stream.url)
      ..headers['range'] = 'bytes=$pos-$last'
      ..headers['user-agent'] = YoutubePlayerApi.userAgent;
    final res = await client.send(req);
    if (res.statusCode != 200 && res.statusCode != 206) {
      await res.stream.drain<void>();
      // Usually an expired or throttled URL: look it up afresh, once.
      if (retried) throw HttpException('googlevideo ${res.statusCode}');
      retried = true;
      resolver.forget(videoId);
      stream = await resolver.resolve(videoId, aac: aac);
      continue;
    }
    await for (final bytes in res.stream) {
      yield bytes;
      pos += bytes.length;
    }
    pos = last + 1;
  }
}

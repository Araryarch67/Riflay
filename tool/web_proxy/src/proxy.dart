import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';

import 'audio.dart';

// The app's own routing rules, so the two never disagree about what is forwarded. A file import rather than a
// package one: the app is a Flutter package, which a plain Dart server cannot depend on.
// ignore: avoid_relative_lib_imports
import '../../../lib/platform/proxy_route.dart';

// ignore: avoid_relative_lib_imports
export '../../../lib/platform/proxy_route.dart' show proxyAudioPrefix, proxyFetchPrefix;
export 'audio.dart' show StreamResolver;

/// A desktop browser, for services that answer differently (or not at all) without one.
const defaultUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';

/// The largest request body forwarded (InnerTube's are a few kilobytes).
const maxRequestBody = 256 << 10;

/// Forwards `/fetch/<host>/<path>` to `https://<host>/<path>` for the hosts in `proxy_route.dart`, serves
/// `/audio/<videoId>` (see `audio.dart`), and answers the browser's CORS checks. Keeps nothing between requests but
/// [limiter]'s counters and [resolver]'s stream URLs, and logs nothing about them.
///
/// [allowOrigin] is the page origin allowed to call it (`*` for any). [clientIp] says who a request comes from for
/// the rate limit (the socket's address by default).
Handler proxyHandler({
  required http.Client client,
  RateLimiter? limiter,
  StreamResolver? resolver,
  String allowOrigin = '*',
  String? Function(Request request)? clientIp,
}) {
  final cors = {
    'access-control-allow-origin': allowOrigin,
    'access-control-expose-headers': 'content-length, content-range, accept-ranges',
    if (allowOrigin != '*') 'vary': 'origin',
  };
  final who = clientIp ?? _socketAddress;
  final audio = audioHandler(
    client: client,
    resolver: resolver ?? StreamResolver(client),
    cors: cors,
    limiter: limiter,
    clientIp: who,
  );

  return (Request request) async {
    final path = '/${request.url.path}';
    final isAudio = path.startsWith(proxyAudioPrefix);
    if (!isAudio && !path.startsWith(proxyFetchPrefix)) return Response.notFound('Not found', headers: cors);
    if (request.method == 'OPTIONS') {
      return Response(
        204,
        headers: {
          ...cors,
          'access-control-allow-methods': 'GET, HEAD, POST, OPTIONS',
          'access-control-allow-headers': request.headers['access-control-request-headers'] ?? '*',
          'access-control-max-age': '86400',
        },
      );
    }
    if (isAudio) return audio(request);
    final target = fromProxy(request.method, path, request.url.query);
    if (target == null) return Response.forbidden('Not forwarded', headers: cors);
    final service = serviceOf(target.host)!;
    // Streams and covers come in many small requests while a song plays; the limit is for API calls.
    if (service == ProxiedService.youtube || service == ProxiedService.lyrics) {
      final ip = who(request);
      if (limiter != null && ip != null && !limiter.take(ip)) {
        return Response(429, body: 'Too many requests', headers: {...cors, 'retry-after': '10'});
      }
    }

    final body = await _readLimited(request);
    if (body == null) return Response(413, body: 'Request too large', headers: cors);
    final out = http.Request(request.method, target)
      ..followRedirects = true
      ..maxRedirects = 5
      ..bodyBytes = body;
    out.headers.addAll(upstreamHeaders(request.headers, target));

    final http.StreamedResponse res;
    try {
      res = await client.send(out).timeout(const Duration(seconds: 30));
    } catch (e) {
      // The error's type only: its message carries the URL, which says what someone listens to.
      stderr.writeln('riflay-proxy: upstream failed (${e.runtimeType})');
      return Response(502, body: 'Service unavailable', headers: cors);
    }
    return Response(
      res.statusCode,
      body: request.method == 'HEAD' ? null : res.stream,
      headers: {...responseHeaders(res.headers, service), ...cors},
      context: {'shelf.io.buffer_output': false},
    );
  };
}

/// The headers sent to [target]: the forwarded ones, the renamed ones under their own name, and a browser's
/// User-Agent, Origin and Referer where the app sent none.
Map<String, String> upstreamHeaders(Map<String, String> incoming, Uri target) {
  final out = <String, String>{};
  incoming.forEach((name, value) {
    final lower = name.toLowerCase();
    if (forwardedRequestHeaders.contains(lower)) {
      out[lower] = value;
    } else if (lower.startsWith(renamedHeaderPrefix)) {
      final real = lower.substring(renamedHeaderPrefix.length);
      if (renamedRequestHeaders.contains(real)) out[real] = value;
    }
  });
  out.putIfAbsent('user-agent', () => defaultUserAgent);
  if (serviceOf(target.host) == ProxiedService.youtube) {
    out.putIfAbsent('origin', () => 'https://${target.host}');
    out.putIfAbsent('referer', () => 'https://${target.host}/');
  }
  return out;
}

/// The service's response headers the browser gets.
Map<String, String> responseHeaders(Map<String, String> upstream, ProxiedService service) {
  final out = <String, String>{};
  upstream.forEach((name, value) {
    final lower = name.toLowerCase();
    if (!forwardedResponseHeaders.contains(lower)) return;
    // dart:io unpacks gzip, so a compressed length would be wrong; streams are never compressed.
    if (lower == 'content-length' && service != ProxiedService.media && service != ProxiedService.image) return;
    out[lower] = value;
  });
  return out;
}

Future<List<int>?> _readLimited(Request request) async {
  final bytes = <int>[];
  await for (final chunk in request.read()) {
    bytes.addAll(chunk);
    if (bytes.length > maxRequestBody) return null;
  }
  return bytes;
}

String? _socketAddress(Request request) =>
    (request.context['shelf.io.connection_info'] as HttpConnectionInfo?)?.remoteAddress.address;

/// A token bucket per client: [burst] requests at once, refilled at [perMinute]. Forgets clients that went quiet,
/// so it holds no more than the last few minutes' addresses.
class RateLimiter {
  RateLimiter({this.perMinute = 120, this.burst = 40, DateTime Function()? now}) : _now = now ?? DateTime.now;

  final int perMinute;
  final int burst;
  final DateTime Function() _now;
  final _buckets = <String, ({double tokens, DateTime at})>{};

  /// Takes one request's token for [client]; false when it has none left.
  bool take(String client) {
    final now = _now();
    if (_buckets.length > 10000) _buckets.removeWhere((_, b) => now.difference(b.at) > const Duration(minutes: 5));
    final b = _buckets[client];
    var tokens = burst.toDouble();
    if (b != null) {
      final refill = now.difference(b.at).inMilliseconds * perMinute / 60000;
      tokens = (b.tokens + refill).clamp(0, burst.toDouble());
    }
    if (tokens < 1) {
      _buckets[client] = (tokens: tokens, at: now);
      return false;
    }
    _buckets[client] = (tokens: tokens - 1, at: now);
    return true;
  }
}

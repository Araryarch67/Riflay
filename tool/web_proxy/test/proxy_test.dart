import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../src/audio.dart';
import '../src/proxy.dart';

Request _req(String method, String path, {Map<String, String>? headers, Object? body}) =>
    Request(method, Uri.parse('http://proxy.test$path'), headers: headers, body: body);

void main() {
  group('/fetch', () {
    test('forwards an InnerTube call with its body, restoring the renamed headers', () async {
      late http.Request seen;
      final handler = proxyHandler(
        client: MockClient((r) async {
          seen = r;
          return http.Response(
            '{"contents":{}}',
            200,
            headers: {'content-type': 'application/json', 'set-cookie': 'a=b'},
          );
        }),
      );
      final res = await handler(
        _req(
          'POST',
          '/fetch/music.youtube.com/youtubei/v1/search?prettyPrint=false',
          headers: {
            'content-type': 'application/json',
            'x-riflay-user-agent': 'Riflay test',
            'x-goog-visitor-id': 'v1',
            'authorization': 'never sent',
            'x-riflay-host': 'never sent either',
          },
          body: '{"query":"daft punk"}',
        ),
      );
      expect(res.statusCode, 200);
      expect(await res.readAsString(), '{"contents":{}}');
      expect(res.headers['access-control-allow-origin'], '*');
      expect(res.headers['set-cookie'], isNull);
      expect(seen.url.toString(), 'https://music.youtube.com/youtubei/v1/search?prettyPrint=false');
      expect(seen.method, 'POST');
      expect(seen.body, '{"query":"daft punk"}');
      expect(seen.headers['user-agent'], 'Riflay test');
      expect(seen.headers['x-goog-visitor-id'], 'v1');
      expect(seen.headers['origin'], 'https://music.youtube.com');
      expect(seen.headers.containsKey('authorization'), isFalse);
      expect(seen.headers.containsKey('host'), isFalse);
    });

    test('passes Range through to googlevideo and the 206 back', () async {
      late http.Request seen;
      final handler = proxyHandler(
        client: MockClient((r) async {
          seen = r;
          return http.Response.bytes(
            List.filled(100, 7),
            206,
            headers: {
              'content-type': 'audio/webm',
              'content-length': '100',
              'content-range': 'bytes 100-199/5000',
              'accept-ranges': 'bytes',
            },
          );
        }),
      );
      final res = await handler(
        _req('GET', '/fetch/rr1---sn-abc.googlevideo.com/videoplayback?id=1', headers: {'range': 'bytes=100-199'}),
      );
      expect(seen.headers['range'], 'bytes=100-199');
      expect(res.statusCode, 206);
      expect(res.headers['content-range'], 'bytes 100-199/5000');
      expect(res.headers['content-length'], '100');
      expect((await res.read().expand((b) => b).toList()).length, 100);
    });

    test('refuses what it does not forward and answers CORS preflights', () async {
      final handler = proxyHandler(client: MockClient((r) async => fail('nothing should be sent')));
      expect((await handler(_req('GET', '/fetch/example.com/'))).statusCode, 403);
      expect((await handler(_req('GET', '/fetch/music.youtube.com/youtubei/v1/search'))).statusCode, 403);
      expect((await handler(_req('GET', '/elsewhere'))).statusCode, 404);
      final pre = await handler(
        _req(
          'OPTIONS',
          '/fetch/music.youtube.com/youtubei/v1/search',
          headers: {'access-control-request-headers': 'content-type'},
        ),
      );
      expect(pre.statusCode, 204);
      expect(pre.headers['access-control-allow-headers'], 'content-type');
      expect(pre.headers['access-control-allow-methods'], contains('POST'));
    });

    test('a client over its rate gets 429, others are unaffected', () async {
      var now = DateTime(2026);
      final limiter = RateLimiter(perMinute: 60, burst: 2, now: () => now);
      final handler = proxyHandler(
        client: MockClient((r) async => http.Response('{}', 200)),
        limiter: limiter,
        clientIp: (r) => r.headers['x-test-ip'],
      );
      Future<int> call(String ip) async =>
          (await handler(_req('GET', '/fetch/lrclib.net/api/get?q=a', headers: {'x-test-ip': ip}))).statusCode;
      expect([await call('a'), await call('a'), await call('a')], [200, 200, 429]);
      expect(await call('b'), 200);
      now = now.add(const Duration(seconds: 1)); // one token back at 60 a minute
      expect(await call('a'), 200);
    });

    test('an unreachable service is a calm 502', () async {
      final handler = proxyHandler(client: MockClient((r) async => throw http.ClientException('down', r.url)));
      final res = await handler(_req('GET', '/fetch/lrclib.net/api/get'));
      expect(res.statusCode, 502);
      expect(await res.readAsString(), 'Service unavailable');
    });
  });

  group('/audio', () {
    // A fake song a little over two chunks long, so ranges cross chunk boundaries.
    final song = Uint8List.fromList(List.generate(2 * audioChunk + 1000, (i) => i % 251));
    late int playerCalls;
    late List<String> ranges;
    late int refuseNext;

    http.Client youtube() => MockClient((r) async {
      if (r.url.path == '/youtubei/v1/visitor_id') {
        return http.Response(
          jsonEncode({
            'responseContext': {'visitorData': 'visitor'},
          }),
          200,
        );
      }
      if (r.url.path == '/youtubei/v1/player') {
        playerCalls++;
        expect((jsonDecode(r.body) as Map)['videoId'], 'dQw4w9WgXcQ');
        return http.Response(
          jsonEncode({
            'playabilityStatus': {'status': 'OK'},
            'streamingData': {
              'adaptiveFormats': [
                {
                  'itag': 251,
                  'mimeType': 'audio/webm; codecs="opus"',
                  'averageBitrate': 130000,
                  'contentLength': '${song.length}',
                  'url':
                      'https://rr1---sn-abc.googlevideo.com/videoplayback?expire=${DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600}&n=$playerCalls',
                },
              ],
            },
          }),
          200,
        );
      }
      if (r.url.host.endsWith('.googlevideo.com')) {
        if (refuseNext > 0) {
          refuseNext--;
          return http.Response('', 403);
        }
        final m = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(r.headers['range']!)!;
        ranges.add(r.headers['range']!);
        final from = int.parse(m[1]!), to = int.parse(m[2]!) + 1;
        return http.Response.bytes(song.sublist(from, to), 206);
      }
      return http.Response('', 404);
    });

    setUp(() {
      playerCalls = 0;
      ranges = [];
      refuseNext = 0;
    });

    Future<Uint8List> bytesOf(Response res) async => Uint8List.fromList(await res.read().expand((b) => b).toList());

    test('serves a range across chunks with one lookup', () async {
      final handler = proxyHandler(client: youtube());
      final from = audioChunk - 10, to = audioChunk + 20;
      final res = await handler(_req('GET', '/audio/dQw4w9WgXcQ', headers: {'range': 'bytes=$from-${to - 1}'}));
      expect(res.statusCode, 206);
      expect(res.headers['content-type'], 'audio/webm');
      expect(res.headers['content-range'], 'bytes $from-${to - 1}/${song.length}');
      expect(res.headers['content-length'], '${to - from}');
      expect(await bytesOf(res), song.sublist(from, to));
      // Only what was asked for: a range shorter than a chunk is one request to googlevideo.
      expect(ranges, ['bytes=$from-${to - 1}']);

      // The browser's next request reuses the lookup.
      final rest = await handler(_req('GET', '/audio/dQw4w9WgXcQ', headers: {'range': 'bytes=${song.length - 5}-'}));
      expect(await bytesOf(rest), song.sublist(song.length - 5));
      expect(playerCalls, 1);
    });

    test('the whole song without a Range, in chunks', () async {
      final handler = proxyHandler(client: youtube());
      final res = await handler(_req('GET', '/audio/dQw4w9WgXcQ'));
      expect(res.statusCode, 200);
      expect(res.headers['content-range'], isNull);
      expect(await bytesOf(res), song);
      expect(ranges, hasLength(3));
    });

    test('a refused URL is looked up again once', () async {
      final handler = proxyHandler(client: youtube());
      refuseNext = 1;
      final res = await handler(_req('GET', '/audio/dQw4w9WgXcQ', headers: {'range': 'bytes=0-99'}));
      expect(await bytesOf(res), song.sublist(0, 100));
      expect(playerCalls, 2);
    });

    test('bad ids and unsatisfiable ranges are refused', () async {
      final handler = proxyHandler(client: youtube());
      expect((await handler(_req('GET', '/audio/nope'))).statusCode, 404);
      expect((await handler(_req('POST', '/audio/dQw4w9WgXcQ'))).statusCode, 404);
      final res = await handler(_req('GET', '/audio/dQw4w9WgXcQ', headers: {'range': 'bytes=${song.length}-'}));
      expect(res.statusCode, 416);
      expect(res.headers['content-range'], 'bytes */${song.length}');
    });
  });

  test('parseRange', () {
    expect(parseRange(null, 100), (0, 100));
    expect(parseRange('bytes=0-', 100), (0, 100));
    expect(parseRange('bytes=10-19', 100), (10, 20));
    expect(parseRange('bytes=90-500', 100), (90, 100));
    expect(parseRange('bytes=-30', 100), (70, 100));
    expect(parseRange('bytes=100-', 100), isNull);
    expect(parseRange('bytes=5-1', 100), isNull);
    expect(parseRange('bytes=0-1,5-6', 100), isNull);
    expect(parseRange('items=0-1', 100), isNull);
  });
}

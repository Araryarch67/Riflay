import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riflay/services/youtube_audio_source.dart';
import 'package:riflay/services/ytdlp.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (_) async => Directory.systemTemp.path,
  );
  var id = 0;
  YoutubeAudioSource source(int size, http.Client client) {
    final yt = YoutubeExplode();
    addTearDown(yt.close);
    addTearDown(client.close);
    return YoutubeAudioSource(
      'range-test-${id++}',
      yt: yt,
      client: client,
      cacheAudio: false,
      resolveAudio: () async => ResolvedAudio(
        url: Uri.parse('https://audio.example/song'),
        formatId: '251',
        ext: 'webm',
        codec: 'opus',
        kbps: 128,
        size: size,
        resolvedAt: DateTime.now(),
        via: 'test',
      ),
    );
  }

  Future<List<int>> read(YoutubeAudioSource audio, [int? start, int? end]) async {
    final response = await audio.request(start, end);
    final out = <int>[];
    await for (final bytes in response.stream) {
      out.addAll(bytes);
    }
    expect(out.length, response.contentLength, reason: 'the proxy must receive all promised bytes');
    return out;
  }

  test('a complete disk cache replays offline in bounded chunks without another download', () async {
    const size = 2 << 20;
    const chunkSize = 64 << 10;
    var requests = 0;
    var offline = false;
    final yt = YoutubeExplode();
    final client = MockClient.streaming((request, _) async {
      if (offline) throw const SocketException('airplane mode');
      requests++;
      final range = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(request.headers['Range']!)!;
      final from = int.parse(range[1]!), to = int.parse(range[2]!);
      final chunk = Uint8List(chunkSize)..fillRange(0, chunkSize, 42);
      return http.StreamedResponse(
        Stream.fromIterable(Iterable.generate((to + 1 - from) ~/ chunkSize, (_) => chunk)),
        206,
        headers: {'content-range': 'bytes $from-$to/$size'},
      );
    });
    addTearDown(yt.close);
    addTearDown(client.close);
    addTearDown(YoutubeAudioSource.clearCache);
    const key = 'offline-disk-memory-test';
    YoutubeAudioSource.retainCache({key});
    final audio = YoutubeAudioSource(
      key,
      yt: yt,
      client: client,
      resolveAudio: () async => ResolvedAudio(
        url: Uri.parse('https://audio.example/song'),
        formatId: '251',
        ext: 'webm',
        codec: 'opus',
        kbps: 128,
        size: size,
        resolvedAt: DateTime.now(),
        via: 'test',
      ),
    );
    var bytesRead = 0;
    await for (final bytes in (await audio.request()).stream) {
      expect(bytes.length, lessThanOrEqualTo(chunkSize));
      bytesRead += bytes.length;
    }
    expect(bytesRead, size);
    expect(YoutubeAudioSource.cacheCompleteFor(key), isTrue);
    final downloaded = requests;
    offline = true;
    bytesRead = 0;
    await for (final bytes in (await audio.request(size ~/ 2, size)).stream) {
      expect(bytes.length, lessThanOrEqualTo(chunkSize));
      expect(bytes, everyElement(42));
      bytesRead += bytes.length;
    }
    expect(bytesRead, size ~/ 2);
    expect(requests, downloaded);
  });

  test('a short successful response resumes from the last delivered byte', () async {
    final data = List<int>.generate(1000, (i) => i % 251);
    final ranges = <String>[];
    final client = MockClient((request) async {
      final range = request.headers['Range']!;
      ranges.add(range);
      final from = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)![1]!);
      final to = from == 0 ? 99 : data.length - 1;
      return http.Response.bytes(
        data.sublist(from, to + 1),
        206,
        headers: {'content-range': 'bytes $from-$to/${data.length}'},
      );
    });
    final received = await read(source(data.length, client));
    expect(received, data);
    expect(ranges, ['bytes=0-999', 'bytes=100-999']);
  });

  test('a server ignoring Range cannot duplicate the start after a seek', () async {
    final data = List<int>.generate(1000, (i) => i % 251);
    final client = MockClient((_) async => http.Response.bytes(data, 200));
    expect(await read(source(data.length, client), 500, 800), data.sublist(500, 800));
  });

  test('a connection error resumes without losing or duplicating bytes', () async {
    final data = List<int>.generate(1000, (i) => i % 251);
    final ranges = <String>[];
    final client = MockClient.streaming((request, body) async {
      ranges.add(request.headers['Range']!);
      final from = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(request.headers['Range']!)![1]!);
      Stream<List<int>> chunks() async* {
        if (from == 0) {
          yield data.sublist(0, 123);
          throw const SocketException('connection lost');
        }
        yield data.sublist(from);
      }

      return http.StreamedResponse(chunks(), 206, headers: {'content-range': 'bytes $from-999/1000'});
    });
    expect(await read(source(data.length, client)), data);
    expect(ranges, ['bytes=0-999', 'bytes=123-999']);
  });

  test('repeated disconnects that make progress still deliver the whole song', () async {
    final data = List<int>.generate(500, (i) => i % 251);
    final client = MockClient.streaming((request, body) async {
      final from = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(request.headers['Range']!)![1]!);
      Stream<List<int>> chunks() async* {
        yield data.sublist(from, (from + 100).clamp(0, data.length));
        throw const SocketException('connection lost');
      }

      return http.StreamedResponse(chunks(), 206, headers: {'content-range': 'bytes $from-499/500'});
    });
    expect(await read(source(data.length, client)), data);
  });

  test('an empty response retries the same position instead of ending the song', () async {
    final ranges = <String>[];
    final client = MockClient((request) async {
      ranges.add(request.headers['Range']!);
      return http.Response.bytes(
        ranges.length == 1 ? <int>[] : [10, 20, 30],
        206,
        headers: {'content-range': 'bytes 0-2/3'},
      );
    });
    expect(await read(source(3, client)), [10, 20, 30]);
    expect(ranges, ['bytes=0-2', 'bytes=0-2']);
  });

  test('a temporary server error retries without dropping the current chunk', () async {
    var requests = 0;
    final client = MockClient((request) async {
      if (++requests == 1) return http.Response('Temporarily unavailable', 503);
      return http.Response.bytes([1, 2, 3], 206, headers: {'content-range': 'bytes 0-2/3'});
    });
    expect(await read(source(3, client)), [1, 2, 3]);
    expect(requests, 2);
  });

  test('a permanently rejected refreshed URL fails promptly instead of buffering forever', () async {
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return http.Response('Forbidden', 403);
    });
    final response = await source(100, client).request();
    await expectLater(
      response.stream.toList().timeout(const Duration(seconds: 2)),
      throwsA(isA<http.ClientException>().having((e) => e.message, 'reason', contains('HTTP 403'))),
    );
    expect(requests, 2, reason: 'refresh the URL once, then report the refusal');
  });

  test('a mismatched partial range never gets appended to the song', () async {
    final client = MockClient(
      (_) async => http.Response.bytes([1, 2, 3], 206, headers: {'content-range': 'bytes 0-2/100'}),
    );
    final response = await source(100, client).request(50, 53);
    await expectLater(response.stream.toList(), throwsA(isA<HttpException>()));
  });

  test('multi-chunk streams deliver an exact byte-for-byte copy through the last byte', () async {
    final data = Uint8List.fromList(List<int>.generate((1 << 20) + 1337, (i) => i % 251));
    final client = MockClient((request) async {
      final match = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(request.headers['Range']!)!;
      final from = int.parse(match[1]!);
      final requestedEnd = int.parse(match[2]!);
      final to = (from + 65535).clamp(from, requestedEnd);
      return http.Response.bytes(
        data.sublist(from, to + 1),
        206,
        headers: {'content-range': 'bytes $from-$to/${data.length}'},
      );
    });
    final received = await read(source(data.length, client));
    expect(sha256.convert(received), sha256.convert(data));
  });
}

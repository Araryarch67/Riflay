import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riflay/services/video_stream_cache.dart';
import 'package:riflay/services/ytdlp.dart';

void main() {
  late Directory folder;
  late VideoStreamCache cache;
  late HttpClient reader;
  late List<int> data;
  late List<String> requests;
  var rejectRanges = false;
  var truncate = false;
  var wrongRange = false;

  http.Client upstream() => MockClient((request) async {
    final header = request.headers['Range']!;
    requests.add(header);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final range = VideoStreamCache.parseRange(header, data.length)!;
    return http.Response.bytes(
      truncate ? data.sublist(range.$1, range.$2 - 1) : data.sublist(range.$1, range.$2),
      rejectRanges ? 200 : 206,
      headers: {'content-range': 'bytes ${wrongRange ? 1 : range.$1}-${range.$2 - 1}/${data.length}'},
    );
  });

  ResolvedVideo stream({String token = 'first', String format = '137', int? size}) => ResolvedVideo(
    url: Uri.parse('https://video.example/media?itag=$format&lmt=123&token=$token'),
    height: 1080,
    codec: 'avc1',
    size: size ?? data.length,
    formatId: format,
  );

  Future<({int status, List<int> bytes, HttpHeaders headers})> read(Uri url, [String? range]) async {
    final request = await reader.getUrl(url);
    if (range != null) request.headers.set(HttpHeaders.rangeHeader, range);
    final response = await request.close();
    final bytes = await response.fold<List<int>>([], (all, chunk) => all..addAll(chunk));
    return (status: response.statusCode, bytes: bytes, headers: response.headers);
  }

  setUp(() async {
    folder = await Directory.systemTemp.createTemp('riflay-video-cache-test-');
    reader = HttpClient();
    data = List.generate(127, (i) => i);
    requests = [];
    rejectRanges = truncate = wrongRange = false;
    cache = VideoStreamCache(directory: () async => folder, client: upstream(), chunkSize: 16, maxBytes: 256);
  });
  tearDown(() async {
    reader.close(force: true);
    await cache.close();
    await folder.delete(recursive: true);
  });

  test('full playback caches original bytes and a seek reuses them without upstream traffic', () async {
    final url = await cache.open('mv', stream());
    expect(url.host, '127.0.0.1');
    expect((await read(url)).bytes, data);
    final coldRequests = requests.length;
    final seek = await read(url, 'bytes=23-74');
    expect(seek.status, 206);
    expect(seek.bytes, data.sublist(23, 75));
    expect(seek.headers.value(HttpHeaders.contentRangeHeader), 'bytes 23-74/127');
    expect(requests.length, coldRequests, reason: 'cached seeks make zero upstream requests');
    expect(coldRequests, 8, reason: 'one request per chunk, including prefetch');
  });

  test('complete chunks survive restart and signed URL refresh without mixing formats', () async {
    final url = await cache.open('mv', stream());
    await read(url);
    await cache.close();
    cache = VideoStreamCache(directory: () async => folder, client: upstream(), chunkSize: 16, maxBytes: 256);
    final before = requests.length;
    final reopened = await cache.open('mv', stream(token: 'refreshed'));
    expect((await read(reopened)).bytes, data);
    expect(requests.length, before);
    await cache.open('mv', stream(format: '136'));
    expect(requests.length, before + 1);
  });

  test('concurrent readers coalesce a missing chunk', () async {
    final url = await cache.open('mv', stream());
    final reads = await Future.wait([read(url, 'bytes=32-47'), read(url, 'bytes=32-47')]);
    expect(reads.every((r) => r.bytes.join(',') == data.sublist(32, 48).join(',')), isTrue);
    expect(requests.where((r) => r == 'bytes=32-47'), hasLength(1));
  });

  test('suffix, HEAD and invalid ranges follow HTTP semantics', () async {
    final url = await cache.open('mv', stream());
    expect((await read(url, 'bytes=-10')).bytes, data.sublist(117));
    final request = await reader.headUrl(url);
    final response = await request.close();
    expect(response.contentLength, data.length);
    expect(await response.fold<int>(0, (n, chunk) => n + chunk.length), 0);
    for (final range in ['bytes=999-', 'bytes=5-2', 'bytes=0-1,3-4', 'bytes=-0']) {
      final result = await read(url, range);
      expect(result.status, 416);
      expect(result.headers.value(HttpHeaders.contentRangeHeader), 'bytes */127');
    }
  });

  test('LRU eviction keeps the disk budget bounded', () async {
    await cache.close();
    cache = VideoStreamCache(directory: () async => folder, client: upstream(), chunkSize: 16, maxBytes: 32);
    final url = await cache.open('mv', stream());
    expect((await read(url)).bytes, data);
    final files = await folder.list().where((f) => f.path.endsWith('.bin')).cast<File>().toList();
    final sizes = await Future.wait(files.map((f) => f.length()));
    expect(sizes.fold<int>(0, (sum, size) => sum + size), lessThanOrEqualTo(32));
    expect((await read(url, 'bytes=0-15')).bytes, data.sublist(0, 16));
  });

  test('partial, wrong-range and range-ignoring responses are never cached', () async {
    for (var i = 0; i < 3; i++) {
      truncate = i == 0;
      wrongRange = i == 1;
      rejectRanges = i == 2;
      final input = stream(token: 'invalid-$i');
      expect(await cache.open('mv-$i', input), input.url);
      expect(await folder.list().toList(), isEmpty);
    }
  });

  test('a corrupt cached chunk is fetched again', () async {
    await cache.open('mv', stream());
    final file = (await folder.list().cast<File>().toList()).single;
    await file.writeAsBytes([1]);
    final url = await cache.open('mv', stream());
    expect((await read(url, 'bytes=0-15')).bytes, data.sublist(0, 16));
    expect(requests.where((r) => r == 'bytes=0-15'), hasLength(2));
  });

  test('unavailable storage falls back to direct streaming', () async {
    await cache.close();
    cache = VideoStreamCache(directory: () async => throw const FileSystemException('unavailable'), client: upstream());
    final input = stream();
    expect(await cache.open('mv', input), input.url);
    expect(requests, isEmpty);
  });
}

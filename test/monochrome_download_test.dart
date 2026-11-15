import 'dart:convert';
import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riflay/services/download_files.dart';
import 'package:riflay/services/library_views.dart';
import 'package:riflay/services/monochrome.dart';
import 'package:riflay/services/monochrome_download.dart';
import 'package:riflay/services/youtube_importer.dart';

void main() {
  late Directory dir;
  final source = Monochrome.track({
    'trackId': '155102871061270528',
    'title': 'One More Time',
    'artistNames': ['Daft Punk'],
    'albumTitle': 'Discovery',
    'artwork': 'https://example.org/cover.jpg',
  }, native: true)!;
  setUp(() => dir = Directory.systemTemp.createTempSync('monochrome-download-test-'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('saves FLAC with metadata and cover, and indexes its offline copy', () async {
    final audio = File('test/fixtures/sine.flac').readAsBytesSync();
    final cover = File('test/fixtures/cover_square.jpg').readAsBytesSync();
    var received = 0;
    final client = MockClient((r) async {
      expect(r.url.scheme, 'https');
      if (r.url.host == 'tracks.monochrome.st') expect(r.headers['User-Agent'], startsWith('Riflay/'));
      return http.Response.bytes(r.url.host == 'example.org' ? cover : audio, 200);
    });
    final saved = await MonochromeDownload.save(source, dir, client: client, progress: (bytes, _) => received = bytes);
    expect(received, audio.length);
    expect(saved.artworkUrl, source.artworkUrl);
    expect(saved.streams, isFalse);
    expect(saved.isDownload, isTrue);
    expect(saved.offlineId, source.offlineId);
    expect(saved.path, endsWith('.flac'));
    final metadata = readMetadata(File(saved.path!), getImage: true);
    expect(metadata.title, source.title);
    expect(metadata.artist, source.artist);
    expect(metadata.album, 'Discovery');
    expect(metadata.pictures.single.bytes, cover);
    expect(metadata.duration, readMetadata(File('test/fixtures/sine.flac')).duration);
    final views = LibraryViews([source, saved], 1);
    expect(views.downloads[source.offlineId], same(saved));
    expect(views.youtubeDownloads!.tracks, [saved]);
    expect(downloadedFrom([source, saved]), [saved]);
    expect((await scanDownloads([saved])).missing, isEmpty);
    expect(dir.listSync().whereType<Directory>(), isEmpty);
  });

  test('HTTP failures and HTML masquerading as audio leave no finished or partial file', () async {
    for (final response in [http.Response('Forbidden', 403), http.Response('<html>error</html>', 200)]) {
      await expectLater(
        MonochromeDownload.save(source, dir, client: MockClient((_) async => response)),
        throwsA(anything),
      );
      expect(dir.listSync(), isEmpty);
    }
  });

  test('continues completed ranges and retries a disconnected range without corrupting FLAC', () async {
    final audio = File('test/fixtures/sine.flac').readAsBytesSync();
    var interrupted = false;
    final offsets = <int>[];
    final client = MockClient.streaming((request, _) async {
      if (request.url.host == 'example.org') return http.StreamedResponse(const Stream.empty(), 404);
      final start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(request.headers['Range']!)![1]!);
      offsets.add(start);
      final end = start == 0 ? 8 : audio.length;
      final headers = {'content-range': 'bytes $start-${end - 1}/${audio.length}', 'etag': '"same-file"'};
      if (start == 8 && !interrupted) {
        interrupted = true;
        return http.StreamedResponse(
          Stream<List<int>>.error(http.ClientException('Connection closed')),
          206,
          headers: headers,
        );
      }
      return http.StreamedResponse(Stream.value(audio.sublist(start, end)), 206, headers: headers);
    });
    final saved = await MonochromeDownload.save(source, dir, client: client);
    expect(offsets, [0, 8, 8]);
    expect(readMetadata(File(saved.path!), getImage: false).title, source.title);
  });

  test('cancelling during transfer removes the partial audio', () async {
    var stop = false;
    await expectLater(
      MonochromeDownload.save(
        source,
        dir,
        client: MockClient((_) async => http.Response.bytes(File('test/fixtures/sine.flac').readAsBytesSync(), 200)),
        cancelled: () => stop,
        progress: (_, _) => stop = true,
      ),
      throwsA(anything),
    );
    expect(dir.listSync(), isEmpty);
  });

  test('download queue preserves Monochrome jobs and rejects altered file keys', () {
    final job = DownloadJob(
      videoId: MonochromeDownload.jobId(source),
      title: source.title,
      channel: source.artist,
      thumbnailUrl: source.artworkUrl!,
      monochromeTrack: source,
    );
    final encoded = YoutubeImporter.encodeQueue([job]);
    final restored = YoutubeImporter.decodeQueue(encoded).single;
    expect(restored.monochromeTrack!.offlineId, source.offlineId);
    expect(restored.videoId, MonochromeDownload.jobId(source));
    final broken = jsonDecode(encoded);
    broken['jobs'][0]['videoId'] = '../../outside';
    expect(YoutubeImporter.decodeQueue(jsonEncode(broken)), isEmpty);
  });

  test('a persisted arbitrary URL cannot become a download destination or source', () async {
    final altered = source.copyWith(uri: Uri.parse('http://localhost/private'));
    final client = MockClient((r) async {
      expect(r.url.host, isNot('localhost'));
      if (r.url.host == 'example.org') return http.Response('', 404);
      return http.Response.bytes(File('test/fixtures/sine.flac').readAsBytesSync(), 200);
    });
    await MonochromeDownload.save(altered, dir, client: client);
    expect(dir.listSync().whereType<File>(), hasLength(1));
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:riflay/models/track.dart';
import 'package:riflay/services/download_files.dart';

Track _song(String path, String videoId) => Track(
  id: Uri.file(path).toString(),
  uri: Uri.file(path),
  title: 'Song $videoId',
  artist: 'Artist',
  addedAt: 0,
  sourceUrl: 'https://music.youtube.com/watch?v=$videoId',
);

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('download_files_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('video ids come from watch and youtu.be links', () {
    expect(youtubeVideoIdOf('https://music.youtube.com/watch?v=abcdefghijk'), 'abcdefghijk');
    expect(youtubeVideoIdOf('https://youtu.be/abcdefghijk'), 'abcdefghijk');
    expect(youtubeVideoIdOf('https://example.com/song'), isNull);
    expect(youtubeVideoIdOf(null), isNull);
  });

  test('downloadedFrom keeps only files that came from YouTube', () {
    final local = Track.fromUri(Uri.file('/music/a.mp3'));
    final streamed = Track.youtube(videoId: 'abcdefghijk', title: 'S', artist: 'A');
    final saved = _song('/music/b.m4a', 'bbbbbbbbbbb');
    expect(downloadedFrom([local, streamed, saved]), [saved]);
  });

  test('scan sums existing files and lists the missing ones', () async {
    final a = File(p.join(dir.path, 'a.m4a'))..writeAsBytesSync(List.filled(1000, 1));
    final b = File(p.join(dir.path, 'b.m4a'))..writeAsBytesSync(List.filled(500, 1));
    final gone = _song(p.join(dir.path, 'gone.m4a'), 'ccccccccccc');
    final scan = await scanDownloads([_song(a.path, 'aaaaaaaaaaa'), _song(b.path, 'bbbbbbbbbbb'), gone]);
    expect(scan.bytes, 1500);
    expect(scan.missing, [gone]);
  });

  test('an old entry is not missing when the same video exists in another file', () async {
    final now = File(p.join(dir.path, 'new.flac'))..writeAsBytesSync([1, 2, 3]);
    final old = _song(p.join(dir.path, 'old.m4a'), 'aaaaaaaaaaa');
    final scan = await scanDownloads([old, _song(now.path, 'aaaaaaaaaaa')]);
    expect(scan.missing, isEmpty);
    expect(scan.bytes, 3);
  });

  test('nothing downloaded scans to zero', () async {
    final scan = await scanDownloads(const []);
    expect(scan.bytes, 0);
    expect(scan.missing, isEmpty);
  });

  test('sizes read like a person would say them', () {
    expect(formatFileSize(0), '0 B');
    expect(formatFileSize(900), '900 B');
    expect(formatFileSize(850 * 1024), '850 KB');
    expect(formatFileSize((12.4 * 1024 * 1024).round()), '12.4 MB');
    expect(formatFileSize((1.2 * 1024 * 1024 * 1024).round()), '1.2 GB');
  });
}

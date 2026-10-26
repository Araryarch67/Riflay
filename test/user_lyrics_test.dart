import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/lyrics.dart';

Track _song({String? videoId, String? sourceUrl, String id = 'file:///music/a.webm'}) =>
    Track(id: id, uri: Uri.parse(id), title: 'Song', artist: 'Artist', videoId: videoId, sourceUrl: sourceUrl);

void main() {
  group('Lyrics.check', () {
    test('timed lyrics are accepted', () {
      final r = Lyrics.check('[ar:Somebody]\n[00:12.00]First line\n[01:03.50][02:00.25]Chorus\n');
      expect(r.ok, isTrue);
      expect(r.timed, isTrue);
    });

    test('plain words are accepted as plain lyrics', () {
      final r = Lyrics.check('Just words\nNo times at all');
      expect(r.ok, isTrue);
      expect(r.timed, isFalse);
    });

    test('empty lyrics ask for some', () {
      expect(Lyrics.check('  \n ').problem, 'Add some lyrics first.');
    });

    test('a badly written time is refused with one calm sentence', () {
      for (final bad in ['[1:2:3x]Oops', '[00:75.00]Seconds over 59', '[00:1']) {
        final r = Lyrics.check('[00:05.00]Fine\n$bad');
        expect(r.ok, isFalse, reason: bad);
        expect(r.problem, contains('times'));
        expect(r.problem, isNot(contains('Exception')));
      }
    });

    test('times far past the end of the song are refused', () {
      expect(Lyrics.check('[10:00.00]Late', length: const Duration(minutes: 3)).ok, isFalse);
      expect(Lyrics.check('[03:05.00]Just inside', length: const Duration(minutes: 3)).ok, isTrue);
    });

    test('parse reads what check accepts', () {
      final l = Lyrics.parse('[00:01.50]One\n[00:03.00]Two', source: 'x');
      expect(l.synced, isTrue);
      expect(l.lines.map((e) => e.text), ['One', 'Two']);
      expect(l.lines.first.time, const Duration(milliseconds: 1500));
    });
  });

  group('UserLyrics', () {
    late Directory dir;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('riflay-my-lyrics');
      UserLyrics.dirOverride = dir;
    });
    tearDown(() {
      UserLyrics.dirOverride = null;
      dir.deleteSync(recursive: true);
    });

    test('a download and the streamed copy of the same video share one lyrics file', () {
      final streamed = _song(videoId: 'dQw4w9WgXcQ', id: 'yt:dQw4w9WgXcQ');
      final download = _song(sourceUrl: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
      expect(UserLyrics.keyOf(download), UserLyrics.keyOf(streamed));
      expect(UserLyrics.keyOf(_song(id: 'file:///music/other.m4a')), isNot('dQw4w9WgXcQ'));
    });

    test('saved lyrics are read back, and removed on request', () async {
      final song = _song(sourceUrl: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
      expect(await UserLyrics.read(song), isNull);
      await UserLyrics.save(song, '[00:01.00]Mine\n');
      expect(await UserLyrics.read(song), '[00:01.00]Mine');
      await UserLyrics.remove(song);
      expect(await UserLyrics.read(song), isNull);
    });

    test('the lyrics service shows the person\'s lyrics before looking anywhere else', () async {
      final song = _song(sourceUrl: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
      await UserLyrics.save(song, '[00:01.00]Mine\n[00:05.00]Still mine');
      final found = await LyricsService.forTrack(song);
      expect(found.source, 'Your lyrics');
      expect(found.synced, isTrue);
      expect(found.lines.last.text, 'Still mine');
    });
  });
}

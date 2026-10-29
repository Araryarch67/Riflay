import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/lyrics.dart';

Duration ms(int n) => Duration(milliseconds: n);

void main() {
  group('enhanced LRC', () {
    test('word tags give each word a start and an end', () {
      final l = Lyrics.parse('[00:12.00]<00:12.00>Hello <00:12.50>world<00:13.20>\n[00:15.00]Next line', source: 'x');
      final line = l.lines.first;
      expect(line.text, 'Hello world');
      expect(line.words.map((w) => w.text), ['Hello ', 'world']);
      expect(line.words[0].start, ms(12000));
      expect(line.words[0].end, ms(12500));
      expect(line.words[1].start, ms(12500));
      expect(line.words[1].end, ms(13200));
      expect(line.end, ms(13200));
      expect(l.lines[1].words, isEmpty);
      expect(l.wordSynced, isTrue);
    });

    test('a first word without a tag starts with the line; the last ends where the next line starts', () {
      final l = Lyrics.parse('[00:12.00]Hello <00:12.500>world\n[00:14.00]Again', source: 'x');
      expect(l.lines.first.words[0].start, ms(12000));
      expect(l.lines.first.words[0].end, ms(12500));
      expect(l.lines.first.words[1].end, ms(14000));
      expect(l.lines.first.text, 'Hello world');
    });

    test('the last word of the last line lasts a second, and [offset:] moves the words too', () {
      final l = Lyrics.parse('[offset:500]\n[00:10.00]<00:10.00>Only <00:10.40>one', source: 'x');
      expect(l.lines.first.time, ms(9500));
      expect(l.lines.first.words[0].start, ms(9500));
      expect(l.lines.first.words[1].start, ms(9900));
      expect(l.lines.first.words[1].end, ms(10900));
    });
  });

  group('TTML words', () {
    const ttml = '''
<tt xmlns="http://www.w3.org/ns/ttml" xmlns:ttm="http://www.w3.org/ns/ttml#metadata"><body><div>
<p begin="0:10.000" end="0:12.000"><span begin="0:10.000" end="0:10.500">Hel</span><span begin="0:10.500" end="0:11.000">lo</span> <span begin="0:11.000" end="0:11.800">world</span><span ttm:role="x-bg" begin="0:11.000" end="0:11.500">(ooh)</span></p>
<p begin="0:13.000" end="0:14.000">No spans here</p>
</div></body></tt>''';

    test('syllables join into words, spaces stay on the word before', () {
      final l = Lyrics.parseTtml(ttml, source: 'x');
      final line = l.lines.first;
      expect(line.text, 'Hello world');
      expect(line.words.map((w) => w.text), ['Hel', 'lo ', 'world']);
      expect(line.words[1].start, ms(10500));
      expect(line.words[2].end, ms(11800));
      expect(line.end, ms(12000));
      expect(l.lines[1].words, isEmpty);
    });
  });

  group('timings nobody could follow', () {
    test('every line at 00:00 is plain text', () {
      final l = Lyrics.parse('[00:00.00]One\n[00:00.00]Two\n[00:00.00]Three', source: 'x');
      expect(l.synced, isFalse);
      expect(l.plain, 'One\nTwo\nThree');
    });

    test('a repeated chorus stamp stays synced', () {
      final l = Lyrics.parse('[00:05.00]Verse\n[00:10.00][01:30.00]Chorus\n[00:20.00]Bridge', source: 'x');
      expect(l.synced, isTrue);
      expect(l.lines.map((x) => x.text), ['Verse', 'Chorus', 'Bridge', 'Chorus']);
    });
  });

  group('toLrc', () {
    test('words and lines come back from parse', () {
      final src = Lyrics.parse(
        '[00:12.00]<00:12.00>Hello <00:12.50>world<00:13.20>\n[00:15.00]Plain line\n[00:18.00]<00:18.00>Gap <00:18.50>here<00:18.70>',
        source: 'x',
      );
      final back = Lyrics.parse(src.toLrc()!, source: 'x');
      expect(back.lines.length, src.lines.length);
      for (final (i, a) in src.lines.indexed) {
        final b = back.lines[i];
        expect(b.text, a.text);
        expect((b.time - a.time).inMilliseconds.abs(), lessThanOrEqualTo(10));
        expect(b.words.length, a.words.length);
        for (final (j, w) in a.words.indexed) {
          expect(b.words[j].text, w.text);
          expect((b.words[j].start - w.start).inMilliseconds.abs(), lessThanOrEqualTo(10));
          expect((b.words[j].end - w.end).inMilliseconds.abs(), lessThanOrEqualTo(10));
        }
      }
    });

    test('plain is its text, instrumental and none are null', () {
      expect(const Lyrics(plain: 'a\nb', source: 'x').toLrc(), 'a\nb');
      expect(const Lyrics(instrumental: true, source: 'x').toLrc(), isNull);
      expect(Lyrics.none.toLrc(), isNull);
    });
  });

  group('LyricsCache', () {
    late Directory dir;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('riflay-lyrics-cache');
      LyricsCache.dirOverride = dir;
    });
    tearDown(() {
      LyricsCache.dirOverride = null;
      dir.deleteSync(recursive: true);
    });

    test('words survive a round trip through the disk', () async {
      final song = Track.youtube(videoId: 'dQw4w9WgXcQ', title: 'T', artist: 'A');
      expect(await LyricsCache.read(song), isNull);
      final l = Lyrics.parse('[00:12.00]<00:12.00>Hello <00:12.50>world<00:13.20>\n[00:15.00]Next', source: 'Kugou');
      await LyricsCache.write(song, l);
      final back = (await LyricsCache.read(song))!;
      expect(back.source, 'Kugou');
      expect(back.lines.length, 2);
      expect(back.lines.first.words.map((w) => w.text), ['Hello ', 'world']);
      expect(back.lines.first.words[1].end, ms(13200));
      expect(back.lines.first.end, ms(13200));
      expect(back.lines[1].words, isEmpty);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/lyrics.dart';
import 'package:riflay/services/lyrics_video_alignment.dart';
import 'package:riflay/services/ytmusic_web.dart';

Lyrics lyrics({int shift = 0, List<String>? texts, List<int>? times, bool otherVersion = false}) => Lyrics(
  source: 'test',
  otherVersion: otherVersion,
  lines: [
    for (var i = 0; i < (texts?.length ?? 6); i++)
      LyricLine(Duration(milliseconds: (times?[i] ?? (10000 + i * 12000)) + shift), texts?[i] ?? 'Unique line $i'),
  ],
);

void main() {
  test('local audio ahead by two seconds advances the MV, preserving its intro', () {
    final offset = LyricsVideoAlignment.offset(lyrics(), lyrics(shift: 2000));
    expect(offset, const Duration(seconds: 2));
    const mv = MusicVideo(
      videoId: 'mv',
      segments: [
        VideoSegment(songStart: Duration.zero, videoStart: Duration(seconds: 15), length: Duration(minutes: 3)),
      ],
    );
    expect(mv.videoTimeAt(const Duration(seconds: 30) + offset!), const Duration(seconds: 47));
    // Song-only and MV-only parts keep their existing map boundaries.
    expect(mv.videoTimeAt(const Duration(seconds: 179) + offset), isNull);
  });

  test('local audio behind by 1.5 seconds delays the MV', () {
    expect(LyricsVideoAlignment.offset(lyrics(shift: 1500), lyrics()), const Duration(milliseconds: -1500));
  });

  test('same timing needs no correction', () {
    expect(LyricsVideoAlignment.offset(lyrics(), lyrics()), Duration.zero);
  });

  test('punctuation, spacing and case differ without losing Unicode text', () {
    final a = lyrics(texts: ['Hello, world!', 'HATI HATI', '君の声が', 'Selamat malam']);
    final b = lyrics(shift: 1000, texts: ['hello world', 'hati-hati', '君の声が。', 'Selamat, malam!']);
    expect(LyricsVideoAlignment.offset(a, b), const Duration(seconds: 1));
  });

  test('small lyric timestamp rounding and one bad line do not dominate', () {
    final remote = lyrics(times: [12000, 24020, 36000, 48000, 60000, 73000]);
    expect(LyricsVideoAlignment.offset(lyrics(), remote), const Duration(seconds: 2));
  });

  test('repeated choruses alone cannot identify an offset', () {
    final repeated = lyrics(texts: List.filled(6, 'Same chorus'));
    expect(LyricsVideoAlignment.offset(repeated, repeated), isNull);
  });

  test('unrelated, plain, short, or explicitly different versions are rejected', () {
    expect(LyricsVideoAlignment.offset(lyrics(), lyrics(texts: List.generate(6, (i) => 'Different words $i'))), isNull);
    expect(LyricsVideoAlignment.offset(lyrics(), const Lyrics(source: 'plain', plain: 'Words')), isNull);
    expect(LyricsVideoAlignment.offset(lyrics(texts: ['One line']), lyrics()), isNull);
    expect(LyricsVideoAlignment.offset(lyrics(), lyrics(otherVersion: true)), isNull);
    expect(
      LyricsVideoAlignment.offset(
        lyrics(times: [1000, 2000, 3000, 4000, 5000, 6000]),
        lyrics(times: [2000, 3000, 4000, 5000, 6000, 7000]),
      ),
      isNull,
    );
  });

  test('different edits, progressive drift and implausible shifts are rejected', () {
    expect(LyricsVideoAlignment.offset(lyrics(), lyrics(times: [12000, 24000, 36000, 52000, 64000, 76000])), isNull);
    expect(LyricsVideoAlignment.offset(lyrics(), lyrics(times: [10000, 22400, 34800, 47200, 59600, 72000])), isNull);
    expect(LyricsVideoAlignment.offset(lyrics(), lyrics(shift: 40000)), isNull);
  });
}

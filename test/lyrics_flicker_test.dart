import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/lyrics.dart';

void main() {
  String lrc(List<(double, String)> lines) => [
    for (final (s, text) in lines)
      '[${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toStringAsFixed(2).padLeft(5, '0')}]$text',
  ].join('\n');

  test('a line repeated every fraction of a second is junk, not lyrics', () {
    final junk = Lyrics.parse(
      lrc([for (var i = 0; i < 40; i++) (1 + i * 0.15, 'はーい注目　はーい注目')]),
      source: 'LRCLIB',
    );
    expect(junk.synced, isTrue);
    expect(Lyrics.flickers(junk.lines), isTrue);
  });

  test('ordinary timed lyrics, quick lines here and there included, are kept', () {
    final real = Lyrics.parse(
      lrc([(0.9, 'はーい注目'), (2.2, 'まあ いっちょ踊ってこうか？'), (2.4, 'Hey!'), (4.4, '視線牛耳ってんのは'), (6.9, 'I I I'), (8.1, 'あれ？')]),
      source: 'LRCLIB',
    );
    expect(Lyrics.flickers(real.lines), isFalse);
  });
}

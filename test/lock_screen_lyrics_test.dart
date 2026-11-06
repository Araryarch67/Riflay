import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/lyrics.dart';
import 'package:riflay/services/media_session.dart';

void main() {
  final lyrics = Lyrics.parse(
    '[00:05.00]First line\n'
    '[00:09.00]Second line\n'
    '[00:14.00]♪\n'
    '[00:20.00]Third line\n',
    source: 'test',
  );
  Duration s(num seconds) => Duration(milliseconds: (seconds * 1000).round());

  test('the line being sung, a little early, and nothing before the first or on a ♪ line', () {
    expect(MediaSession.lineFor(lyrics, s(2)), isNull, reason: 'before the first line the artist shows');
    expect(MediaSession.lineFor(lyrics, s(4.9)), 'First line', reason: 'lit a moment before it starts');
    expect(MediaSession.lineFor(lyrics, s(8)), 'First line');
    expect(MediaSession.lineFor(lyrics, s(10)), 'Second line');
    expect(MediaSession.lineFor(lyrics, s(15)), isNull, reason: 'an instrumental break shows the artist');
    expect(MediaSession.lineFor(lyrics, s(60)), 'Third line');
  });

  test('wakes at the next line, not on a clock', () {
    expect(MediaSession.nextLineAt(lyrics, s(2)), s(4.85));
    expect(MediaSession.nextLineAt(lyrics, s(6)), s(8.85));
    expect(MediaSession.nextLineAt(lyrics, s(21)), isNull, reason: 'the last line stays until the song changes');
  });

  test("a line's own end hands the place back to the artist", () {
    const timed = Lyrics(
      lines: [
        LyricLine(Duration(seconds: 1), 'Hello', end: Duration(seconds: 3)),
        LyricLine(Duration(seconds: 10), 'Again'),
      ],
      source: 'test',
    );
    expect(MediaSession.lineFor(timed, s(2)), 'Hello');
    expect(MediaSession.lineFor(timed, s(5)), isNull);
    expect(MediaSession.nextLineAt(timed, s(2)), s(2.85));
    expect(MediaSession.nextLineAt(timed, s(5)), s(9.85));
  });
}

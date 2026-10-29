import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/lyrics_sources.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Trimmed from real replies (2026-10): Kugou and QQ Music for "晴天" by 周杰伦,
// Genius for "Hati-Hati di Jalan" by Tulus, Megalobiz for "Shape of You".
String _fixture(String name) => File('test/fixtures/lyrics/$name').readAsStringSync();

Track _song(String title, String artist, int seconds) => Track(
  id: title,
  uri: Uri.parse('file:///x'),
  title: title,
  artist: artist,
  duration: Duration(seconds: seconds),
);

http.Response _ok(String body) => http.Response.bytes(utf8.encode(body), 200);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MoreLyrics.resetMusixmatch();
  });

  group('Kugou', () {
    test('KRC: words get absolute times and the credits and headline go', () {
      final bytes = base64.decode((jsonDecode(_fixture('kugou_download_krc.json')) as Map)['content'] as String);
      final l = MoreLyrics.parseKrc(MoreLyrics.decodeKrc(bytes), title: '晴天')!;
      expect(l.source, 'Kugou');
      expect(l.lines.map((x) => x.text), ['故事的小黄花', '从出生那年就飘着', 'Re So So Si Do Si La']);
      final first = l.lines.first;
      expect(first.time, const Duration(milliseconds: 29264));
      expect(first.end, const Duration(milliseconds: 29264 + 3446));
      expect(first.words.map((w) => w.text).join(), first.text);
      // Offsets count from the start of the line.
      expect(first.words[1].start, const Duration(milliseconds: 29264 + 390));
      expect(first.words[1].end, const Duration(milliseconds: 29264 + 390 + 392));
      // Spaces stay on the word they follow, none after the last.
      final spaced = l.lines.last;
      expect(spaced.words.first.text, 'Re ');
      expect(spaced.words.last.text, 'La');
      expect(l.wordSynced, isTrue);
    });

    test('a bad file is refused', () {
      expect(() => MoreLyrics.decodeKrc([1, 2, 3, 4, 5]), throwsFormatException);
    });

    test('end to end through the search and the download', () async {
      final asked = <String>[];
      final client = MockClient((req) async {
        asked.add(req.url.path);
        if (req.url.path == '/search') {
          expect(req.url.queryParameters['keyword'], '周杰伦 - 晴天');
          return _ok(_fixture('kugou_search.json'));
        }
        expect(req.url.queryParameters['id'], '274944371');
        return _ok(_fixture('kugou_download_krc.json'));
      });
      final l = (await MoreLyrics.kugou(_song('晴天', '周杰伦', 269), client: client))!;
      expect(asked, ['/search', '/download']);
      expect(l.wordSynced, isTrue);
      expect(l.lines.first.text, '故事的小黄花');
    });

    test('another song, another length or an unknown artist finds nothing', () async {
      final client = MockClient((req) async => _ok(_fixture('kugou_search.json')));
      expect(await MoreLyrics.kugou(_song('雨天', '周杰伦', 269), client: client), isNull);
      expect(await MoreLyrics.kugou(_song('晴天', '周杰伦', 200), client: client), isNull);
      expect(await MoreLyrics.kugou(_song('晴天', 'Someone Else', 269), client: client), isNull);
      expect(await MoreLyrics.kugou(_song('晴天', Track.unknownArtist, 269), client: client), isNull);
    });

    test('a server error throws', () async {
      final client = MockClient((req) async => http.Response('', 500));
      expect(MoreLyrics.kugou(_song('晴天', '周杰伦', 269), client: client), throwsA(isA<HttpException>()));
    });
  });

  group('QQ Music', () {
    test('lyric reply → timed lines without credits', () {
      final l = MoreLyrics.parseQqLyric(_fixture('qq_lyric.json'), title: '晴天')!;
      expect(l.source, 'QQ Music');
      expect(l.lines.map((x) => (x.time.inMilliseconds, x.text)), [
        (29260, '故事的小黄花'),
        (32710, '从出生那年就飘着'),
        (36240, '童年的荡秋千'),
      ]);
    });

    test('end to end, with the Referer', () async {
      final client = MockClient((req) async {
        expect(req.headers['Referer'], 'https://y.qq.com');
        if (req.url.path.contains('client_search')) return _ok(_fixture('qq_search.json'));
        expect(req.url.queryParameters['songmid'], '0039MnYb0qxYhV'); // not the cover band's
        return _ok(_fixture('qq_lyric.json'));
      });
      final l = (await MoreLyrics.qqMusic(_song('晴天', '周杰伦', 269), client: client))!;
      expect(l.synced, isTrue);
    });

    test('a wrong-song hit is rejected and a 500 throws', () async {
      final client = MockClient((req) async => _ok(_fixture('qq_search.json')));
      expect(await MoreLyrics.qqMusic(_song('晴天', 'Nobody', 269), client: client), isNull);
      final broken = MockClient((req) async => http.Response('', 503));
      expect(MoreLyrics.qqMusic(_song('晴天', '周杰伦', 269), client: broken), throwsA(isA<HttpException>()));
    });
  });

  group('Musixmatch', () {
    test('richsync → words with times', () {
      final l = MoreLyrics.parseRichsync(_fixture('mxm_richsync.json'))!;
      expect(l.lines.map((x) => x.text), ['Hello dark world', 'Sunny day']);
      final first = l.lines.first;
      expect(first.time, const Duration(milliseconds: 12300));
      expect(first.end, const Duration(milliseconds: 15100));
      expect(first.words.map((w) => w.text), ['Hello ', 'dark ', 'world']);
      expect(first.words[1].start, const Duration(milliseconds: 12800));
      expect(first.words[1].end, const Duration(milliseconds: 13500));
      expect(first.words.last.end, const Duration(milliseconds: 15100));
      // Syllables: "Sun" + "ny " stay separate words.
      expect(l.lines.last.words.map((w) => w.text), ['Sun', 'ny ', 'day']);
    });

    String macro({String name = 'Hello', String artist = 'Adele', bool rich = true}) => jsonEncode({
      'message': {
        'header': {'status_code': 200},
        'body': {
          'macro_calls': {
            'matcher.track.get': {
              'message': {
                'header': {'status_code': 200},
                'body': {
                  'track': {'track_name': name, 'artist_name': artist, 'track_length': 295, 'instrumental': 0},
                },
              },
            },
            'track.richsync.get': {
              'message': {
                'header': {'status_code': rich ? 200 : 404},
                'body': rich
                    ? {
                        'richsync': {'richsync_body': _fixture('mxm_richsync.json')},
                      }
                    : [],
              },
            },
            'track.subtitles.get': {
              'message': {
                'header': {'status_code': 200},
                'body': {
                  'subtitle_list': [
                    {
                      'subtitle': {'subtitle_body': '[00:12.00]Hello\n[00:16.00]It is me'},
                    },
                  ],
                },
              },
            },
          },
        },
      },
    });

    String tokenReply(String token) => jsonEncode({
      'message': {
        'header': {'status_code': 200},
        'body': {'user_token': token},
      },
    });

    test('token, then richsync; the token is kept for the next song', () async {
      var tokens = 0;
      final client = MockClient((req) async {
        if (req.url.path.endsWith('token.get')) {
          tokens++;
          return _ok(tokenReply('2b4c8f1e5a9d4c7e8f2a6b3d1c0e9f8a7b6c5d4e3f2a1b0c9d8e7f'));
        }
        expect(req.url.queryParameters['usertoken'], startsWith('2b4c8f'));
        return _ok(macro());
      });
      final l = (await MoreLyrics.musixmatch(_song('Hello', 'Adele', 295), client: client))!;
      expect(l.wordSynced, isTrue);
      expect(l.source, 'Musixmatch');
      await MoreLyrics.musixmatch(_song('Hello', 'Adele', 295), client: client);
      expect(tokens, 1);
    });

    test('without richsync the timed lines are used', () async {
      final client = MockClient((req) async {
        if (req.url.path.endsWith('token.get')) return _ok(tokenReply('2b4c8f1e5a9d4c7e8f2a6b3d1c0e9f8a7b6c5d4e'));
        return _ok(macro(rich: false));
      });
      final l = (await MoreLyrics.musixmatch(_song('Hello', 'Adele', 295), client: client))!;
      expect(l.wordSynced, isFalse);
      expect(l.lines.map((x) => x.text), ['Hello', 'It is me']);
    });

    test('a different song in the answer is rejected', () async {
      final client = MockClient((req) async {
        if (req.url.path.endsWith('token.get')) return _ok(tokenReply('2b4c8f1e5a9d4c7e8f2a6b3d1c0e9f8a7b6c5d4e'));
        return _ok(macro(name: 'NOKIA', artist: 'Drake'));
      });
      expect(await MoreLyrics.musixmatch(_song('Hello', 'Adele', 295), client: client), isNull);
    });

    test('a refused token gives null and a pause, not a new request each time', () async {
      var asked = 0;
      final client = MockClient((req) async {
        asked++;
        return _ok(tokenReply('0' * 54));
      });
      expect(await MoreLyrics.musixmatch(_song('Hello', 'Adele', 295), client: client), isNull);
      expect(await MoreLyrics.musixmatch(_song('Hello', 'Adele', 295), client: client), isNull);
      expect(asked, 1);
    });

    test('a server error throws', () async {
      final client = MockClient((req) async => http.Response('', 500));
      expect(MoreLyrics.musixmatch(_song('Hello', 'Adele', 295), client: client), throwsA(isA<HttpException>()));
    });
  });

  group('Genius', () {
    test('page → the words without the header junk', () {
      final text = MoreLyrics.geniusText(_fixture('genius_page.html'))!;
      expect(text, startsWith('[Lirik "Hati-hati di Jalan"]'));
      expect(text, isNot(contains('Contributors')));
      expect(text, isNot(contains('Translations')));
      expect(text, isNot(contains('<')));
      expect(text, contains("'Ku bertemu kamu"));
      expect(
        text,
        contains('Kukira kita asam dan garam\nDan kita bertemu di belanga\nKisah yang ternyata tak seindah itu'),
      );
      expect(text, endsWith('[Outro]\nHati-hati di jalan'));
    });

    test('end to end; the translation and the remix are not taken', () async {
      final fetched = <String>[];
      final client = MockClient((req) async {
        if (req.url.path.startsWith('/api/search')) return _ok(_fixture('genius_search.json'));
        fetched.add(req.url.path);
        return _ok(_fixture('genius_page.html'));
      });
      final l = (await MoreLyrics.genius(_song('Hati-Hati di Jalan', 'Tulus', 242), client: client))!;
      expect(l.plain, contains('Perjalanan membawamu'));
      expect(l.source, 'Genius');
      expect(fetched, ['/Tulus-hati-hati-di-jalan-lyrics']);
    });

    test('another artist finds nothing and a 500 throws', () async {
      final client = MockClient((req) async => _ok(_fixture('genius_search.json')));
      expect(await MoreLyrics.genius(_song('Hati-Hati di Jalan', 'Someone Else', 242), client: client), isNull);
      final broken = MockClient((req) async => http.Response('', 500));
      expect(
        MoreLyrics.genius(_song('Hati-Hati di Jalan', 'Tulus', 242), client: broken),
        throwsA(isA<HttpException>()),
      );
    });
  });

  group('Megalobiz', () {
    test('end to end: the sheet of the right length becomes timed lines', () async {
      final client = MockClient((req) async {
        if (req.url.path.endsWith('/search')) return _ok(_fixture('megalobiz_search.json'));
        expect(req.url.path, '/api/public/v1/lrc/731');
        return _ok(_fixture('megalobiz_lrc.txt'));
      });
      final l = (await MoreLyrics.megalobiz(_song('Shape of You', 'Ed Sheeran', 234), client: client))!;
      expect(l.source, 'Megalobiz');
      expect(l.lines.first.time, const Duration(milliseconds: 9660));
      expect(l.lines.first.text, "The club isn't the best place to find a lover");
      expect(l.lines.length, 4);
    });

    test('a wrong song or length is rejected, and a 429 or 500 throws', () async {
      final client = MockClient((req) async => _ok(_fixture('megalobiz_search.json')));
      expect(await MoreLyrics.megalobiz(_song('Perfect', 'Ed Sheeran', 234), client: client), isNull);
      expect(await MoreLyrics.megalobiz(_song('Shape of You', 'Ed Sheeran', 300), client: client), isNull);
      for (final code in [429, 500]) {
        final broken = MockClient((req) async => http.Response('', code));
        expect(
          MoreLyrics.megalobiz(_song('Shape of You', 'Ed Sheeran', 234), client: broken),
          throwsA(isA<HttpException>()),
        );
      }
    });
  });

  test('credit lines are told from sung ones', () {
    expect(MoreLyrics.isCredit('词：周杰伦'), isTrue);
    expect(MoreLyrics.isCredit('Composer: Someone'), isTrue);
    expect(MoreLyrics.isCredit('Composed by：Ed Sheeran/Steve Mac'), isTrue);
    expect(MoreLyrics.isCredit('Hello from the other side'), isFalse);
  });
}

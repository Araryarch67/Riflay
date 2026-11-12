import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/sources/audius.dart';
import 'package:riflay/services/sources/ccmixter.dart';
import 'package:riflay/services/sources/jamendo.dart';
import 'package:riflay/services/sources/music_sources.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MusicSources.instance.reset();
  });

  test('Audius keeps only songs it streams to anyone, and plays its stream address', () async {
    late Uri asked;
    final audius = Audius(
      client: MockClient((req) async {
        asked = req.url;
        return http.Response(
          jsonEncode({
            'data': [
              {
                'id': 'O6bw9pR',
                'title': 'Piano Fala',
                'duration': 76,
                'is_streamable': true,
                'artwork': {'480x480': 'https://node.example/480.jpg'},
                'user': {'name': 'Fala', 'handle': 'fala'},
              },
              {'id': 'gated', 'title': 'Paid', 'is_streamable': true, 'is_stream_gated': true, 'user': {}},
              {'id': 'gone', 'title': 'Deleted', 'is_streamable': true, 'is_delete': true, 'user': {}},
              {'id': 'off', 'title': 'Off', 'is_streamable': false, 'user': {}},
              {
                'id': 'left',
                'title': 'Left',
                'is_streamable': true,
                'user': {'is_deactivated': true},
              },
              {'id': '../x', 'title': 'Bad id', 'is_streamable': true, 'user': {}},
            ],
          }),
          200,
        );
      }),
    );
    final songs = await audius.search(' piano ', limit: 5);
    expect(asked.host, Audius.host);
    expect(asked.queryParameters, {'query': 'piano', 'limit': '10', 'app_name': Audius.appName});
    final song = songs.single;
    expect(song.id, 'audius:O6bw9pR');
    expect(song.uri.toString(), 'https://api.audius.co/v1/tracks/O6bw9pR/stream?app_name=Riflay');
    expect((song.title, song.artist, song.duration), ('Piano Fala', 'Fala', const Duration(seconds: 76)));
    expect(song.artworkUrl, 'https://node.example/480.jpg');
    expect(song.streams, isFalse, reason: 'not YouTube Music or SoundCloud');
    expect(Track.fromJson(song.toJson()).uri, song.uri);
  });

  test('ccMixter plays the full mix, in FLAC when there is one, and leaves out stems and samples', () {
    Map file(String name, String nick, String ext, {String ps = '2:03'}) => {
      'file_nicname': nick,
      'download_url': 'https://ccmixter.org/content/a/$name',
      'file_format_info': {'media-type': 'audio', 'default-ext': ext, 'ps': ps},
    };
    final cc = CcMixter();
    final song = cc.parse({
      'upload_id': 71346,
      'upload_name': 'Same block,',
      'user_name': 'md',
      'user_real_name': 'Malre',
      'upload_tags': ',remix,attribution,',
      'files': [
        file('a.mp3', 'mp3', 'mp3'),
        file('a_1.flac', 'Percussion.flac', 'flac'),
        file('a.flac', 'flac', 'flac'),
      ],
    })!;
    expect(song.id, 'ccmixter:71346');
    expect(song.uri.toString(), 'https://ccmixter.org/content/a/a.flac');
    expect((song.title, song.artist), ('Same block', 'Malre'));
    expect(song.duration, const Duration(minutes: 2, seconds: 3));
    final mp3 = cc.parse({
      'upload_id': 2,
      'upload_name': 'Only MP3',
      'user_name': 'x',
      'files': [file('b.mp3', 'mp3', 'mp3', ps: 'bad'), file('b_1.flac', 'Brass.flac', 'flac')],
    })!;
    expect(mp3.uri.path, '/content/a/b.mp3');
    expect(mp3.duration, isNull);
    expect(
      cc.parse({
        'upload_id': 3,
        'upload_name': 'Stems',
        'upload_tags': ',sample,stem,',
        'files': [file('c.flac', 'flac', 'flac')],
      }),
      isNull,
    );
    expect(CcMixter.parseLength('1:02:03'), const Duration(hours: 1, minutes: 2, seconds: 3));
  });

  test('Jamendo is hidden without a client id and asks with it when there is one', () async {
    expect(Jamendo(clientIdOverride: '').available, isFalse);
    expect(await Jamendo(clientIdOverride: '').search('song'), isEmpty);
    late Uri asked;
    final jamendo = Jamendo(
      clientIdOverride: 'abc',
      client: MockClient((req) async {
        asked = req.url;
        return http.Response(
          jsonEncode({
            'headers': {'status': 'success'},
            'results': [
              {
                'id': '1532771',
                'name': 'Morning',
                'duration': 201,
                'artist_name': 'Ava',
                'album_name': 'Light',
                'image': 'https://usercontent.jamendo.com/cover.jpg',
                'audio': 'https://prod-1.storage.jamendo.com/?trackid=1532771&format=mp32',
              },
              {'id': '2', 'name': 'No audio'},
            ],
          }),
          200,
        );
      }),
    );
    final song = (await jamendo.search('morning')).single;
    expect(asked.queryParameters['client_id'], 'abc');
    expect(asked.queryParameters['search'], 'morning');
    expect(song.id, 'jamendo:1532771');
    expect(song.uri.host, 'prod-1.storage.jamendo.com');
    expect((song.artist, song.album, song.duration), ('Ava', 'Light', const Duration(seconds: 201)));
  });

  test('a refusal is told apart from no matches', () async {
    final refused = MockClient((_) async => http.Response('Denied', 403));
    await expectLater(Audius(client: refused).search('x'), throwsA(isA<http.ClientException>()));
    await expectLater(CcMixter(client: refused).search('x'), throwsA(isA<http.ClientException>()));
    final badKey = Jamendo(
      clientIdOverride: 'wrong',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'headers': {'status': 'failed', 'code': 5},
            'results': [],
          }),
          200,
        ),
      ),
    );
    await expectLater(badKey.search('x'), throwsA(isA<http.ClientException>()));
  });

  test('song sources are off until turned on, and stay as set', () async {
    final s = MusicSources.instance;
    await s.load();
    expect(s.enabledSongSources, isEmpty);
    await s.setOn(Audius.instance, true);
    await s.setOn(CcMixter.instance, true);
    s.reset();
    await s.load();
    expect(s.enabledSongSources, [Audius.instance, CcMixter.instance]);
    expect((s.archive, s.radioParadise), (true, true));
    await s.setOn(Audius.instance, false);
    s.reset();
    await s.load();
    expect(s.enabledSongSources, [CcMixter.instance]);
  });
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/incoming_links.dart';
import 'package:riflay/services/play_history.dart';
import 'package:riflay/services/soundcloud.dart';
import 'package:riflay/services/soundcloud_audio_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _transcoding(String preset, String mime, {String protocol = 'hls', bool snipped = false}) => {
  'url': 'https://api-v2.soundcloud.com/media/soundcloud:tracks:1/$preset/stream/$protocol',
  'preset': preset,
  'snipped': snipped,
  'format': {'protocol': protocol, 'mime_type': mime},
};

Map<String, dynamic> _track({
  int id = 42,
  String policy = 'ALLOW',
  List<Map<String, dynamic>>? transcodings,
  Object? artwork = 'https://i1.sndcdn.com/artworks-000abc-xyz-large.jpg',
  Map<String, dynamic>? meta,
}) => {
  'kind': 'track',
  'id': id,
  'title': ' Night Drive ',
  'duration': 215000,
  'policy': policy,
  'streamable': true,
  'permalink_url': 'https://soundcloud.com/someone/night-drive',
  'artwork_url': artwork,
  'publisher_metadata': meta,
  'track_authorization': 'auth-token',
  'user': {'username': 'someone', 'avatar_url': 'https://i1.sndcdn.com/avatars-000xyz-large.jpg'},
  'media': {
    'transcodings':
        transcodings ??
        [_transcoding('aac_160k', 'audio/mp4; codecs="mp4a.40.2"'), _transcoding('abr_sq', 'audio/mpegurl')],
  },
};

void main() {
  group('parseTrack', () {
    test('reads a playable track', () {
      final t = SoundcloudClient.parseTrack(_track())!;
      expect(t.id, 'sc:42');
      expect(t.soundcloudId, '42');
      expect(t.title, 'Night Drive');
      expect(t.artist, 'someone');
      expect(t.duration, const Duration(milliseconds: 215000));
      expect(t.sourceUrl, 'https://soundcloud.com/someone/night-drive');
      expect(t.artworkUrl, 'https://i1.sndcdn.com/artworks-000abc-xyz-t500x500.jpg');
      expect(t.streams, isTrue);
      expect(t.isRemote, isFalse, reason: 'YouTube-only features key off isRemote');
      expect(t.source, TrackSource.soundcloud);
      expect(t.path, isNull);
    });

    test('prefers the publisher\'s artist name', () {
      expect(SoundcloudClient.parseTrack(_track(meta: {'artist': 'Real Artist'}))!.artist, 'Real Artist');
      expect(SoundcloudClient.parseTrack(_track(meta: {'artist': '  '}))!.artist, 'someone');
    });

    test('falls back to the uploader\'s picture', () {
      expect(
        SoundcloudClient.parseTrack(_track(artwork: null))!.artworkUrl,
        'https://i1.sndcdn.com/avatars-000xyz-t500x500.jpg',
      );
    });

    test('leaves out Go+ previews, blocked tracks and streams it may not play', () {
      expect(SoundcloudClient.parseTrack(_track(policy: 'SNIP')), isNull);
      expect(SoundcloudClient.parseTrack(_track(policy: 'BLOCK')), isNull);
      expect(SoundcloudClient.parseTrack(_track(policy: 'MONETIZE')), isNotNull);
      expect(
        SoundcloudClient.parseTrack(_track(transcodings: [_transcoding('aac_160k', 'audio/mp4', snipped: true)])),
        isNull,
      );
      expect(
        SoundcloudClient.parseTrack(
          _track(transcodings: [_transcoding('aac_160k', 'audio/mp4', protocol: 'ctr-encrypted-hls')]),
        ),
        isNull,
      );
      expect(SoundcloudClient.parseTrack({..._track(), 'streamable': false}), isNull);
      expect(SoundcloudClient.parseTrack({..._track(), 'kind': 'playlist'}), isNull);
      expect(SoundcloudClient.parseTrack('nonsense'), isNull);
    });
  });

  test('pickTranscoding: AAC at the best bitrate, then MP3, Opus, the adaptive playlist', () {
    final aac96 = _transcoding('aac_96k', 'audio/mp4');
    final aac160 = _transcoding('aac_160k', 'audio/mp4');
    final mp3 = _transcoding('mp3_128k', 'audio/mpeg');
    final opus = _transcoding('opus_64k', 'audio/ogg; codecs="opus"');
    final abr = _transcoding('abr_sq', 'audio/mpegurl');
    final progressive = _transcoding('mp3_1_0', 'audio/mpeg', protocol: 'progressive');
    final drm = _transcoding('aac_256k', 'audio/mp4', protocol: 'cbc-encrypted-hls');
    expect(SoundcloudClient.pickTranscoding([abr, aac96, mp3, aac160, drm]), aac160['url']);
    expect(SoundcloudClient.pickTranscoding([abr, opus, mp3]), mp3['url']);
    expect(SoundcloudClient.pickTranscoding([abr, opus]), opus['url']);
    expect(SoundcloudClient.pickTranscoding([progressive, abr]), abr['url']);
    expect(SoundcloudClient.pickTranscoding([progressive, drm]), isNull);
    expect(SoundcloudClient.pickTranscoding([]), isNull);
  });

  test('largeArtwork swaps only the size suffix', () {
    expect(SoundcloudClient.largeArtwork('https://i1.sndcdn.com/artworks-a-large.png'), endsWith('-a-t500x500.png'));
    expect(SoundcloudClient.largeArtwork('https://x/large-thing.jpg'), 'https://x/large-thing.jpg');
    expect(SoundcloudClient.largeArtwork(null), isNull);
  });

  test('finds the web player\'s client id', () {
    const html = '''
<script crossorigin src="https://a-v2.sndcdn.com/assets/0-aa.js"></script>
<script src="https://example.com/other.js"></script>
<script crossorigin src='https://a-v2.sndcdn.com/assets/57-bb.js'></script>''';
    expect(SoundcloudClient.scriptUrls(html), [
      'https://a-v2.sndcdn.com/assets/0-aa.js',
      'https://a-v2.sndcdn.com/assets/57-bb.js',
    ]);
    expect(SoundcloudClient.clientIdIn('x={client_id:"39AVoiZVrdvJEMFLH8T0c5WGshQaAPRJ",env:"p"}'), hasLength(32));
    expect(SoundcloudClient.clientIdIn('?client_id=abc'), isNull);
  });

  test('absolutePlaylist resolves relative segments and map URIs', () {
    final base = Uri.parse('https://cdn.example/a/b/playlist.m3u8?sig=1');
    const text =
        '#EXTM3U\n#EXT-X-MAP:URI="init.mp4"\n#EXTINF:10,\ndata000.m4s?x=1\n#EXTINF:10,\nhttps://other/d1.m4s\n';
    final out = SoundcloudClient.absolutePlaylist(text, base).split('\n');
    expect(out[1], '#EXT-X-MAP:URI="https://cdn.example/a/b/init.mp4"');
    expect(out[3], 'https://cdn.example/a/b/data000.m4s?x=1');
    expect(out[5], 'https://other/d1.m4s');
  });

  group('SoundcloudLink', () {
    test('finds a track link in a shared message', () {
      final link = SoundcloudLink.parse('Listen to this! https://m.soundcloud.com/someone/night-drive?si=abc&utm=x.')!;
      expect(link.url.toString(), 'https://soundcloud.com/someone/night-drive');
      expect(link.isTrack, isTrue);
      expect(link.isPlaylist, isFalse);
      expect(link.short, isFalse);
    });

    test('reads sets, profiles, private tracks and short links', () {
      expect(SoundcloudLink.parse('https://soundcloud.com/someone/sets/best-of')!.isPlaylist, isTrue);
      final profile = SoundcloudLink.parse('https://www.soundcloud.com/someone')!;
      expect(profile.isTrack || profile.isPlaylist, isFalse);
      expect(SoundcloudLink.parse('https://soundcloud.com/someone/likes')!.isTrack, isFalse);
      expect(SoundcloudLink.parse('https://soundcloud.com/someone/demo/s-AbCdE')!.url.path, '/someone/demo/s-AbCdE');
      final short = SoundcloudLink.parse('https://on.soundcloud.com/AbC123')!;
      expect(short.short, isTrue);
      expect(short.isTrack, isFalse);
      expect(SoundcloudLink.parse('soundcloud.com/someone/night-drive')!.isTrack, isTrue);
    });

    test('ignores other sites and SoundCloud\'s own pages', () {
      expect(SoundcloudLink.parse('https://music.youtube.com/watch?v=abc'), isNull);
      expect(SoundcloudLink.parse('https://soundcloud.com/discover'), isNull);
      expect(SoundcloudLink.parse('https://soundcloud.com/'), isNull);
      expect(SoundcloudLink.parse('https://notsoundcloud.com/a/b'), isNull);
      expect(SoundcloudLink.parse('https://on.soundcloud.com/'), isNull);
      expect(SoundcloudLink.looksLikeLink('just words'), isFalse);
    });
  });

  test('a saved SoundCloud track keeps what plays it', () {
    final t = SoundcloudClient.parseTrack(_track())!;
    final back = Track.fromJson(jsonDecode(jsonEncode(t.toJson())) as Map<String, dynamic>);
    expect(back.soundcloudId, '42');
    expect(back.streams, isTrue);
    expect(back.sourceUrl, t.sourceUrl);
    final info = SongInfo.of(t);
    final again = info.toTrack();
    expect(again.soundcloudId, '42');
    expect(again.artworkUrl, t.artworkUrl);
    expect(again.title, t.title);
  });

  test('YouTube songs and files keep their sources', () {
    final yt = Track.youtube(videoId: 'abc', title: 't', artist: 'a');
    expect(yt.source, TrackSource.youtubeMusic);
    expect(yt.streams, isTrue);
    expect(yt.soundcloudId, isNull);
    final file = Track.fromUri(Uri.file('/music/a - b.flac'));
    expect(file.source, TrackSource.device);
    expect(file.streams, isFalse);
  });

  test('the uploader\'s id rides along for their page', () {
    final t = SoundcloudClient.parseTrack({
      ..._track(),
      'user': {'id': 77, 'username': 'someone'},
    })!;
    expect(t.artistId, '77');
    expect(Track.fromJson(t.toJson()).artistId, '77');
  });

  test('playlistExpiry is the first signature to run out', () {
    const text = '#EXTM3U\nhttps://a/x.m4s?expires=1800000100&Policy=p\nhttps://a/y.m4s?a=1&expires=1800000050\n';
    expect(SoundcloudClient.playlistExpiry(text), DateTime.fromMillisecondsSinceEpoch(1800000050 * 1000));
    expect(SoundcloudClient.playlistExpiry('#EXTM3U\nseg.m4s'), isNull);
  });

  test('SoundcloudCollection reads playlists and profiles', () {
    final p = SoundcloudCollection.tryParse({
      'kind': 'playlist',
      'id': 9,
      'title': ' Best of ',
      'track_count': 12,
      'artwork_url': 'https://i1.sndcdn.com/artworks-a-large.jpg',
      'user': {'username': 'someone'},
    })!;
    expect((p.kind, p.id, p.title, p.subtitle, p.count), (SoundcloudKind.playlist, '9', 'Best of', 'someone', 12));
    expect(p.artworkUrl, endsWith('-t500x500.jpg'));
    expect(p.cover.source, TrackSource.soundcloud);
    final u = SoundcloudCollection.tryParse({
      'kind': 'user',
      'id': 3,
      'username': 'Lofi Girl',
      'avatar_url': 'https://i1.sndcdn.com/avatars-b-large.jpg',
    })!;
    expect((u.kind, u.title, u.subtitle), (SoundcloudKind.user, 'Lofi Girl', ''));
    expect(SoundcloudCollection.tryParse({'kind': 'track', 'id': 1}), isNull);
  });

  test('shared SoundCloud links are taken, YouTube ones first', () {
    expect(IncomingLinks.isLink('https://soundcloud.com/someone/night-drive'), isTrue);
    expect(IncomingLinks.isLink('https://youtu.be/dQw4w9WgXcQ'), isTrue);
    expect(IncomingLinks.isLink('--verbose'), isFalse);
    expect(IncomingLinks.readSoundcloud('Hear this https://on.soundcloud.com/AbC')!.short, isTrue);
    expect(IncomingLinks.readSoundcloud('https://youtu.be/dQw4w9WgXcQ https://soundcloud.com/a/b'), isNull);
  });

  group('SoundcloudClient', () {
    const id = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ012345';
    const html = '<script crossorigin src="https://a-v2.sndcdn.com/assets/9-zz.js"></script>';

    late List<Uri> asked;
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      asked = [];
    });

    SoundcloudClient client(Future<http.Response> Function(http.Request r) answer) => SoundcloudClient(
      prefs: prefs,
      client: MockClient((r) {
        asked.add(r.url);
        if (r.url.host == 'soundcloud.com') return Future.value(http.Response(html, 200));
        if (r.url.path.endsWith('9-zz.js')) return Future.value(http.Response('a={client_id:"$id"}', 200));
        return answer(r);
      }),
    );

    test('reads the client id once, then keeps it', () async {
      final sc = client(
        (r) async => http.Response(
          jsonEncode({
            'collection': [_track(), _track(id: 7, policy: 'SNIP')],
          }),
          200,
        ),
      );
      final found = await sc.search('night');
      expect(found.map((t) => t.id), ['sc:42']);
      expect(asked.last.queryParameters['client_id'], id);
      expect(asked.last.queryParameters['q'], 'night');
      expect(prefs.getString('soundcloud.clientId.v1'), id);
      asked.clear();
      await sc.search('again');
      expect(asked, hasLength(1), reason: 'the id is not read again');
    });

    test('a refused id is read again once', () async {
      await prefs.setString('soundcloud.clientId.v1', 'stale-id-stale-id-stale-id-stale');
      final sc = client((r) async {
        if (r.url.queryParameters['client_id'] != id) return http.Response('', 401);
        return http.Response(jsonEncode({'collection': []}), 200);
      });
      expect(await sc.search('x'), isEmpty);
      expect(prefs.getString('soundcloud.clientId.v1'), id);
    });

    test('playlistFor follows the track to its HLS playlist and keeps it a moment', () async {
      final sc = client((r) async {
        if (r.url.path == '/tracks/42') return http.Response(jsonEncode(_track()), 200);
        if (r.url.path.contains('/stream/hls')) {
          expect(r.url.queryParameters['track_authorization'], 'auth-token');
          expect(r.url.path, contains('aac_160k'));
          return http.Response(jsonEncode({'url': 'https://cdn.example/x/playlist.m3u8?sig=1'}), 200);
        }
        if (r.url.host == 'cdn.example') return http.Response('#EXTM3U\n#EXTINF:10,\nseg0.m4s\n#EXT-X-ENDLIST', 200);
        return http.Response('', 404);
      });
      final text = await sc.playlistFor('42');
      expect(text, contains('https://cdn.example/x/seg0.m4s'));
      final before = asked.length;
      expect(await sc.playlistFor('42'), text);
      expect(asked.length, before, reason: 'mpv\'s second request is answered from memory');

      final source = SoundcloudAudioSource('42', client: sc);
      final whole = await source.request();
      expect(whole.contentType, SoundcloudAudioSource.hlsType);
      expect(whole.sourceLength, utf8.encode(text).length);
      final part = await source.request(2, 7);
      expect(part.offset, 2);
      expect(part.contentLength, 5);
      expect(utf8.decode(await part.stream.expand((b) => b).toList()), text.substring(2, 7));
    });

    test('a playlist\'s signatures are remembered until it is looked up again', () async {
      final sc = client((r) async {
        if (r.url.path == '/tracks/42') return http.Response(jsonEncode(_track()), 200);
        if (r.url.path.contains('/stream/hls')) {
          return http.Response(jsonEncode({'url': 'https://cdn.example/x/playlist.m3u8'}), 200);
        }
        return http.Response('#EXTM3U\n#EXTINF:10,\nseg0.m4s?expires=1800000000\n', 200);
      });
      final served = <String>[];
      sc.served.listen(served.add);
      await sc.playlistFor('42');
      expect(sc.expiresAt('42'), DateTime.fromMillisecondsSinceEpoch(1800000000 * 1000));
      expect(served, ['42']);
      final asked0 = asked.length;
      sc.forget('42');
      expect(sc.expiresAt('42'), isNull);
      await sc.playlistFor('42');
      expect(asked.length, greaterThan(asked0), reason: 'forgotten: looked up afresh');
      expect(served, ['42', '42']);
    });

    test('profiles, playlists by id and the search shelves', () async {
      final sc = client((r) async {
        switch (r.url.path) {
          case '/users/3':
            return http.Response(jsonEncode({'kind': 'user', 'id': 3, 'username': 'Lofi Girl'}), 200);
          case '/users/3/tracks':
            return http.Response(
              jsonEncode({
                'collection': [_track(id: 5)],
              }),
              200,
            );
          case '/playlists/9':
            return http.Response(
              jsonEncode({
                'kind': 'playlist',
                'id': 9,
                'title': 'Mix',
                'user': {'username': 'x'},
                'tracks': [_track()],
              }),
              200,
            );
          case '/search/playlists':
            return http.Response(
              jsonEncode({
                'collection': [
                  {
                    'kind': 'playlist',
                    'id': 9,
                    'title': 'Mix',
                    'user': {'username': 'x'},
                  },
                ],
              }),
              200,
            );
          case '/search/users':
            return http.Response(
              jsonEncode({
                'collection': [
                  {'kind': 'user', 'id': 3, 'username': 'Lofi Girl'},
                ],
              }),
              200,
            );
        }
        return http.Response('', 404);
      });
      final user = await sc.user('3');
      expect((user.kind, user.id, user.title), (SoundcloudKind.user, '3', 'Lofi Girl'));
      expect(user.tracks.single.soundcloudId, '5');
      final list = await sc.playlist('9');
      expect((list.kind, list.title, list.tracks.length), (SoundcloudKind.playlist, 'Mix', 1));
      final found = await sc.searchCollections('lofi');
      expect(found.playlists.single.title, 'Mix');
      expect(found.users.single.title, 'Lofi Girl');
    });

    test('a Go+ track is not played', () async {
      final sc = client((r) async => http.Response(jsonEncode(_track(policy: 'SNIP')), 200));
      await expectLater(sc.playlistFor('42'), throwsA(isA<SoundcloudUnplayable>()));
    });

    test('a playlist fetches the tracks that came as ids only, in order', () async {
      final sc = client((r) async {
        if (r.url.path == '/resolve') {
          return http.Response(
            jsonEncode({
              'kind': 'playlist',
              'title': 'Best of',
              'user': {'username': 'someone'},
              'artwork_url': null,
              'tracks': [
                _track(id: 1),
                {'id': 2, 'kind': 'track'},
                {'id': 3, 'kind': 'track'},
              ],
            }),
            200,
          );
        }
        if (r.url.path == '/tracks') {
          expect(r.url.queryParameters['ids'], '2,3');
          return http.Response(jsonEncode([_track(id: 3), _track(id: 2, policy: 'BLOCK')]), 200);
        }
        return http.Response('', 404);
      });
      final page = await sc.resolve(SoundcloudLink.parse('https://soundcloud.com/someone/sets/best-of')!);
      expect(page.isPlaylist, isTrue);
      expect(page.title, 'Best of');
      expect(page.subtitle, 'someone');
      expect(page.tracks.map((t) => t.soundcloudId), ['1', '3']);
      expect(page.artworkUrl, page.tracks.first.artworkUrl);
    });
  });
}

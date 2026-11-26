// ignore_for_file: experimental_member_use

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:just_audio/just_audio.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/spotify_audio_source.dart';
import 'package:riflay/services/spotify_bridge.dart';
import 'package:riflay/services/spotify_library.dart';

const _id = '4uLU6hMCjMI75M1A2tKUQC';

http.Response ok(Object body) => http.Response.bytes(utf8.encode(jsonEncode(body)), 200);

SpotifyLibraryClient clientFor(Object page) => SpotifyLibraryClient(
  client: MockClient((req) async => req.url.toString().contains('pathfinder') ? ok(page) : http.Response('', 404)),
  auth: ({bool force = false}) async => (accessToken: 'tok', clientToken: 'ct', appVersion: ''),
);

Map<String, Object?> artists(List<String> names) => {
  'items': [
    for (final n in names)
      {
        'profile': {'name': n},
      },
  ],
};

/// A bridge that is already "started": no process, a fixed address, and a count of forced sign-ins.
class FakeBridge extends SpotifyBridge {
  int freshSignIns = 0;

  @override
  Future<Uri> streamUri(String trackId) async => Uri.parse('http://127.0.0.1:9/secret/$trackId');

  @override
  Future<void> signIn({bool fresh = false}) async {
    if (fresh) freshSignIns++;
  }
}

/// The same song from YouTube Music, as the player's fallback gives it.
class FixedSource extends StreamAudioSource {
  int asked = 0;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    asked++;
    return StreamAudioResponse(
      sourceLength: 3,
      contentLength: 3,
      offset: 0,
      contentType: 'audio/webm',
      stream: Stream.value([1, 2, 3]),
    );
  }
}

void main() {
  test('a Spotify track streams, is not a YouTube song, and keeps its page', () {
    final t = Track.spotify(trackId: _id, title: 'Song', artist: 'Ada', album: 'LP');
    expect(t.id, 'sp:$_id');
    expect(t.spotifyId, _id);
    expect(t.streams, isTrue);
    expect(t.isRemote, isFalse);
    expect(t.youtubeId, isNull);
    expect(t.isDownload, isFalse);
    expect(t.source, TrackSource.spotify);
    expect(t.sourceUrl, 'https://open.spotify.com/track/$_id');
    // Saved in a playlist and read back, it is still a Spotify track.
    expect(Track.fromJson(jsonDecode(jsonEncode(t.toJson())) as Map<String, dynamic>).spotifyId, _id);
  });

  test('only a track uri gives a track id', () {
    expect(SpotifyLibraryClient.trackIdOf('spotify:track:$_id'), _id);
    expect(SpotifyLibraryClient.trackIdOf('spotify:episode:$_id'), isNull);
    expect(SpotifyLibraryClient.trackIdOf('spotify:local:a:b:c:1'), isNull);
    expect(SpotifyLibraryClient.trackIdOf('spotify:track:short'), isNull);
    expect(SpotifyLibraryClient.trackIdOf(null), isNull);
  });

  test('a playlist song carries its Spotify track, album and largest cover', () async {
    final spotify = clientFor({
      'data': {
        'playlistV2': {
          'content': {
            'totalCount': 2,
            'items': [
              {
                'itemV2': {
                  'data': {
                    '__typename': 'Track',
                    'uri': 'spotify:track:$_id',
                    'name': 'Song A',
                    'trackDuration': {'totalMilliseconds': 201000},
                    'artists': artists(['Ada', 'Bob']),
                    'albumOfTrack': {
                      'name': 'First LP',
                      'coverArt': {
                        'sources': [
                          {'url': 'https://i.scdn.co/image/small', 'width': 64},
                          {'url': 'https://i.scdn.co/image/large', 'width': 640},
                          {'url': 'https://i.scdn.co/image/medium', 'width': 300},
                        ],
                      },
                    },
                  },
                },
              },
              // No uri: still importable by name, but nothing to play from Spotify.
              {
                'itemV2': {
                  'data': {
                    '__typename': 'Track',
                    'name': 'Song B',
                    'artists': artists(['Cy']),
                  },
                },
              },
            ],
          },
        },
      },
    });
    final list = await spotify.songs(
      const SpotifyItem(kind: SpotifyItemKind.playlist, uri: 'spotify:playlist:p1', name: 'Road trip'),
    );
    final a = list.songs.first.native!;
    expect(a.spotifyId, _id);
    expect(a.title, 'Song A');
    expect(a.artist, 'Ada, Bob');
    expect(a.album, 'First LP');
    expect(a.duration, const Duration(milliseconds: 201000));
    expect(a.artworkUrl, 'https://i.scdn.co/image/large');
    expect(list.songs.last.native, isNull);
  });

  test('a Liked Songs entry takes its id from the wrapper', () async {
    final spotify = clientFor({
      'data': {
        'me': {
          'library': {
            'tracks': {
              'totalCount': 1,
              'items': [
                {
                  'track': {
                    '_uri': 'spotify:track:$_id',
                    'data': {
                      '__typename': 'Track',
                      'name': 'Liked',
                      'artists': artists(['Ada']),
                    },
                  },
                },
              ],
            },
          },
        },
      },
    });
    final list = await spotify.songs(
      const SpotifyItem(kind: SpotifyItemKind.liked, uri: 'spotify:collection:tracks', name: 'Liked Songs'),
    );
    expect(list.songs.single.native?.spotifyId, _id);
  });

  test('an album\'s songs take the album\'s name and cover', () async {
    final spotify = clientFor({
      'data': {
        'albumUnion': {
          'tracksV2': {
            'totalCount': 1,
            'items': [
              {
                'track': {
                  'uri': 'spotify:track:$_id',
                  'name': 'One',
                  'artists': artists(['Daft Punk']),
                },
              },
            ],
          },
        },
      },
    });
    final list = await spotify.songs(
      const SpotifyItem(
        kind: SpotifyItemKind.album,
        uri: 'spotify:album:a1',
        name: 'Discovery',
        imageUrl: 'https://i.scdn.co/image/album',
      ),
    );
    final t = list.songs.single.native!;
    expect(t.album, 'Discovery');
    expect(t.artworkUrl, 'https://i.scdn.co/image/album');
  });

  group('SpotifyAudioSource', () {
    test('reads the file\'s length from Content-Range', () {
      expect(SpotifyAudioSource.totalOf('bytes 100-199/5000'), 5000);
      expect(SpotifyAudioSource.totalOf('bytes */5000'), 5000);
      expect(SpotifyAudioSource.totalOf(null), isNull);
      expect(SpotifyAudioSource.totalOf('bytes 0-1/*'), isNull);
    });

    test('asks the bridge for the range mpv wants (exclusive end to inclusive)', () async {
      final seen = <String?>[];
      final source = SpotifyAudioSource(
        _id,
        bridge: FakeBridge(),
        client: MockClient((req) async {
          seen.add(req.headers['range']);
          expect(req.url.path, '/secret/$_id');
          return http.Response.bytes(
            List.filled(100, 7),
            206,
            headers: {'content-range': 'bytes 100-199/5000', 'content-length': '100'},
          );
        }),
      );
      final part = await source.request(100, 200);
      expect(seen, ['bytes=100-199']);
      expect(part.sourceLength, 5000);
      expect(part.contentLength, 100);
      expect(part.offset, 100);
      expect(part.contentType, 'audio/ogg');
      await source.request(300);
      expect(seen.last, 'bytes=300-');
    });

    test('the whole file needs no Range header', () async {
      final source = SpotifyAudioSource(
        _id,
        bridge: FakeBridge(),
        client: MockClient((req) async {
          expect(req.headers.containsKey('range'), isFalse);
          return http.Response.bytes(List.filled(50, 1), 200, headers: {'content-length': '50'});
        }),
      );
      final whole = await source.request();
      expect(whole.sourceLength, 50);
      expect(whole.offset, 0);
    });

    test('a 401 signs in with a new token once, then plays', () async {
      final bridge = FakeBridge();
      var calls = 0;
      final source = SpotifyAudioSource(
        _id,
        bridge: bridge,
        client: MockClient(
          (req) async => ++calls == 1
              ? http.Response('', 401)
              : http.Response.bytes(List.filled(10, 1), 200, headers: {'content-length': '10'}),
        ),
      );
      expect((await source.request()).contentLength, 10);
      expect(bridge.freshSignIns, 1);
      expect(calls, 2);
    });

    test('a song Spotify won\'t serve fails instead of playing silence', () async {
      final source = SpotifyAudioSource(
        _id,
        bridge: FakeBridge(),
        client: MockClient((req) async => http.Response('', 404)),
      );
      await expectLater(source.request(), throwsA(isA<SpotifyBridgeError>()));
    });

    group('without Premium', () {
      setUp(() => SpotifyAudioSource.failuresInARow = 0);

      test('a song Spotify refuses plays from YouTube Music instead', () async {
        final youtube = FixedSource();
        final source = SpotifyAudioSource(
          _id,
          bridge: FakeBridge(),
          client: MockClient((req) async => http.Response('', 502)),
          fallback: () async => youtube,
        );
        expect((await source.request()).contentType, 'audio/webm');
        // Detail stats says where the sound comes from.
        expect(source.playingInstead, same(youtube));
        // Later ranges of the song come from the same YouTube file.
        await source.request(1);
        expect(youtube.asked, 2);
      });

      test('after two refused songs the bridge is no longer asked', () async {
        var asked = 0;
        SpotifyAudioSource song() => SpotifyAudioSource(
          _id,
          bridge: FakeBridge(),
          client: MockClient((req) async {
            asked++;
            return http.Response('', 502);
          }),
          fallback: () async => FixedSource(),
        );
        for (var i = 0; i < 3; i++) {
          await song().request();
        }
        expect(asked, 2);
      });

      test('a song found nowhere fails, and one Spotify began never switches files', () async {
        final nowhere = SpotifyAudioSource(
          _id,
          bridge: FakeBridge(),
          client: MockClient((req) async => http.Response('', 404)),
          fallback: () async => null,
        );
        await expectLater(nowhere.request(), throwsA(isA<SpotifyBridgeError>()));

        var calls = 0;
        final begun = SpotifyAudioSource(
          _id,
          bridge: FakeBridge(),
          client: MockClient(
            (req) async => ++calls == 1
                ? http.Response.bytes(List.filled(10, 1), 200, headers: {'content-length': '10'})
                : http.Response('', 502),
          ),
          fallback: () async => FixedSource(),
        );
        await begun.request();
        await expectLater(begun.request(5), throwsA(isA<SpotifyBridgeError>()));
      });
    });
  });
}

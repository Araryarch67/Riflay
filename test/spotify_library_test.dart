import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riflay/services/playlist_transfer.dart';
import 'package:riflay/services/spotify_library.dart';

const _bundle = 'https://open.spotifycdn.com/cdn/build/web-player/web-player.f954508a.js';
const _calm = 'Couldn\'t read your Spotify library right now. Try again later.';

http.Response ok(Object body) => http.Response.bytes(utf8.encode(jsonEncode(body)), 200);

/// A web player bundle with the query table the real one carries.
String bundleJs(Map<String, String> hashes) =>
    'var a=1;${hashes.entries.map((e) => 'n.registerQuery("${e.key}","query","${e.value}")').join(';')};';

String hex(String c) => List.filled(64, c).join();

Map<String, Object?> libraryPage(int total, List<Object?> items) => {
  'data': {
    'me': {
      'libraryV3': {'__typename': 'LibraryPage', 'totalCount': total, 'items': items},
    },
  },
};

Map<String, Object?> playlistEntry(String id, String name, String owner) => {
  'item': {
    '__typename': 'PlaylistResponseWrapper',
    '_uri': 'spotify:playlist:$id',
    'data': {
      '__typename': 'Playlist',
      'uri': 'spotify:playlist:$id',
      'name': name,
      'ownerV2': {
        'data': {'name': owner},
      },
      'images': {
        'items': [
          {
            'sources': [
              {'url': 'https://i.scdn.co/image/$id'},
            ],
          },
        ],
      },
    },
  },
};

Map<String, Object?> artistsOf(List<String> names) => {
  'items': [
    for (final n in names)
      {
        'profile': {'name': n},
      },
  ],
};

Map<String, Object?> trackData(String name, List<String> artists, int ms) => {
  '__typename': 'Track',
  'name': name,
  'trackDuration': {'totalMilliseconds': ms},
  'artists': artistsOf(artists),
};

Map<String, Object?> playlistPage(int total, List<Object?> items) => {
  'data': {
    'playlistV2': {
      'name': 'Road trip',
      'content': {'totalCount': total, 'items': items},
    },
  },
};

Map<String, Object?> wrapped(Map<String, Object?> data) => {
  'itemV2': {'__typename': 'TrackResponseWrapper', 'data': data},
};

const _auth = (accessToken: 'tok', clientToken: 'ct', appVersion: '1.3.8.509.gabc');

class Fake {
  Fake(this.onQuery, {this.page, this.js}) {
    client = MockClient((req) async {
      final url = req.url.toString();
      if (url == 'https://open.spotify.com/') return page ?? http.Response('<html></html>', 200);
      if (url == _bundle) {
        bundleReads++;
        return js ?? http.Response('', 404);
      }
      if (url.contains('pathfinder')) {
        final body = jsonDecode(req.body) as Map<String, Object?>;
        requests.add((headers: req.headers, body: body));
        return onQuery(body, requests.length);
      }
      return http.Response('nope', 404);
    });
    spotify = SpotifyLibraryClient(
      client: client,
      auth: ({bool force = false}) async {
        if (force) forced++;
        return force ? (accessToken: 'fresh', clientToken: 'ct', appVersion: '') : _auth;
      },
    );
  }

  final http.Response Function(Map<String, Object?> body, int n) onQuery;
  final http.Response? page;
  final http.Response? js;
  late final MockClient client;
  late final SpotifyLibraryClient spotify;
  final requests = <({Map<String, String> headers, Map<String, Object?> body})>[];
  int forced = 0;
  int bundleReads = 0;

  Map<String, Object?> variables(int i) => requests[i].body['variables']! as Map<String, Object?>;
  String hashOf(int i) => ((requests[i].body['extensions']! as Map)['persistedQuery']! as Map)['sha256Hash']! as String;
}

SpotifyItem item(SpotifyItemKind kind, String uri, {String name = 'X'}) =>
    SpotifyItem(kind: kind, uri: uri, name: name);

void main() {
  test('sends the web player headers and a persisted query', () async {
    final f = Fake(
      (b, n) => ok({
        'data': {
          'me': {
            'profile': {'name': 'Ada'},
          },
        },
      }),
    );
    // No bundle: the built-in hashes are used, profileAttributes has none.
    expect(await f.spotify.profileName(), isNull);
    expect(f.requests, isEmpty);

    final g = Fake((b, n) => ok(libraryPage(0, [])));
    await g.spotify.albums();
    final h = g.requests.single.headers;
    expect(h['authorization'], 'Bearer tok');
    expect(h['client-token'], 'ct');
    expect(h['app-platform'], 'WebPlayer');
    expect(h['spotify-app-version'], '1.3.8.509.gabc');
    expect(h['content-type'], startsWith('application/json'));
    expect(h['accept'], 'application/json');
    expect(h['accept-language'], 'en');
    final body = g.requests.single.body;
    expect(body['operationName'], 'libraryV3');
    expect(g.hashOf(0), startsWith('390c78e5'));
    expect(g.variables(0), containsPair('filters', ['Albums']));
    expect(g.variables(0), containsPair('limit', 50));
  });

  test('reads the query hashes from the web player bundle once', () async {
    final f = Fake(
      (b, n) => ok(
        b['operationName'] == 'profileAttributes'
            ? {
                'data': {
                  'me': {
                    'profile': {'name': 'Ada'},
                  },
                },
              }
            : libraryPage(0, []),
      ),
      page: http.Response('<script src="$_bundle"></script><script src="https://x/vendor~web-player.aaaa.js">', 200),
      js: http.Response(
        bundleJs({
          'libraryV3': hex('a'),
          'fetchLibraryTracks': hex('b'),
          'fetchPlaylist': hex('c'),
          'getAlbum': hex('d'),
          'profileAttributes': hex('e'),
        }),
        200,
      ),
    );
    expect(await f.spotify.profileName(), 'Ada');
    await f.spotify.albums();
    expect(f.hashOf(0), hex('e'));
    expect(f.hashOf(1), hex('a'));
    expect(f.bundleReads, 1);
  });

  test('falls back to the built-in hashes when the page can\'t be read', () async {
    final f = Fake((b, n) => ok(libraryPage(0, [])), page: http.Response('down', 503));
    await f.spotify.playlists();
    expect(f.hashOf(0), startsWith('390c78e5'));
  });

  test('rescans once when Spotify no longer knows a hash', () async {
    final f = Fake(
      (b, n) => n == 1
          ? ok({
              'errors': [
                {'message': 'PersistedQueryNotFound'},
              ],
            })
          : ok(libraryPage(0, [])),
      page: http.Response(_bundle, 200),
      js: http.Response(
        bundleJs({
          'libraryV3': hex('a'),
          'fetchLibraryTracks': hex('b'),
          'fetchPlaylist': hex('c'),
          'getAlbum': hex('d'),
        }),
        200,
      ),
    );
    await f.spotify.albums();
    expect(f.requests, hasLength(2));
    expect(f.bundleReads, 2);
  });

  test('lists playlists across pages, Liked Songs first, folders skipped', () async {
    final page1 = [
      playlistEntry('p1', 'Road trip', 'Ada'),
      {
        'item': {
          '__typename': 'LibraryFolderResponseWrapper',
          '_uri': 'spotify:user:ada:folder:f1',
          'data': {'__typename': 'Folder', 'name': 'Old stuff'},
        },
      },
      for (var i = 0; i < 48; i++) playlistEntry('pa$i', 'Filler $i', 'Ada'),
    ];
    final page2 = [
      {
        'item': {
          '__typename': 'LibraryPseudoPlaylistResponseWrapper',
          '_uri': 'spotify:collection:tracks',
          'data': {'__typename': 'PseudoPlaylist', 'uri': 'spotify:collection:tracks', 'name': '', 'count': 321},
        },
      },
      playlistEntry('p1', 'Road trip', 'Ada'),
      playlistEntry('p2', 'Focus', 'Bob'),
      {'item': 'garbage'},
    ];
    final f = Fake((b, n) {
      final offset = (b['variables']! as Map)['offset'] as int;
      return ok(libraryPage(54, offset == 0 ? page1 : page2));
    });
    final list = await f.spotify.playlists();
    expect(f.requests, hasLength(2));
    expect(f.variables(0), allOf(containsPair('offset', 0), containsPair('filters', ['Playlists'])));
    expect(f.variables(0), containsPair('flatten', true));
    expect(f.variables(0), containsPair('includeFoldersWhenFlattening', true));
    expect(f.variables(0), containsPair('features', ['LIKED_SONGS']));
    expect(f.variables(1), containsPair('offset', 50));

    expect(list.first.kind, SpotifyItemKind.liked);
    expect(list.first.name, 'Liked Songs');
    expect(list.first.count, 321);
    expect(list.map((i) => i.uri).where((u) => u == 'spotify:playlist:p1'), hasLength(1));
    expect(list.any((i) => i.name == 'Old stuff'), isFalse);
    final focus = list.firstWhere((i) => i.uri == 'spotify:playlist:p2');
    expect(focus.kind, SpotifyItemKind.playlist);
    expect(focus.subtitle, 'Bob');
    expect(focus.imageUrl, 'https://i.scdn.co/image/p2');
    expect(list, hasLength(51));
  });

  test('parses a Liked Songs entry sent as an unknown wrapper', () async {
    final f = Fake(
      (b, n) => ok(
        libraryPage(1, [
          {
            'item': {
              '__typename': 'UnknownTypeWrapper',
              '_uri': 'spotify:collection:tracks',
              'data': {'__typename': 'UnknownType'},
            },
          },
        ]),
      ),
    );
    final list = await f.spotify.playlists();
    expect(list.single.kind, SpotifyItemKind.liked);
    expect(list.single.name, 'Liked Songs');
  });

  test('parses albums and artists', () async {
    final f = Fake((b, n) {
      final filter = ((b['variables']! as Map)['filters'] as List).single;
      return ok(
        filter == 'Albums'
            ? libraryPage(1, [
                {
                  'item': {
                    '__typename': 'AlbumResponseWrapper',
                    '_uri': 'spotify:album:a1',
                    'data': {
                      '__typename': 'Album',
                      'uri': 'spotify:album:a1',
                      'name': 'Discovery',
                      'artists': artistsOf(['Daft Punk']),
                      'coverArt': {
                        'sources': [
                          {'url': 'https://i.scdn.co/image/cover'},
                        ],
                      },
                    },
                  },
                },
              ])
            : libraryPage(1, [
                {
                  'item': {
                    '__typename': 'ArtistResponseWrapper',
                    '_uri': 'spotify:artist:r1',
                    'data': {
                      '__typename': 'Artist',
                      'uri': 'spotify:artist:r1',
                      'profile': {'name': 'Air'},
                      'visuals': {
                        'avatarImage': {
                          'sources': [
                            {'url': 'https://i.scdn.co/image/air'},
                          ],
                        },
                      },
                    },
                  },
                },
              ]),
      );
    });
    final albums = await f.spotify.albums();
    expect(albums.single.kind, SpotifyItemKind.album);
    expect(albums.single.name, 'Discovery');
    expect(albums.single.subtitle, 'Daft Punk');
    expect(albums.single.imageUrl, 'https://i.scdn.co/image/cover');
    final artists = await f.spotify.artists();
    expect(artists.single.kind, SpotifyItemKind.artist);
    expect(artists.single.name, 'Air');
    expect(artists.single.imageUrl, 'https://i.scdn.co/image/air');
  });

  test('reads a playlist, skipping episodes and local files', () async {
    final f = Fake(
      (b, n) => ok(
        playlistPage(4, [
          wrapped(trackData('Song A', ['Ada', 'Bob'], 201000)),
          wrapped({'__typename': 'Episode', 'name': 'A podcast'}),
          wrapped({'__typename': 'LocalTrack', 'name': 'My rip'}),
          wrapped({
            ...trackData('', ['Ada'], 1000),
          }),
          wrapped(trackData('Song B', ['Cy'], 180000)),
        ]),
      ),
    );
    final list = await f.spotify.songs(item(SpotifyItemKind.playlist, 'spotify:playlist:p1', name: 'Road trip'));
    expect(list.title, 'Road trip');
    expect(list.service, 'Spotify');
    expect(list.total, 4);
    expect(list.songs.map((s) => s.title), ['Song A', 'Song B']);
    expect(list.songs.first.artist, 'Ada, Bob');
    expect(list.songs.first.duration, const Duration(milliseconds: 201000));
    expect(f.variables(0), allOf(containsPair('uri', 'spotify:playlist:p1'), containsPair('limit', 100)));
    expect(f.variables(0), containsPair('enableWatchFeedEntrypoint', false));
  });

  test('reads Liked Songs in pages of 50 and stops at max', () async {
    Map<String, Object?> likedPage(int from, int count) => {
      'data': {
        'me': {
          'library': {
            'tracks': {
              '__typename': 'UserLibraryTrackPage',
              'totalCount': 120,
              'items': [
                for (var i = from; i < from + count; i++)
                  {
                    'track': {
                      '_uri': 'spotify:track:t$i',
                      'data': trackData('Song $i', ['Ada'], 1000 * (i + 1)),
                    },
                  },
              ],
            },
          },
        },
      },
    };
    final f = Fake((b, n) {
      final offset = (b['variables']! as Map)['offset'] as int;
      return ok(likedPage(offset, offset + 50 <= 120 ? 50 : 120 - offset));
    });
    final liked = item(SpotifyItemKind.liked, 'spotify:collection:tracks');
    final all = await f.spotify.songs(liked);
    expect(all.songs, hasLength(120));
    expect(all.total, 120);
    expect(f.requests, hasLength(3));
    expect(f.variables(0), containsPair('limit', 50));
    expect(all.songs[119].title, 'Song 119');

    final g = Fake((b, n) {
      final offset = (b['variables']! as Map)['offset'] as int;
      return ok(likedPage(offset, offset + 50 <= 120 ? 50 : 120 - offset));
    });
    final capped = await g.spotify.songs(liked, max: 60);
    expect(capped.songs, hasLength(60));
    expect(capped.total, 120);
    expect(g.requests, hasLength(2));
  });

  test('reads an album across pages', () async {
    Map<String, Object?> albumPage(int from, int count) => {
      'data': {
        'albumUnion': {
          'name': 'Discovery',
          'tracksV2': {
            'totalCount': 60,
            'items': [
              for (var i = from; i < from + count; i++)
                {
                  'track': {
                    'name': 'Track $i',
                    'duration': {'totalMilliseconds': 200000},
                    'artists': artistsOf(['Daft Punk']),
                  },
                },
            ],
          },
        },
      },
    };
    final f = Fake((b, n) {
      final offset = (b['variables']! as Map)['offset'] as int;
      return ok(albumPage(offset, offset == 0 ? 50 : 10));
    });
    final list = await f.spotify.songs(item(SpotifyItemKind.album, 'spotify:album:a1', name: 'Discovery'));
    expect(list.songs, hasLength(60));
    expect(list.songs.first.duration, const Duration(seconds: 200));
    expect(f.variables(0), allOf(containsPair('uri', 'spotify:album:a1'), containsPair('locale', '')));
  });

  test('artists can\'t be imported as songs', () {
    final f = Fake((b, n) => ok({}));
    expect(() => f.spotify.songs(item(SpotifyItemKind.artist, 'spotify:artist:r1')), throwsArgumentError);
  });

  test('a 401 refreshes the sign-in and retries', () async {
    final f = Fake((b, n) => n == 1 ? http.Response('', 401) : ok(libraryPage(0, [])));
    await f.spotify.albums();
    expect(f.forced, 1);
    expect(f.requests, hasLength(2));
    expect(f.requests[1].headers['authorization'], 'Bearer fresh');
    expect(f.requests[1].headers.containsKey('spotify-app-version'), isFalse);
  });

  test('a second 401 means signed out', () async {
    final f = Fake((b, n) => http.Response('', 401));
    await expectLater(f.spotify.albums(), throwsA(isA<SpotifySignedOut>()));
    expect(f.forced, 1);
    expect(const SpotifySignedOut().toString(), 'Your Spotify sign-in has expired. Sign in again.');
  });

  test('waits and retries when throttled', () async {
    final f = Fake((b, n) => n < 3 ? http.Response('', 429, headers: {'retry-after': '0'}) : ok(libraryPage(0, [])));
    await f.spotify.albums();
    expect(f.requests, hasLength(3));
  });

  test('a server error ends as one calm sentence', () async {
    final f = Fake((b, n) => http.Response('{"secret":"stack trace"}', 500));
    await expectLater(
      f.spotify.playlists(),
      throwsA(isA<PlaylistTransferError>().having((e) => e.message, 'message', _calm)),
    );
    final g = Fake(
      (b, n) => ok({
        'errors': [
          {'message': 'boom'},
        ],
      }),
    );
    await expectLater(
      g.spotify.albums(),
      throwsA(isA<PlaylistTransferError>().having((e) => e.message, 'message', _calm)),
    );
  });
}

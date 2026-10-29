import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riflay/services/ytmusic_play_report.dart';
import 'package:riflay/services/ytmusic_web.dart';

Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/fixtures/$name.json').readAsStringSync()) as Map<String, dynamic>;

Map<String, dynamic>? find(Object? node, String key) {
  if (node is Map<String, dynamic>) {
    if (node[key] is Map<String, dynamic>) return node[key] as Map<String, dynamic>;
    for (final v in node.values) {
      final r = find(v, key);
      if (r != null) return r;
    }
  } else if (node is List) {
    for (final v in node) {
      final r = find(v, key);
      if (r != null) return r;
    }
  }
  return null;
}

/// Answers browse requests with the fixture named for the browseId; records every request.
({YtMusicWeb web, List<({String endpoint, Map<String, dynamic> body})> sent}) fake(
  Map<String, Map<String, dynamic>> pages, {
  String cookies = '',
}) {
  final sent = <({String endpoint, Map<String, dynamic> body})>[];
  final client = MockClient((req) async {
    final endpoint = req.url.path.replaceFirst('/youtubei/v1/', '');
    final body = req.method == 'POST' ? jsonDecode(req.body) as Map<String, dynamic> : <String, dynamic>{};
    sent.add((endpoint: endpoint, body: body));
    if (endpoint == 'browse') {
      return http.Response.bytes(utf8.encode(jsonEncode(pages[body['browseId']] ?? <String, dynamic>{})), 200);
    }
    return http.Response.bytes(utf8.encode('{}'), 200);
  });
  return (web: YtMusicWeb(cookies: cookies, visitorData: '', client: client), sent: sent);
}

const _signedIn = '__Secure-3PAPISID=abc; SID=x';

void main() {
  group('moods and genres', () {
    test('groups the tiles with their params', () async {
      final f = fake({'FEmusic_moods_and_genres': fixture('ytm_moods_and_genres')});
      final groups = await f.web.moodsAndGenres();
      expect(groups.map((g) => g.title), ['Moods & moments', 'Genres']);
      expect(groups.first.moods, hasLength(4));
      expect(groups.first.moods.first.title, 'Chill');
      expect(groups.first.moods.first.params, 'ggMPOg1uX1JOQWZFeDByc2Jm');
      expect(groups.first.moods.first.color, isNotNull);
    });

    test('a category asks with its params and yields playlist cards', () async {
      final f = fake({'FEmusic_moods_and_genres_category': fixture('ytm_mood_category')});
      final shelves = await f.web.moodShelves('ggMPOg1uX1JOQWZFeDByc2Jm');
      expect(f.sent.single.body['browseId'], 'FEmusic_moods_and_genres_category');
      expect(f.sent.single.body['params'], 'ggMPOg1uX1JOQWZFeDByc2Jm');
      expect(shelves, hasLength(2));
      expect(shelves.first.title, 'Coffee shop blends');
      expect(shelves.first.cards, hasLength(3));
      expect(shelves.first.cards.first.browseId, startsWith('VLRD'));
    });
  });

  group('new releases', () {
    test('albums become cards, music videos become songs', () async {
      final f = fake({'FEmusic_new_releases': fixture('ytm_new_releases')});
      final shelves = await f.web.shelves('FEmusic_new_releases');
      expect(shelves.map((s) => s.title), ['Albums & singles', 'Music videos']);
      expect(shelves.first.cards.first.browseId, startsWith('MPRE'));
      expect(shelves.last.tracks, isNotEmpty);
      expect(shelves.last.tracks.first.videoId, isNotEmpty);
    });
  });

  group('save to library', () {
    test('an album goes by its audio playlist id; signed out shows not saved', () {
      final s = YtMusicWeb.saveStateOf(fixture('ytm_album'), 'MPREb_UlujxjivYqb')!;
      expect(s.playlistId, startsWith('OLAK5uy_'));
      expect(s.saved, isFalse);
    });

    test('the signed-in bookmark button tells the state and the playlist', () {
      final page = fixture('ytm_album');
      final header = find(page, 'musicResponsiveHeaderRenderer')!;
      final toggle = (header['buttons'] as List)
          .map((b) => (b as Map)['toggleButtonRenderer'])
          .firstWhere((t) => t != null)!;
      toggle['isToggled'] = true;
      toggle['defaultServiceEndpoint'] = {
        'likeEndpoint': {
          'status': 'INDIFFERENT',
          'target': {'playlistId': 'OLAK5uy_signedIn'},
        },
      };
      final s = YtMusicWeb.saveStateOf(page, 'MPREb_x')!;
      expect(s.saved, isTrue);
      expect(s.playlistId, 'OLAK5uy_signedIn');
    });

    test('your own playlists have nothing to save', () {
      final page = {
        'contents': {
          'musicEditablePlaylistDetailHeaderRenderer': {'header': <String, dynamic>{}},
        },
      };
      expect(YtMusicWeb.saveStateOf(page, 'VLPL1'), isNull);
    });

    test('saving and removing send like / removelike with the playlist as target', () async {
      final f = fake(const {}, cookies: _signedIn);
      await f.web.saveToLibrary('OLAK5uy_a', saved: true);
      await f.web.saveToLibrary('OLAK5uy_a', saved: false);
      expect(f.sent.map((s) => s.endpoint), ['like/like', 'like/removelike']);
      expect(f.sent.first.body['target'], {'playlistId': 'OLAK5uy_a'});
    });
  });

  group('play reports', () {
    test('the nonce is 16 characters from the web player alphabet', () {
      for (var i = 0; i < 50; i++) {
        expect(YtMusicWeb.newCpn(), matches(RegExp(r'^[A-Za-z0-9_-]{16}$')));
      }
    });

    test('reportPlay reads the stats URL from the player reply and fetches it with ver, c and cpn', () async {
      final requests = <http.Request>[];
      final client = MockClient((req) async {
        requests.add(req);
        if (req.url.path.endsWith('/player')) {
          return http.Response(
            jsonEncode({
              'playbackTracking': {
                'videostatsPlaybackUrl': {'baseUrl': 'https://s.youtube.com/api/stats/playback?docid=VID&ei=E'},
              },
            }),
            200,
          );
        }
        return http.Response('', 204);
      });
      await YtMusicWeb(cookies: _signedIn, visitorData: '', client: client).reportPlay('VID');
      expect(requests, hasLength(2));
      expect(jsonDecode(requests.first.body)['videoId'], 'VID');
      final q = requests.last.url.queryParameters;
      expect(requests.last.method, 'GET');
      expect(q['docid'], 'VID');
      expect(q['ver'], '2');
      expect(q['c'], 'WEB_REMIX');
      expect(q['cpn'], hasLength(16));
      expect(requests.last.headers['authorization'], startsWith('SAPISIDHASH '));
    });

    test('a player reply without a stats URL is an error, not a request', () async {
      final f = fake(const {}, cookies: _signedIn);
      await expectLater(f.web.reportPlay('VID'), throwsA(isA<YtMusicWebError>()));
      expect(f.sent.map((s) => s.endpoint), ['player']);
    });
  });

  group('when a play counts', () {
    bool tick(PlayReportClock c, int seconds, {String id = 'a', bool playing = true, bool ended = false}) => c.tick(
      trackId: id,
      position: Duration(seconds: seconds),
      playing: playing,
      ended: ended,
    );

    test('after 30 seconds of listening, once', () {
      final c = PlayReportClock();
      final fired = [for (var s = 0; s <= 60; s++) tick(c, s)];
      expect(fired.where((f) => f), hasLength(1));
      expect(fired.indexOf(true), 30);
    });

    test('pausing does not count', () {
      final c = PlayReportClock();
      for (var s = 0; s <= 100; s++) {
        expect(tick(c, 0, playing: false), isFalse);
      }
      expect(c.heard, Duration.zero);
    });

    test('a seek forward does not count as listening', () {
      final c = PlayReportClock();
      for (var s = 0; s < 10; s++) {
        tick(c, s);
      }
      expect(tick(c, 120), isFalse);
      expect(c.heard, lessThan(const Duration(seconds: 11)));
    });

    test('a short song counts when it ends', () {
      final c = PlayReportClock();
      for (var s = 0; s < 20; s++) {
        expect(tick(c, s), isFalse);
      }
      expect(tick(c, 20, ended: true), isTrue);
      expect(tick(c, 20, ended: true), isFalse);
    });

    test('ending after it was reported does not report twice', () {
      final c = PlayReportClock();
      for (var s = 0; s <= 31; s++) {
        tick(c, s);
      }
      expect(tick(c, 200, ended: true), isFalse);
    });

    test('a skipped song is not reported; the next one starts again from zero', () {
      final c = PlayReportClock();
      for (var s = 0; s < 10; s++) {
        tick(c, s);
      }
      final fired = [for (var s = 0; s <= 35; s++) tick(c, s, id: 'b')];
      expect(fired.where((f) => f), hasLength(1));
    });

    test('repeating one song reports each play', () {
      final c = PlayReportClock();
      var reports = 0;
      for (var round = 0; round < 3; round++) {
        for (var s = 0; s <= 40; s++) {
          if (tick(c, s)) reports++;
        }
        if (tick(c, 40, ended: true)) reports++;
        tick(c, 0); // the player starts it again
      }
      expect(reports, 3);
    });

    test('nothing playing, nothing reported', () {
      final c = PlayReportClock();
      expect(c.tick(trackId: null, position: const Duration(seconds: 50), playing: true, ended: true), isFalse);
    });
  });
}

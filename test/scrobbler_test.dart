import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/play_history.dart';
import 'package:riflay/services/scrobbler.dart';
import 'package:riflay/services/smart_playlists.dart';

Track song(String name, {String artist = 'Artist', Duration? length = const Duration(minutes: 3)}) => Track(
  id: 'file:///music/$name.flac',
  uri: Uri.parse('file:///music/$name.flac'),
  title: name,
  artist: artist,
  album: 'Album',
  duration: length,
);

void main() {
  const s = Duration(seconds: 1);
  final start = DateTime.utc(2026, 10, 31, 12);

  group('when a play is a scrobble', () {
    /// Plays [t] for [seconds] of its own time, one look a second, the clock moving along.
    List<ScrobbleEvent> listen(ScrobbleTracker tr, Track t, int seconds, {int from = 0}) => [
      for (var i = from; i <= from + seconds; i++) ...tr.tick(track: t, position: s * i, playing: true, ended: false),
    ];

    test('now playing at once, the scrobble at half the song', () {
      final tr = ScrobbleTracker(now: () => start);
      final first = tr.tick(track: song('a'), position: Duration.zero, playing: true, ended: false);
      expect(first.single, isA<NowPlaying>());
      expect(listen(tr, song('a'), 88, from: 1).whereType<Scrobbled>(), isEmpty);
      final out = listen(tr, song('a'), 3, from: 89);
      expect(out.whereType<Scrobbled>(), hasLength(1));
      expect(out.whereType<Scrobbled>().single.listen.startedAt, start.millisecondsSinceEpoch ~/ 1000);
    });

    test('a long song counts after 4 minutes', () {
      final tr = ScrobbleTracker();
      final long = song('long', length: const Duration(minutes: 20));
      expect(listen(tr, long, 239).whereType<Scrobbled>(), isEmpty);
      expect(listen(tr, long, 2, from: 240).whereType<Scrobbled>(), hasLength(1));
    });

    test('a song of 30 seconds or less never counts', () {
      final tr = ScrobbleTracker();
      final short = song('short', length: const Duration(seconds: 25));
      expect(listen(tr, short, 25).whereType<Scrobbled>(), isEmpty);
      expect(tr.tick(track: short, position: s * 25, playing: false, ended: true), isEmpty);
    });

    test('seeking adds nothing', () {
      final tr = ScrobbleTracker();
      final a = song('a');
      listen(tr, a, 10);
      expect(tr.tick(track: a, position: s * 170, playing: true, ended: false), isEmpty);
      expect(listen(tr, a, 5, from: 171).whereType<Scrobbled>(), isEmpty);
    });

    test('once per play; repeating the song is a new play', () {
      final tr = ScrobbleTracker();
      final a = song('a');
      expect(listen(tr, a, 100).whereType<Scrobbled>(), hasLength(1));
      expect(listen(tr, a, 70, from: 101).whereType<Scrobbled>(), isEmpty);
      expect(tr.tick(track: a, position: s * 180, playing: false, ended: true), isEmpty);
      final again = listen(tr, a, 95);
      expect(again.whereType<NowPlaying>(), hasLength(1));
      expect(again.whereType<Scrobbled>(), hasLength(1));
    });

    test('songs with no real artist are not sent', () {
      final tr = ScrobbleTracker();
      expect(listen(tr, song('a', artist: Track.unknownArtist), 120), isEmpty);
    });
  });

  group('Last.fm', () {
    test('signs a request with the sorted parameters and the secret, leaving out format', () {
      final fm = LastFm(http.Client(), apiKey: 'key', secret: 'sec');
      final sig = fm.sign({'method': 'auth.getToken', 'api_key': 'key', 'format': 'json'});
      expect(sig, md5Hex('api_keykeymethodauth.getTokensec'));
    });

    test('scrobbles a batch with numbered fields; error 9 disconnects', () async {
      late Map<String, String> sent;
      var answer = '{"scrobbles":{}}';
      final fm = LastFm(
        MockClient((r) async {
          sent = Uri.splitQueryString(r.body);
          return http.Response(answer, 200);
        }),
        apiKey: 'key',
        secret: 'sec',
      )..session = 'sk';
      final l = Listen.of(song('a'), startedAt: start)!;
      await fm.submit([l, l]);
      expect(sent['method'], 'track.scrobble');
      expect(sent['artist[1]'], 'Artist');
      expect(sent['timestamp[0]'], '${l.startedAt}');
      expect(sent['duration[0]'], '180');
      expect(sent['api_sig'], isNotEmpty);

      answer = '{"error":9,"message":"Invalid session key"}';
      await expectLater(fm.submit([l]), throwsA(isA<ScrobbleError>().having((e) => e.signedOut, 'signedOut', true)));
    });
  });

  group('ListenBrainz', () {
    test('sends a listen with its start time and Riflay as the player', () async {
      late Map<String, dynamic> body;
      late Map<String, String> headers;
      final lb = ListenBrainz(
        MockClient((r) async {
          headers = r.headers;
          body = jsonDecode(r.body) as Map<String, dynamic>;
          return http.Response('{"status":"ok"}', 200);
        }),
      )..token = 'tok';
      final yt = Track.youtube(videoId: 'abc', title: 'Song', artist: 'Band');
      await lb.submit([Listen.of(yt, startedAt: start)!]);
      expect(headers['Authorization'], 'Token tok');
      expect(body['listen_type'], 'single');
      final p = (body['payload'] as List).single as Map<String, dynamic>;
      expect(p['listened_at'], start.millisecondsSinceEpoch ~/ 1000);
      final meta = p['track_metadata'] as Map<String, dynamic>;
      expect(meta['artist_name'], 'Band');
      expect((meta['additional_info'] as Map)['origin_url'], 'https://music.youtube.com/watch?v=abc');
    });

    test('a token that isn\'t valid is not kept', () async {
      final lb = ListenBrainz(MockClient((_) async => http.Response('{"valid":false}', 200)));
      await expectLater(lb.connect('nope'), throwsA(isA<ScrobbleError>()));
      expect(lb.connected, isFalse);
    });
  });

  group('the queue', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('scrobble'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('keeps listens while offline, saves them, and sends them later in order', () async {
      var online = false;
      final got = <int>[];
      http.Client client() => MockClient((r) async {
        if (!online) throw const SocketException('offline');
        final b = jsonDecode(r.body) as Map<String, dynamic>;
        got.addAll([for (final p in b['payload'] as List) (p as Map)['listened_at'] as int]);
        return http.Response('{}', 200);
      });
      final file = File('${dir.path}/scrobbling.json');
      final a = Scrobbler(client: client(), file: file)..listenBrainz.token = 'tok';
      final l1 = Listen.of(song('a'), startedAt: start)!;
      final l2 = Listen.of(song('b'), startedAt: start.add(const Duration(minutes: 3)))!;
      a.handle([Scrobbled(l1), Scrobbled(l2)]);
      await a.settled();
      expect(a.pending(a.listenBrainz), 2);
      a.dispose();

      // A new start reads the sign-in and the waiting listens back.
      online = true;
      final b = Scrobbler(client: client(), file: file);
      await b.load();
      expect(b.listenBrainz.connected, isTrue);
      expect(b.pending(b.listenBrainz), 2);
      await b.send();
      expect(b.pending(b.listenBrainz), 0);
      expect(got, [l1.startedAt, l2.startedAt]);
      b.dispose();
    });

    test('nothing is queued for a service that isn\'t connected; Last.fm is hidden without a key', () {
      final sc = Scrobbler(client: MockClient((_) async => http.Response('{}', 200)));
      expect(sc.services.map((s) => s.label), ['ListenBrainz']);
      sc.handle([Scrobbled(Listen.of(song('a'), startedAt: start)!)]);
      expect(sc.pending(sc.listenBrainz), 0);
      sc.dispose();
    });
  });

  group('bringing past listens in', () {
    test('ListenBrainz pages back by time; songs match the library, a video, or stay stats-only', () async {
      final asked = <String?>[];
      final pages = {
        null: [
          {
            'listened_at': 3000,
            'track_metadata': {'artist_name': 'Artist', 'track_name': 'a'},
          },
          {
            'listened_at': 2000,
            'track_metadata': {
              'artist_name': 'Band',
              'track_name': 'Video song',
              'additional_info': {'origin_url': 'https://music.youtube.com/watch?v=abcdefghijk', 'duration_ms': 200000},
            },
          },
        ],
        '2000': [
          {
            'listened_at': 1000,
            'track_metadata': {'artist_name': 'Someone', 'track_name': 'Elsewhere'},
          },
        ],
        '1000': <Object>[],
      };
      final sc = Scrobbler(
        client: MockClient((r) async {
          final before = r.url.queryParameters['max_ts'];
          asked.add(before);
          return http.Response(
            jsonEncode({
              'payload': {'listens': pages[before]},
            }),
            200,
          );
        }),
      );
      sc.listenBrainz
        ..token = 'tok'
        ..user = 'me';
      final history = PlayHistory();
      final library = [song('a')];
      expect(await sc.importHistory(sc.listenBrainz, history: history, library: library), 3);
      expect(asked, [null, '2000', '1000']);
      expect(history.length, 3);
      // Oldest first, as the history keeps them.
      expect([for (var i = 0; i < 3; i++) history.atSec(i)], [1000, 2000, 3000]);
      expect(history.playsOf(song('a').id), 1, reason: 'matched to the file in the library');
      expect(history.playsOf('yt:abcdefghijk'), 1);
      final other = history.songInfo(history.songIndex(0));
      expect(other.imported, isTrue);

      // Again: everything is already there.
      expect(await sc.importHistory(sc.listenBrainz, history: history, library: library), 0);
      expect(history.length, 3);

      // Songs with nothing to play stay out of Most played.
      final lists = SmartPlaylists.compute(library, history);
      expect(lists[SmartList.mostPlayed]!.tracks.map((t) => t.id), isNot(contains(startsWith('imported:'))));
      sc.dispose();
    });

    test('a play Riflay itself sent is not counted twice', () async {
      final history = PlayHistory();
      // Kept here when it ended (started at 10,000, 3 minutes long).
      history.record(song('a'), const Duration(minutes: 3), at: DateTime.fromMillisecondsSinceEpoch(10180 * 1000));
      final added = await history.importPlays([
        ImportedPlay(SongInfo.of(song('a')), 10000, 180),
        ImportedPlay(SongInfo.of(song('a')), 50000, 180),
      ]);
      expect(added, 1);
      expect(history.length, 2);
    });

    test('the duplicate window holds at its edges, among many plays of one song', () async {
      final history = PlayHistory();
      final a = SongInfo.of(song('a'));
      // Kept plays at 10,000, 20,000 … 1,000,000 (each dated when it ended).
      await history.importPlays([for (var t = 10000; t <= 1000000; t += 10000) ImportedPlay(a, t, 1)]);
      expect(history.length, 100);
      final added = await history.importPlays([
        ImportedPlay(a, 500120, 60), // 120 s after a kept play: the same one
        ImportedPlay(a, 500121, 60), // 121 s after: a new play
        ImportedPlay(a, 509340, 60), // ends 600 s before the next kept play: the same one
        ImportedPlay(a, 1, 60), // before everything
        ImportedPlay(a, 1, 60), // the same listen twice in one import
      ]);
      expect(added, 2);
      expect(history.atSec(0), 1, reason: 'still oldest first');
    });

    test('Last.fm pages through recent tracks and leaves out the one playing now', () async {
      final fm =
          LastFm(
              MockClient((r) async {
                final page = r.url.queryParameters['page'];
                return http.Response(
                  jsonEncode({
                    'recenttracks': {
                      '@attr': {'totalPages': '2'},
                      'track': page == '1'
                          ? [
                              {
                                'artist': {'#text': 'Artist'},
                                'name': 'now',
                                '@attr': {'nowplaying': 'true'},
                              },
                              {
                                'artist': {'#text': 'Artist'},
                                'name': 'b',
                                'album': {'#text': ''},
                                'date': {'uts': '2000'},
                              },
                            ]
                          // One track comes back as an object.
                          : {
                              'artist': {'#text': 'Artist'},
                              'name': 'a',
                              'album': {'#text': 'Album'},
                              'date': {'uts': '1000'},
                            },
                    },
                  }),
                  200,
                );
              }),
              apiKey: 'key',
              secret: 'sec',
            )
            ..session = 'sk'
            ..user = 'me';
      final got = await fm.history().expand((p) => p).toList();
      expect(got.map((l) => (l.title, l.startedAt, l.album)), [('b', 2000, null), ('a', 1000, 'Album')]);
    });
  });
}

String md5Hex(String s) => md5.convert(utf8.encode(s)).toString();

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/scrobbler.dart';

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
}

String md5Hex(String s) => md5.convert(utf8.encode(s)).toString();

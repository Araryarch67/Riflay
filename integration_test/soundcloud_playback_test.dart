// Real Riflay playback of a SoundCloud track through just_audio + libmpv, in a headless Weston.
// First an HLS stream made by ffmpeg and served here (SoundCloud's api-v2 answered by a fake client), then (opt in
// with RIFLAY_LIVE_SOUNDCLOUD) a live track. Uses a fresh XDG_DATA_HOME and ao=null; no account or speaker output.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:media_kit/media_kit.dart' show NativePlayer;
import 'package:riflay/models/track.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/services/soundcloud.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a SoundCloud track plays and seeks through its HLS playlist', (tester) async {
    JustAudioMediaKit.ensureInitialized(linux: true, windows: true);
    SharedPreferences.setMockInitialValues({'soundcloud.clientId.v1': 'test-client-id'});
    final c = PlayerController();
    final apply = JustAudioMediaKit.onPlayerCreated!;
    JustAudioMediaKit.onPlayerCreated = (p) async {
      await (p.platform as NativePlayer).setProperty('ao', 'null');
      apply(p);
    };
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('SoundCloud playback test'))));
    await tester.runAsync(() async {
      final dir = Directory.systemTemp.createTempSync('riflay-soundcloud');
      final errors = <String>[];
      final sub = c.errors.listen(errors.add);
      HttpServer? server;
      try {
        await c.load();
        await c.setAutoplay(false);
        await c.audio.setCrossfade(false);
        // 40 seconds of AAC in fMP4 segments, as SoundCloud serves it.
        final made = await Process.run('ffmpeg', [
          '-loglevel', 'error', '-y', '-f', 'lavfi', '-i', 'sine=frequency=440:duration=40:sample_rate=44100', //
          '-c:a', 'aac', '-b:a', '160k', '-f', 'hls', '-hls_time', '10', '-hls_playlist_type', 'vod',
          '-hls_segment_type', 'fmp4', '-hls_segment_filename', '${dir.path}/data%03d.m4s', '${dir.path}/playlist.m3u8',
        ]);
        expect(made.exitCode, 0, reason: '${made.stderr}');
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        var segments = 0;
        server.listen((request) async {
          final file = File('${dir.path}${request.uri.path}');
          if (request.uri.path.endsWith('.m4s')) segments++;
          if (!file.existsSync()) {
            request.response.statusCode = HttpStatus.notFound;
          } else {
            request.response.add(await file.readAsBytes());
          }
          await request.response.close();
        });
        final base = 'http://127.0.0.1:${server.port}';
        final playlist = await File('${dir.path}/playlist.m3u8').readAsString();
        // The first playlist's signatures run out just past the refresh margin, so the player looks it up again.
        var lookups = 0;
        String signed(Duration life) {
          final at = DateTime.now().add(life).millisecondsSinceEpoch ~/ 1000;
          return playlist.replaceAllMapped(RegExp(r'^(.+\.m4s)$', multiLine: true), (m) => '${m[1]}?expires=$at');
        }

        c.soundcloud = SoundcloudClient(
          prefs: await SharedPreferences.getInstance(),
          client: MockClient((r) async {
            if (r.url.path == '/tracks/1') {
              return http.Response(
                jsonEncode({
                  'kind': 'track',
                  'id': 1,
                  'title': 'Sine',
                  'policy': 'ALLOW',
                  'media': {
                    'transcodings': [
                      {
                        'url': 'https://api-v2.soundcloud.com/media/1/aac_160k/stream/hls',
                        'preset': 'aac_160k',
                        'format': {'protocol': 'hls', 'mime_type': 'audio/mp4; codecs="mp4a.40.2"'},
                      },
                    ],
                  },
                }),
                200,
              );
            }
            if (r.url.path.endsWith('/stream/hls')) {
              return http.Response(jsonEncode({'url': '$base/playlist.m3u8'}), 200);
            }
            // The playlist itself: its relative segments become the local server's.
            if (r.url.path == '/playlist.m3u8') {
              lookups++;
              final life = lookups == 1 ? const Duration(minutes: 10, seconds: 20) : const Duration(hours: 3);
              return http.Response(signed(life), 200);
            }
            return http.Response('', 404);
          }),
        );
        final track = Track.soundcloud(trackId: '1', title: 'Sine', artist: 'Test');
        await c.playList([track], 0, from: 'SoundCloud integration test').timeout(const Duration(seconds: 30));
        await _until(() => c.position >= const Duration(seconds: 2), 'playing');
        expect(c.duration?.inSeconds, inInclusiveRange(39, 41), reason: 'HLS VOD reports its length');
        await c.seek(const Duration(seconds: 30));
        await _until(() => c.position >= const Duration(seconds: 31), 'seeked');
        expect(segments, greaterThan(1));
        expect(errors, isEmpty);
        debugPrint('SOUNDCLOUD local HLS: PASS, duration=${c.duration}, segments=$segments');

        // Signatures about to run out: the track is loaded again where it is, and keeps playing.
        await c.seek(const Duration(seconds: 2));
        final first = lookups;
        var before = Duration.zero;
        await _until(
          () {
            if (lookups == first) before = c.position;
            return lookups > first;
          },
          'a fresh playlist',
          seconds: 60,
        );
        await Future<void>.delayed(const Duration(seconds: 3));
        final at = c.position;
        expect(at, greaterThanOrEqualTo(before), reason: 'it goes on from where it was ($before), not from the top');
        expect(c.currentTrack?.id, track.id);
        expect(errors, isEmpty);
        debugPrint('SOUNDCLOUD refresh: PASS, $before before, $at three seconds after, lookups=$lookups');
        await c.pause();

        if (const bool.fromEnvironment('RIFLAY_LIVE_SOUNDCLOUD')) {
          c.soundcloud = SoundcloudClient(prefs: await SharedPreferences.getInstance());
          await (await SharedPreferences.getInstance()).remove('soundcloud.clientId.v1');
          final found = await c.searchSoundcloud('lofi hip hop').timeout(const Duration(seconds: 60));
          final song = found.firstWhere((t) => (t.duration ?? Duration.zero) > const Duration(minutes: 2));
          debugPrint('SOUNDCLOUD live: ${song.title} / ${song.id} / ${song.duration}');
          await c.playList([song], 0, from: 'SoundCloud integration test').timeout(const Duration(seconds: 60));
          await _until(() => c.position >= const Duration(seconds: 3), 'live playing', seconds: 60);
          await c.seek(const Duration(seconds: 90));
          await _until(() => c.position >= const Duration(seconds: 92), 'live seeked', seconds: 60);
          expect(errors, isEmpty);
          debugPrint('SOUNDCLOUD live: PASS, duration=${c.duration}');
          await c.pause();
        }
      } finally {
        await sub.cancel();
        await server?.close(force: true);
        dir.deleteSync(recursive: true);
      }
    });
  });
}

Future<void> _until(bool Function() done, String what, {int seconds = 30}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (!done()) {
    if (DateTime.now().isAfter(end)) fail('Timed out waiting until $what');
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

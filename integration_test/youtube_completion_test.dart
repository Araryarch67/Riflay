// Real Riflay playback through just_audio + libmpv, in a headless Weston.
// Tests short HTTP range responses, then (opt in) a complete live YouTube song.
// Uses a fresh XDG_DATA_HOME and ao=null; no account or speaker output is used.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:media_kit/media_kit.dart' show NativePlayer;
import 'package:riflay/models/track.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/services/youtube_audio_source.dart';
import 'package:riflay/services/ytdlp.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('complete songs reach their end before the queue advances', (tester) async {
    JustAudioMediaKit.ensureInitialized(linux: true, windows: true);
    SharedPreferences.setMockInitialValues({});
    final c = PlayerController();
    final apply = JustAudioMediaKit.onPlayerCreated!;
    JustAudioMediaKit.onPlayerCreated = (p) async {
      await (p.platform as NativePlayer).setProperty('ao', 'null');
      apply(p);
    };
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('Playback completion test'))));
    await tester.runAsync(() async {
      final dir = Directory.systemTemp.createTempSync('riflay-completion');
      final errors = <String>[];
      final sub = c.errors.listen(errors.add);
      HttpServer? server;
      try {
        await c.load();
        await c.setAutoplay(false);
        await c.audio.setCrossfade(false);
        final audio = File('${dir.path}/song.webm');
        final marker = File('${dir.path}/next.wav');
        for (final args in [
          [
            '-f',
            'lavfi',
            '-i',
            'sine=frequency=440:duration=20:sample_rate=48000',
            '-c:a',
            'libopus',
            '-b:a',
            '160k',
            audio.path,
          ],
          ['-f', 'lavfi', '-i', 'sine=frequency=880:duration=3:sample_rate=48000', marker.path],
        ]) {
          final result = await Process.run('ffmpeg', ['-loglevel', 'error', '-y', ...args]);
          expect(result.exitCode, 0, reason: '${result.stderr}');
        }
        final bytes = await audio.readAsBytes();
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        var requests = 0;
        server.listen((request) async {
          requests++;
          final range = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(request.headers.value('range') ?? '');
          final from = range == null ? 0 : int.parse(range[1]!);
          final requestedEnd = range == null ? bytes.length - 1 : int.parse(range[2]!);
          final end = (from + 32767).clamp(from, requestedEnd.clamp(from, bytes.length - 1));
          request.response.statusCode = HttpStatus.partialContent;
          request.response.headers.set('content-type', 'audio/webm');
          request.response.headers.set('content-range', 'bytes $from-$end/${bytes.length}');
          request.response.add(bytes.sublist(from, end + 1));
          await request.response.close();
        });
        final track = Track.youtube(
          videoId: 'completion-partial',
          title: '20-second stream',
          artist: 'Test',
          duration: const Duration(seconds: 20),
        );
        final next = Track.fromUri(marker.uri);
        final uri = Uri.parse('http://127.0.0.1:${server.port}/audio');
        final source = YoutubeAudioSource(
          track.videoId!,
          yt: c.youtube.client,
          tag: track,
          resolveAudio: () async => ResolvedAudio(
            url: uri,
            formatId: '251',
            ext: 'webm',
            codec: 'opus',
            kbps: 160,
            size: bytes.length,
            resolvedAt: DateTime.now(),
            via: 'local interrupted HTTP',
          ),
        );
        await c.player.setAudioSources([source, AudioSource.uri(marker.uri, tag: next)]);
        for (var i = 0; i < 200 && !YoutubeAudioSource.cacheCompleteFor(track.videoId!); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
        expect(YoutubeAudioSource.cacheCompleteFor(track.videoId!), isTrue);
        await server.close(force: true);
        server = null;
        debugPrint('REAL_PLAYBACK offline test: upstream server disconnected after background caching');
        await _finishFirst(
          c,
          expected: const Duration(seconds: 20),
          start: () async {
            unawaited(c.play());
          },
        );
        expect(requests, greaterThan(1), reason: 'the real source resumed multiple short HTTP responses');
        expect(errors, isEmpty);
        debugPrint('REAL_PLAYBACK short HTTP responses: PASS, $requests requests, full 20-second song');
        await c.pause();

        if (const bool.fromEnvironment('RIFLAY_LIVE_YOUTUBE')) {
          final found = await c.searchYoutube('D-low beatbox').timeout(const Duration(seconds: 60));
          final candidates = found
              .where(
                (song) =>
                    song.duration != null &&
                    song.duration! >= const Duration(seconds: 45) &&
                    song.duration! <= const Duration(minutes: 3),
              )
              .toList();
          expect(candidates, isNotEmpty, reason: 'the live search must provide a complete short song to test');
          final song = candidates.first;
          debugPrint('REAL_PLAYBACK live YouTube: ${song.title} / ${song.videoId} / ${song.duration}');
          // Load through Riflay's normal source selection, queue and controller.
          await c.playList([song, next], 0, from: 'Completion integration test').timeout(const Duration(seconds: 90));
          expect(c.currentTrack?.id, song.id, reason: 'the actual YouTube song must load');
          final actual = c.duration ?? song.duration!;
          await _finishFirst(c, expected: actual);
          expect(errors, isEmpty, reason: 'no decoder/network error may silently skip the live song');
          final stats = YoutubeAudioSource.statsOf(song.videoId!);
          debugPrint(
            'REAL_PLAYBACK live YouTube: PASS, duration=$actual, received=${stats?.received}, '
            'format=${stats?.stream?.formatId}, source=${stats?.stream?.via}',
          );
        }
      } finally {
        await c.pause();
        await sub.cancel();
        await server?.close(force: true);
        c.dispose();
        dir.deleteSync(recursive: true);
      }
    });
  }, timeout: const Timeout(Duration(minutes: 12)));
}

Future<void> _finishFirst(PlayerController c, {required Duration expected, Future<void> Function()? start}) async {
  var furthest = Duration.zero;
  final sub = c.player.positionStream.listen((position) {
    if (c.player.currentIndex == 0 && position > furthest) furthest = position;
  });
  final clock = Stopwatch()..start();
  try {
    await start?.call();
    while (c.player.currentIndex == 0 && clock.elapsed < expected + const Duration(seconds: 60)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(c.player.currentIndex, 1, reason: 'the player must naturally advance to the next song');
    expect(
      furthest.inMilliseconds,
      greaterThanOrEqualTo(expected.inMilliseconds - 1000),
      reason: 'must reach the last second, rather than treat a short network response as EOF',
    );
    expect(
      clock.elapsed.inMilliseconds,
      greaterThanOrEqualTo(expected.inMilliseconds - 1500),
      reason: 'normal-speed playback must last the whole song',
    );
    debugPrint('REAL_PLAYBACK completed: expected=$expected, lastPosition=$furthest, elapsed=${clock.elapsed}');
  } finally {
    await sub.cancel();
  }
}

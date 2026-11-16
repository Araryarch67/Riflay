// Opt-in real libmpv playback, using a local HTTP fixture and isolated storage.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:riflay/models/track.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const enabled = bool.fromEnvironment('RIFLAY_TEST_WINDOWS_MPV');
  testWidgets(
    'real player retries an unavailable stream, keeps the queue and honours pause during backoff',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.runAsync(() async {
        MediaKit.ensureInitialized(
          libmpv: File(
            const String.fromEnvironment('RIFLAY_TEST_MPV_DLL', defaultValue: 'build/windows/x64/libmpv/libmpv-2.dll'),
          ).absolute.path,
        );
        JustAudioMediaKit.ensureInitialized(windows: true);
        SharedPreferences.setMockInitialValues({'discord.enabled': false});
        final directory = await Directory.systemTemp.createTemp('riflay-playback-retry-');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
        final oldDelays = PlayerController.playbackRetryDelays;
        PlayerController.playbackRetryDelays = List.filled(8, const Duration(milliseconds: 100));
        final controller = PlayerController();
        controller.discord.enabled = false;
        final apply = JustAudioMediaKit.onPlayerCreated;
        JustAudioMediaKit.onPlayerCreated = (player) {
          unawaited((player.platform as NativePlayer).setProperty('ao', 'null').then((_) => apply?.call(player)));
        };
        final errors = <String>[];
        final friendly = controller.errors.listen(errors.add);
        final audio = await File('test/fixtures/sine.flac').readAsBytes();
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        var available = false;
        var requests = 0;
        var failures = 0;
        final rawErrors = controller.player.errorStream.listen((error) {
          if (error.index == 0) {
            failures++;
            available = failures >= 5;
          }
        });
        server.listen((request) async {
          requests++;
          if (!available) {
            request.response.statusCode = HttpStatus.serviceUnavailable;
          } else {
            request.response.headers.contentType = ContentType('audio', 'flac');
            request.response.contentLength = audio.length;
            if (request.method != 'HEAD') request.response.add(audio);
          }
          await request.response.close();
        });
        final tracks = [
          for (final id in ['first', 'next'])
            Track(id: id, uri: Uri.parse('http://127.0.0.1:${server.port}/$id.flac'), title: id, artist: 'Test'),
        ];
        Future<void> until(bool Function() ready) async {
          final watch = Stopwatch()..start();
          while (!ready() && watch.elapsed < const Duration(seconds: 20)) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
          expect(ready(), isTrue);
        }

        try {
          await controller.setAutoplay(false);
          await controller.playList(tracks, 0);
          await until(() => controller.player.position > Duration.zero && controller.player.playing);
          expect(failures, greaterThanOrEqualTo(5));
          expect(requests, greaterThan(1));
          expect(controller.currentTrack?.id, 'first');
          expect(controller.queue.map((track) => track.id), ['first', 'next']);
          expect(errors, isEmpty);

          PlayerController.playbackRetryDelays = [const Duration(milliseconds: 100)];
          available = false;
          final before = failures;
          await controller.playList(tracks, 0);
          await until(() => failures > before);
          await controller.pause();
          final pausedSources = controller.player.sequenceState.sequence.toList();
          await Future<void>.delayed(const Duration(milliseconds: 250));
          expect(controller.player.playing, isFalse);
          final afterPause = controller.player.sequenceState.sequence;
          expect(afterPause.length, pausedSources.length);
          for (var i = 0; i < afterPause.length; i++) {
            expect(identical(afterPause[i], pausedSources[i]), isTrue, reason: 'Pause must prevent a source reload');
          }
          expect(errors, isEmpty);
        } finally {
          await rawErrors.cancel();
          await friendly.cancel();
          await controller.player.dispose();
          controller.dispose();
          JustAudioMediaKit.onPlayerCreated = apply;
          PlayerController.playbackRetryDelays = oldDelays;
          await server.close(force: true);
          await directory.delete(recursive: true);
        }
      });
    },
    skip: !Platform.isWindows || !enabled,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

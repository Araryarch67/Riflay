// Opt-in: the media session driving the real libmpv player (flutter test --dart-define=RIFLAY_TEST_WINDOWS_MPV=true).
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:riflay/models/track.dart';
import 'package:riflay/services/media_session/media_session_service.dart';
import 'package:riflay/services/media_session/player_binding.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Recorder implements MediaSessionAdapter {
  final updates = <MediaSessionState>[];
  late void Function(MediaCommand) press;

  @override
  String get name => 'recorder';

  @override
  Future<bool> attach(void Function(MediaCommand) onCommand) async {
    press = onCommand;
    return true;
  }

  @override
  Future<void> update(MediaSessionState state) async => updates.add(state);

  @override
  Future<void> detach() async {}
}

void main() {
  const enabled = bool.fromEnvironment('RIFLAY_TEST_WINDOWS_MPV');
  testWidgets(
    'system commands drive the real libmpv player and its state comes back',
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
        final directory = await Directory.systemTemp.createTemp('riflay-media-session-');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
        final controller = PlayerController();
        controller.discord.enabled = false;
        final apply = JustAudioMediaKit.onPlayerCreated;
        JustAudioMediaKit.onPlayerCreated = (player) {
          final backend = player.platform as NativePlayer;
          unawaited(backend.setProperty('ao', 'null').then((_) => apply?.call(player)));
        };
        MediaSessionService.resetForTest();
        final recorder = _Recorder();
        final session = await MediaSessionService.start(PlayerControllerBinding(controller), [recorder]);
        final sine = File('test/fixtures/sine.flac').absolute;
        final tracks = [
          for (final id in ['first', 'second']) Track(id: id, uri: Uri.file(sine.path), title: id, artist: 'Test'),
        ];
        Future<void> until(bool Function() ready) async {
          final watch = Stopwatch()..start();
          while (!ready() && watch.elapsed < const Duration(seconds: 20)) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
          expect(ready(), isTrue);
        }

        Future<void> press(MediaCommand c) async {
          // Past the bounce window: each is a separate press.
          await Future<void>.delayed(const Duration(milliseconds: 400));
          expect(session.dispatch(c), isTrue);
          await session.settled;
        }

        try {
          await controller.setAutoplay(false);
          await controller.playList(tracks, 0);
          await until(() => controller.player.playing && controller.player.position > Duration.zero);
          await until(() => recorder.updates.isNotEmpty && recorder.updates.last.playing);
          expect(recorder.updates.last.track?.id, 'first');

          await press(const MediaCommand.pause());
          await until(() => !controller.player.playing);
          await until(() => !recorder.updates.last.playing);

          await press(const MediaCommand.play());
          await until(() => controller.player.playing);
          await until(() => recorder.updates.last.playing);

          await press(const MediaCommand.next());
          await until(() => controller.currentTrack?.id == 'second');
          await until(() => recorder.updates.last.track?.id == 'second');

          await press(const MediaCommand.seek(Duration(milliseconds: 500)));
          await until(() => recorder.updates.last.position >= const Duration(milliseconds: 500));

          await press(const MediaCommand.previous());
          await until(() => controller.currentTrack?.id == 'first' || controller.position < const Duration(seconds: 1));

          await press(const MediaCommand.toggle(source: MediaCommandSource.keyboard));
          await until(() => !controller.player.playing);
          // The same key as the system saw it: dropped, the player stays paused.
          expect(session.dispatch(const MediaCommand.play()), isFalse);
          await session.settled;
          expect(controller.player.playing, isFalse);
        } finally {
          await session.dispose();
          MediaSessionService.resetForTest();
          JustAudioMediaKit.onPlayerCreated = apply;
          controller.dispose();
          await directory.delete(recursive: true).catchError((Object _) => directory);
        }
      });
    },
    skip: !enabled || !Platform.isWindows,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

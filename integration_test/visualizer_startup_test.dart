import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:media_kit/media_kit.dart' show NativePlayer;
import 'package:riflay/models/track.dart';
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/ui/widgets/audio_visualizer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'wav_util.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  JustAudioMediaKit.ensureInitialized(linux: true);

  testWidgets('visualizer starts measuring on first playback without reopening its view', (tester) async {
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({'discord.enabled': false});
      await LayoutPrefs.instance.reset();
      await LayoutPrefs.instance.setVisualizer(true);
      final folder = Directory.systemTemp.createTempSync('riflay-visualizer-startup-');
      final source = writeWav('${folder.path}/tone.wav', 48000 * 10, (i) {
        final s = 0.4 * math.sin(2 * math.pi * 440 * i / 48000);
        return (s, s);
      });
      final c = PlayerController();
      final original = JustAudioMediaKit.onPlayerCreated!;
      JustAudioMediaKit.onPlayerCreated = (player) {
        original(player);
        final native = player.platform as NativePlayer;
        final ready = native.setProperty('ao', 'null');
        native.onLoadHooks.add(() => ready);
      };
      try {
        final track = Track.fromUri(source.uri);
        await c.player.setAudioSources([AudioSource.uri(source.uri, tag: track)]);
        await tester.pumpWidget(
          PlayerScope(
            controller: c,
            child: const MaterialApp(
              home: Scaffold(
                body: Center(child: AudioVisualizer(child: SizedBox.square(dimension: 240))),
              ),
            ),
          ),
        );
        unawaited(c.player.play());
        var peak = 0.0;
        for (var i = 0; i < 30 && peak <= 0.05; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
          peak = c.audio.visualizerLevels.value.reduce(math.max);
        }
        expect(c.audio.visualizerActive, isTrue);
        expect(peak, greaterThan(0.05), reason: 'polling must let the initial meter setup finish');
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await c.player.stop();
        JustAudioMediaKit.onPlayerCreated = original;
        c.dispose();
        folder.deleteSync(recursive: true);
      }
    });
  });
}

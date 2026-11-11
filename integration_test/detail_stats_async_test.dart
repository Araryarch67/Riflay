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
import 'package:riflay/platform/mpv_snapshot.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/ui/widgets/stats_for_nerds.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'wav_util.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  JustAudioMediaKit.ensureInitialized(linux: true);

  testWidgets('native diagnostics leave the UI free and populate the stats popup', (tester) async {
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({'discord.enabled': false});
      final folder = Directory.systemTemp.createTempSync('riflay-stats-async-');
      final source = writeWav('${folder.path}/tone.wav', 48000 * 8, (i) {
        final s = 0.3 * math.sin(2 * math.pi * 440 * i / 48000);
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
        unawaited(c.player.play());
        final native = JustAudioMediaKit.activePlayer!.platform as NativePlayer;
        var uiRan = false;
        Timer.run(() => uiRan = true);
        final values = await readMpvSnapshot(native, [
          for (var i = 0; i < 64; i++) 'audio-params/samplerate',
          'audio-codec',
          'riflay-property-that-does-not-exist',
        ]);
        expect(uiRan, isTrue, reason: 'native reads must yield to the UI event loop');
        expect(values['audio-params/samplerate'], '48000');
        expect(values['audio-codec'], isNotEmpty);
        expect(values['riflay-property-that-does-not-exist'], '');
        final path = await c.audio.signalPath();
        expect(path?.inRate, 48000);
        expect((await c.audio.nerdStats()).codecName, isNotEmpty);

        await tester.pumpWidget(
          PlayerScope(
            controller: c,
            child: MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: TextButton(onPressed: () => showDetailStats(context), child: const Text('Open')),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pump();
        expect(find.text('Detail stats'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 400));
        for (var i = 0; i < 30 && find.text('Source').evaluate().isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
        }
        expect(find.text('Source'), findsOneWidget);
        expect(tester.takeException(), isNull);
        Navigator.of(tester.element(find.text('Detail stats'))).pop();
        await tester.pump(const Duration(milliseconds: 400));
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

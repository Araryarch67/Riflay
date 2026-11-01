// Run in headless Weston, isolated XDG_DATA_HOME, per AGENT.md. Null audio only.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:media_kit/media_kit.dart' show NativePlayer;
import 'package:riflay/models/track.dart';
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/services/appearance.dart';
import 'package:riflay/ui/widgets/player_backdrop.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/ui/widgets/audio_visualizer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'wav_util.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  JustAudioMediaKit.ensureInitialized(linux: true, windows: true, android: true, macOS: true, iOS: true);

  testWidgets('real decoded audio drives all styles; silence, pause, hidden and off stop metering', (tester) async {
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({'discord.enabled': false});
      final folder = Directory.systemTemp.createTempSync('riflay-visualizer-test-');
      final source = writeWav('${folder.path}/levels.wav', 48000 * 12, (i) {
        final t = i / 48000;
        final a = t < 2 || t >= 10 ? 0.0 : (0.1 + 0.35 * (1 + math.sin(t * 8)) / 2);
        final sample = a * math.sin(2 * math.pi * 440 * t);
        return (sample, sample);
      });
      final c = PlayerController();
      await c.load();
      await c.setAutoplay(false);
      final original = JustAudioMediaKit.onPlayerCreated!;
      JustAudioMediaKit.onPlayerCreated = (p) {
        original(p);
        final native = p.platform as NativePlayer;
        final ready = native.setProperty('ao', 'null');
        native.onLoadHooks.add(() => ready);
      };
      final prefs = LayoutPrefs.instance;
      await prefs.setVisualizer(true);
      final look = Appearance.instance;
      await look.setNowPlaying(NowPlayingBackground.aurora);
      await look.setReactiveBackground(true);
      final capture = GlobalKey();
      Widget view({bool visible = true}) => PlayerScope(
        controller: c,
        child: MaterialApp(
          home: Scaffold(
            backgroundColor: const Color(0xFF11171C),
            body: TickerMode(
              enabled: visible,
              child: Center(
                child: RepaintBoundary(
                  key: capture,
                  child: const SizedBox(
                    width: 700,
                    height: 400,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        PlayerBackdrop(coverColor: Color(0xffb64d7b)),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AudioVisualizer(
                              child: SizedBox.square(dimension: 240, child: ColoredBox(color: Color(0xFF284E53))),
                            ),
                            SizedBox(height: 24),
                            AudioVisualizer(),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      try {
        final track = Track.fromUri(source.uri);
        await c.player.setAudioSources([AudioSource.uri(source.uri, tag: track)]);
        await tester.pumpWidget(view());
        unawaited(c.player.play());
        await Future<void>.delayed(const Duration(milliseconds: 750));
        expect(c.audio.visualizerLevels.value, everyElement(lessThan(0.001)));
        await Future<void>.delayed(const Duration(seconds: 2));
        expect(
          c.audio.visualizerLevels.value.where((v) => v > 0.3).length,
          greaterThan(8),
          reason: 'measured from decoded 440 Hz audio',
        );
        final native = JustAudioMediaKit.activePlayer!.platform as NativePlayer;
        final chain = await native.getProperty('af');
        expect('visualizer'.allMatches(chain).length, 1, reason: 'visualizers and reactive background share one meter');
        const shots = String.fromEnvironment('SHOTS');
        for (final style in VisualizerStyle.values) {
          await prefs.setVisualizerStyle(style);
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 120));
          await tester.pump();
          if (shots.isNotEmpty) {
            Directory(shots).createSync(recursive: true);
            final boundary = capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
            final image = await boundary.toImage();
            final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
            await File('$shots/visualizer-${style.name}.png').writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          }
          expect(tester.takeException(), isNull);
        }
        await c.player.pause();
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(c.audio.visualizerLevels.value, everyElement(0));
        expect(await native.getProperty('af'), isNot(contains('visualizer')));
        unawaited(c.player.play());
        await tester.pumpWidget(view(visible: false));
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(await native.getProperty('af'), isNot(contains('visualizer')));
        await tester.pumpWidget(view());
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(await native.getProperty('af'), contains('visualizer'));
        await prefs.setVisualizer(false);
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(await native.getProperty('af'), contains('visualizer'), reason: 'background works independently');
        final frame = c.audio.visualizerLevels.frame;
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(c.audio.visualizerLevels.frame, greaterThan(frame));
        await look.setReactiveBackground(false);
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(await native.getProperty('af'), isNot(contains('visualizer')));
        await look.setReactiveBackground(true);
        await tester.pump();
        await c.player.seek(const Duration(milliseconds: 11500));
        for (var i = 0; i < 80 && c.player.processingState != ProcessingState.completed; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        expect(c.player.processingState, ProcessingState.completed);
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(
          await native.getProperty('af'),
          isNot(contains('visualizer')),
          reason: 'completed songs release analysis too',
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await c.player.stop();
        c.dispose();
        JustAudioMediaKit.onPlayerCreated = original;
        await prefs.reset();
        await look.reset();
        folder.deleteSync(recursive: true);
      }
    });
  });
}

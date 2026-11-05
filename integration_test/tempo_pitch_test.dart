// Tempo & pitch reach mpv as speed, pitch correction and the @pitch filter (real engine, silent output).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:media_kit/media_kit.dart' show NativePlayer;
import 'package:riflay/models/track.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'wav_util.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  JustAudioMediaKit.ensureInitialized(linux: true, windows: true);

  testWidgets('tempo plays faster in time, pitch shifts without changing it', (tester) async {
    final dir = Directory.systemTemp.createTempSync('om-tempo');
    addTearDown(() => dir.deleteSync(recursive: true));
    final song = Track(
      id: 'file://${dir.path}/a.wav',
      uri: Uri.file(writeWav('${dir.path}/a.wav', 48000 * 60, (_) => (0.0, 0.0)).path),
      title: 'A',
      artist: 'Test',
    );
    SharedPreferences.setMockInitialValues({'library.v1': jsonEncode([song.toJson()])});
    final c = PlayerController();
    NativePlayer? mpv;
    final apply = JustAudioMediaKit.onPlayerCreated!;
    JustAudioMediaKit.onPlayerCreated = (p) async {
      mpv = p.platform as NativePlayer;
      await mpv!.setProperty('ao', 'null');
      apply(p);
    };
    addTearDown(() => JustAudioMediaKit.onPlayerCreated = apply);
    await tester.runAsync(() async {
      await c.load();
      await c.setAutoplay(false);
      await c.playList([song], 0);
      await Future<void>.delayed(const Duration(milliseconds: 800));
      await c.audio.setTempo(1.25);
      await c.audio.setPitch(2);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      final speed = double.parse(await mpv!.getProperty('speed'));
      final af = await mpv!.getProperty('af');
      final correction = await mpv!.getProperty('audio-pitch-correction');
      // ignore: avoid_print
      print('TEMPO: speed=$speed correction=$correction af=$af');
      expect(speed, closeTo(1.25 * 1.122462, 0.001));
      expect(af, contains('scaletempo'));
      expect(correction, 'no');
      // The song moves on at the tempo: 1.25 s of song per real second.
      final before = c.player.position;
      final clock = Stopwatch()..start();
      await Future<void>.delayed(const Duration(seconds: 4));
      final rate = (c.player.position - before).inMilliseconds / clock.elapsedMilliseconds;
      // ignore: avoid_print
      print('TEMPO: rate=$rate');
      expect(rate, closeTo(1.25, 0.08));
      await c.audio.resetTempoPitch();
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(double.parse(await mpv!.getProperty('speed')), closeTo(1, 0.001));
      expect(await mpv!.getProperty('af'), isNot(contains('scaletempo')));
      await c.pause();
      c.dispose();
    });
  }, timeout: const Timeout(Duration(minutes: 3)));
}

// Moving and removing songs in the queue (real just_audio + libmpv, silent output).
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

  testWidgets('queue songs move and come out, the playing one untouched', (tester) async {
    final dir = Directory.systemTemp.createTempSync('om-queue');
    addTearDown(() => dir.deleteSync(recursive: true));
    final songs = [
      for (final n in ['A', 'B', 'C', 'D', 'E'])
        Track(
          id: 'file://${dir.path}/$n.wav',
          uri: Uri.file(writeWav('${dir.path}/$n.wav', 48000 * 20, (_) => (0.0, 0.0)).path),
          title: n,
          artist: 'Test',
        ),
    ];
    SharedPreferences.setMockInitialValues({'library.v1': jsonEncode([for (final t in songs) t.toJson()])});
    final c = PlayerController();
    final apply = JustAudioMediaKit.onPlayerCreated!;
    JustAudioMediaKit.onPlayerCreated = (p) async {
      await (p.platform as NativePlayer).setProperty('ao', 'null');
      apply(p);
    };
    addTearDown(() => JustAudioMediaKit.onPlayerCreated = apply);
    await tester.runAsync(() async {
      await c.load();
      await c.setAutoplay(false);
      await c.playList(songs, 0);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      List<String> next() => [for (final t in c.upNext) t.title];
      expect(c.currentTrack?.title, 'A');
      expect(next(), ['B', 'C', 'D', 'E']);
      await c.moveInQueue(0, 2); // B after D
      expect(next(), ['C', 'D', 'B', 'E']);
      await c.moveInQueue(3, 0); // E first
      expect(next(), ['E', 'C', 'D', 'B']);
      await c.removeFromQueue(1); // C out
      expect(next(), ['E', 'D', 'B']);
      expect(c.currentTrack?.title, 'A', reason: 'the song playing is never moved');
      await c.player.seekToNext();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(c.currentTrack?.title, 'E', reason: 'the new order is what plays');
      await c.pause();
      c.dispose();
    });
  }, timeout: const Timeout(Duration(minutes: 3)));
}

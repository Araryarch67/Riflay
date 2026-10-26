// Changing a Playback or Hi-Fi audio setting must not change the song: the same song goes on from
// the same place, and a paused one stays paused. A short dropout while the output reopens is fine.
//
// Real engine, silent output (mpv's `null` ao, which still runs in real time). Run it in headless
// Weston with a throwaway XDG_DATA_HOME:
//   flutter test integration_test/settings_keep_playing_test.dart -d linux
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:media_kit/media_kit.dart' show NativePlayer;
import 'package:riflay/models/track.dart';
import 'package:riflay/services/audio_engine.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'wav_util.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  JustAudioMediaKit.ensureInitialized(linux: true, windows: true);

  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('om-keep');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  // `failing`: the output can't open (mpv's alsa on a card that isn't there), as a real one does
  // when a device is busy or can't take a format. mpv then plays on without sound, and its
  // "could not open the audio device" error must not be taken for a broken song.
  for (final (playing, failing) in [(true, false), (false, false), (true, true), (false, true)]) {
    final name = '${playing ? 'playing' : 'paused'}${failing ? ', output failing' : ''}';
    testWidgets('settings keep the song and its place ($name)', (tester) async {
      final songs = [
        for (var i = 0; i < 3; i++)
          Track.fromUri(
            Uri.file(
              writeWav('${dir.path}/song$i.wav', 48000 * 30, (n) {
                final s = 0.2 * (n % 48 < 24 ? 1.0 : -1.0);
                return (s, s);
              }).path,
            ),
          ),
      ];
      SharedPreferences.setMockInitialValues({
        'discord.enabled': false,
        'source.v1': 'local',
        'library.v1': jsonEncode([for (final t in songs) t.toJson()]),
        // Bit-perfect must not take the real sound card.
        'audio.v1': jsonEncode({'device': 'alsa/no-such-card'}),
      });
      final c = PlayerController();
      final apply = JustAudioMediaKit.onPlayerCreated!;
      NativePlayer? mpv;
      JustAudioMediaKit.onPlayerCreated = (p) async {
        mpv = p.platform as NativePlayer;
        await mpv?.setProperty('ao', 'null');
        apply(p);
      };
      addTearDown(() => JustAudioMediaKit.onPlayerCreated = apply);
      await tester.runAsync(c.load);
      await tester.runAsync(() => c.setAutoplay(false));

      Future<void> wait(int ms) => tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));

      Future<void> start() async {
        await tester.runAsync(() async {
          await mpv?.setProperty('ao', 'null');
          await c.playList(c.library.where((t) => songs.any((s) => s.id == t.id)).toList(), 1);
        });
        for (var i = 0; i < 100 && c.player.position < const Duration(milliseconds: 300); i++) {
          await wait(100);
        }
        await tester.runAsync(() => c.player.seek(const Duration(seconds: 10)));
        await wait(500);
        if (!playing) await tester.runAsync(() => c.player.pause());
        await wait(500);
        expect(c.player.playing, playing);
      }

      final changes = <String, Future<void> Function()>{
        'gapless off': () => c.audio.setGapless(false),
        'gapless on': () => c.audio.setGapless(true),
        'leveling track': () => c.audio.setLeveling(VolumeLeveling.track),
        'leveling off': () => c.audio.setLeveling(VolumeLeveling.off),
        'crossfeed': () => c.audio.setCrossfeed(0.5),
        'mono': () => c.audio.setMono(MonoAudio.values.last),
        'virtual speakers': () => c.audio.setVirtualSpeakers(true),
        'eq on': () => c.audio.setEqEnabled(true),
        'buffer': () => c.audio.setBuffer(BufferSize.values.last),
        'exclusive': () => c.audio.setExclusive(true),
        'output rate': () => c.audio.setOutputRate(96000),
        'output rate auto': () => c.audio.setOutputRate(null),
        'hq resampler': () => c.audio.setHqResampler(true),
        'bit-perfect': () => c.audio.setBitPerfect(true),
        'native DSD': () => c.audio.setNativeDsd(true),
        'plugins': () => c.audio.setPlugins(true),
        // Not with a failing output: 'auto' would let alsa open the real sound card.
        if (!failing) 'device': () => c.audio.setDevice('auto'),
      };

      final failures = <String>[];
      for (final e in changes.entries) {
        await start();
        // From now on reopening the output fails.
        if (failing) await tester.runAsync(() => mpv!.setProperty('ao', 'alsa'));
        final index = c.player.currentIndex;
        final before = c.player.position;
        final clock = Stopwatch()..start();
        await tester.runAsync(() => e.value().timeout(const Duration(seconds: 20)));
        await wait(3000);
        final expected = before + (playing ? clock.elapsed : Duration.zero);
        final drift = (c.player.position - expected).inMilliseconds.abs();
        final problem = [
          if (c.player.currentIndex != index) 'song ${c.player.currentIndex} instead of $index',
          if (drift > 2500) 'position ${c.player.position} instead of about $expected',
          if (c.player.playing != playing) 'playing is ${c.player.playing}',
        ];
        if (problem.isNotEmpty) {
          failures.add('${e.key}: ${problem.join(', ')}');
          if (failing) break; // a wedged output makes every next step hang
        }
      }
      await tester.runAsync(() => c.player.stop().timeout(const Duration(seconds: 10), onTimeout: () {}));
      expect(failures, isEmpty);
    }, timeout: const Timeout(Duration(minutes: 8)));
  }
}

// Audio plugins through this platform's own libmpv, the app's bridge and Carla:
// the project half_gain_internal.carxp (Carla's own gain at 0.5) must lower a
// tone by 6 dB, and without a project the tone must come out as it went in.
// mpv renders into a WAV file (ao=pcm), nothing is heard.
//
//   flutter test integration_test/plugins_test.dart -d <linux|macos>
//
// Needs Carla installed (the test says so and passes without it, since that
// is the user's machine, not a fault). It sets the app's plugins project aside
// while it runs and puts it back after; run it with a throwaway app-data
// directory and in a headless session (see AGENT.md).
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:media_kit/media_kit.dart' show NativePlayer;
import 'package:path_provider/path_provider.dart';
import 'package:riflay/services/audio_engine.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'wav_util.dart';

/// test/fixtures/half_gain_internal.carxp (the app has no test folder next to it on a desktop).
const _halfGain = """<?xml version='1.0' encoding='UTF-8'?>
<!DOCTYPE CARLA-PROJECT>
<CARLA-PROJECT VERSION='2.5'>
 <Plugin>
  <Info><Type>Internal</Type><Name>Audio Gain (Stereo)</Name><Label>audiogain_s</Label></Info>
  <Data><Active>Yes</Active><Parameter><Index>0</Index><Name>Gain</Name><Value>0.5</Value></Parameter></Data>
 </Plugin>
</CARLA-PROJECT>
""";

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  JustAudioMediaKit.ensureInitialized(linux: true, windows: true, android: true, macOS: true, iOS: true);

  testWidgets('a Carla project in the filter chain changes what mpv renders', (tester) async {
    expect(AudioEngine.pluginBridge, isNotNull, reason: 'the bridge is in the app');
    if (!AudioEngine.carlaInstalled) {
      // CI installs it first: not finding it there is a fault.
      if (Platform.environment['CI'] == 'true') fail('Carla should be installed');
      // ignore: avoid_print
      print('PLUGINS skipped: Carla is not installed');
      return;
    }
    SharedPreferences.setMockInitialValues({'discord.enabled': false});
    final dir = ((await getTemporaryDirectory())..createSync(recursive: true)).createTempSync('om-plugins');
    final project = File(AudioEngine.pluginsProject);
    final aside = File('${dir.path}/previous.carxp');
    if (project.existsSync()) project.copySync(aside.path);
    addTearDown(() {
      if (aside.existsSync()) {
        aside.copySync(project.path);
      } else if (project.existsSync()) {
        project.deleteSync();
      }
      dir.deleteSync(recursive: true);
    });
    final song = writeWav('${dir.path}/tone.wav', 48000 * 3, (i) {
      final v = 0.5 * math.sin(2 * math.pi * 440 * i / 48000);
      return (v, v);
    });

    final c = PlayerController();
    await c.load();
    await c.setAutoplay(false);
    var out = '';
    final apply = JustAudioMediaKit.onPlayerCreated!;
    JustAudioMediaKit.onPlayerCreated = (p) {
      apply(p);
      final mpv = p.platform as NativePlayer;
      final file = out;
      final silent = () async {
        await mpv.setProperty('ao', 'pcm');
        await mpv.setProperty('ao-pcm-file', file);
        await mpv.setProperty('ao-pcm-waveheader', 'yes');
      }();
      mpv.onLoadHooks.add(() => silent);
    };
    addTearDown(() => JustAudioMediaKit.onPlayerCreated = apply);

    var n = 0;
    Future<List<double>> render(String name, Future<void> Function() change) async {
      out = '${dir.path}/out${n++}.wav';
      Future<T?> step<T>(Future<T> Function() f) => tester.runAsync(() => f().timeout(const Duration(seconds: 30)));
      await step(c.player.stop);
      await step(change);
      await step(() => c.player.setAudioSource(AudioSource.file(song.path)));
      await tester.pump(const Duration(milliseconds: 300));
      unawaited(c.player.play());
      final sw = Stopwatch()..start();
      while (c.player.processingState != ProcessingState.completed) {
        if (sw.elapsed > const Duration(seconds: 60)) fail('$name never finished');
        await tester.pump(const Duration(milliseconds: 20));
      }
      final filters = (await step(c.audio.signalPath))?.filters;
      await step(c.player.stop);
      await tester.pump(const Duration(milliseconds: 300));
      final m = measureWav(File(out));
      // ignore: avoid_print
      print('PLUGINS $name: ${m.db.map((d) => d.toStringAsFixed(2)).join(' / ')} dB, $filters');
      return m.db;
    }

    if (project.existsSync()) project.deleteSync();
    final dry = await render('no project', () => c.audio.setPlugins(true));
    expect(dry[0], closeTo(-9.03, 0.3));

    project.parent.createSync(recursive: true);
    project.writeAsStringSync(_halfGain);
    final halved = await render('gain 0.5', () => c.audio.setPlugins(true));
    expect(halved[0], closeTo(dry[0] - 6.02, 0.3), reason: 'the project halves the level');
    expect(halved[1], closeTo(halved[0], 0.05));

    final off = await render('plugins off', () => c.audio.setPlugins(false));
    expect(off[0], closeTo(dry[0], 0.05), reason: 'switched off, the sound is as it was');
    c.dispose();
  });
}

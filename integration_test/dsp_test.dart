// The sound-changing settings through this platform's own libmpv, measured:
// Mono audio, Virtual speakers, crossfeed and room correction. mpv renders
// into WAV files (ao=pcm), nothing is heard and nothing runs on a host, so the
// same test proves each platform's build (Linux, Windows, Android, macOS, iOS).
//
//   flutter test integration_test/dsp_test.dart -d <linux|windows|macos|emulator-5554|iPhone…>
//
// On a desktop, run it with a throwaway app-data directory and in a headless
// session (see AGENT.md).
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:media_kit/media_kit.dart' show NativePlayer;
import 'package:riflay/services/audio_engine.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'wav_util.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  JustAudioMediaKit.ensureInitialized(linux: true, windows: true, android: true, macOS: true, iOS: true);

  testWidgets('mono, virtual speakers, crossfeed and room correction change what mpv renders', (tester) async {
    // Discord off: the real one, if running, would show the test song on the user's profile.
    SharedPreferences.setMockInitialValues({'discord.enabled': false});
    // macOS outside the App Store sandbox: the caches folder isn't there until something makes it.
    final dir = ((await getTemporaryDirectory())..createSync(recursive: true)).createTempSync('om-dsp');
    addTearDown(() => dir.deleteSync(recursive: true));
    // 440 Hz on the left only, at −6 dBFS (−9 dBFS RMS).
    final song = writeWav('${dir.path}/left.wav', 48000 * 4, (i) => (0.5 * math.sin(2 * math.pi * 440 * i / 48000), 0));
    // A unit impulse, in a folder whose name FFmpeg's graph syntax would take apart unescaped.
    final odd = Directory("${dir.path}/O'Brien [IR], a;b")..createSync();
    final dirac = writeWav('${odd.path}/dirac.wav', 480, (i) => i == 0 ? (1, 1) : (0, 0));

    final c = PlayerController();
    await c.load();
    await c.setAutoplay(false);
    var out = '';
    final apply = JustAudioMediaKit.onPlayerCreated!;
    JustAudioMediaKit.onPlayerCreated = (p) {
      apply(p);
      // Into the file, never the device: the song waits for this before it opens the output.
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
    final stages = <String, List<String>>{};

    /// Plays [input] (the test song) through mpv with [change] made first; what came out.
    Future<({int rate, List<double> db, double peak})> render(
      String name,
      Future<void> Function() change, {
      File? input,
    }) async {
      out = '${dir.path}/out${n++}.wav';
      // Each step in real time: in the test's fake time, a player call that waits on a
      // timer inside just_audio or media_kit never returns (it hung about one run in seven).
      Future<T?> step<T>(String what, Future<T> Function() f) => tester.runAsync(
        () => f().timeout(const Duration(seconds: 30), onTimeout: () => throw StateError('$name: $what hung')),
      );
      await step('stop', c.player.stop); // a new mpv player, writing to [out]
      await step('the settings', change);
      await step('loading', () => c.player.setAudioSource(AudioSource.file((input ?? song).path)));
      await tester.pump(const Duration(milliseconds: 300));
      // Not awaited: just_audio's play() returns only when playback stops, and a stall must fail here.
      unawaited(c.player.play());
      final sw = Stopwatch()..start();
      while (c.player.processingState != ProcessingState.completed) {
        if (sw.elapsed > const Duration(seconds: 60)) {
          final mpv = JustAudioMediaKit.activePlayer!.platform as NativePlayer;
          final state = await tester.runAsync(() async {
            final values = <String>[];
            for (final k in ['current-ao', 'ao', 'pause', 'core-idle', 'eof-reached', 'time-pos', 'af']) {
              values.add('$k=${await mpv.getProperty(k)}');
            }
            return values.join(' ');
          });
          fail('$name never finished (${c.player.processingState} at ${c.player.position}; mpv: $state)');
        }
        if (!stages.containsKey(name)) {
          final path = await step('the signal path', c.audio.signalPath);
          if (path != null) stages[name] = path.filters;
        }
        await tester.pump(const Duration(milliseconds: 20));
      }
      await step('stop after', c.player.stop); // closes (and finishes) the WAV
      await tester.pump(const Duration(milliseconds: 300));
      final m = measureWav(File(out));
      // ignore: avoid_print
      print('DSP $name: ${m.db.map((d) => d.toStringAsFixed(2)).join(' / ')} dB at ${m.rate} Hz, ${stages[name]}');
      return m;
    }

    final dry = await render('dry', () async {});
    expect(dry.db[0], closeTo(-9.03, 0.3));
    expect(dry.db[1], lessThan(-100));

    final both = await render('mono both ears', () => c.audio.setMono(MonoAudio.both));
    expect(both.db[0], closeTo(dry.db[0] - 6.02, 0.2), reason: 'each ear gets half of left plus right');
    expect(both.db[1], closeTo(both.db[0], 0.05));

    final left = await render('mono left', () => c.audio.setMono(MonoAudio.left));
    expect(left.db[0], closeTo(both.db[0], 0.05));
    expect(left.db[1], lessThan(-100), reason: 'nothing on the right');

    final right = await render('mono right', () => c.audio.setMono(MonoAudio.right));
    expect(right.db[1], closeTo(both.db[0], 0.05));
    expect(right.db[0], lessThan(-100), reason: 'nothing on the left');

    final speakers = await render('virtual speakers', () async {
      await c.audio.setMono(MonoAudio.off);
      await c.audio.setVirtualSpeakers(true);
    });
    expect(c.audio.hrirPath, isNotNull, reason: 'the HRIR asset became a file');
    expect(speakers.rate, 48000);
    expect(speakers.db[1], greaterThan(speakers.db[0] - 20), reason: 'the right ear hears the left speaker too');
    expect(speakers.db[1], lessThan(speakers.db[0]), reason: 'but quieter, from across the head');

    final crossfed = await render('crossfeed', () async {
      await c.audio.setVirtualSpeakers(false);
      await c.audio.setCrossfeed(0.5);
    });
    expect(crossfed.db[1], greaterThan(-60), reason: 'some of the left reaches the right');
    expect(crossfed.db[1], lessThan(crossfed.db[0]));

    final corrected = await render('room correction', () async {
      await c.audio.setCrossfeed(0);
      c.audio
        ..impulsePath = dirac.path
        ..impulseName = 'dirac';
      await c.audio.setConvolution(true);
    });
    expect(corrected.db[0], closeTo(dry.db[0], 0.5), reason: 'a unit impulse leaves the sound as it is');
    expect(stages['room correction'], contains('Room correction (dirac)'), reason: 'the graph opened the odd path');

    if (AudioEngine.hasExclusiveMode) {
      // Exclusive mode: mpv turns the sound into the DAC's integer format itself, where a sample past
      // full scale would be cut off flat. A tone 3.5 dB past it, as a loud song decoded from Opus can be.
      final hot = writeWav(
        '${dir.path}/hot.wav',
        48000 * 4,
        (i) => (1.5 * math.sin(2 * math.pi * 440 * i / 48000), 0),
        float: true,
      );
      final guarded = await render('clip protection', () async {
        await c.audio.setConvolution(false);
        await c.audio.setExclusive(true);
      }, input: hot);
      expect(guarded.peak, lessThan(0.01), reason: 'lowered to full scale, not past it');
      expect(guarded.db[0], closeTo(-3.01, 0.3), reason: 'a sine right at full scale');
      final untouched = await render('clip protection, quiet song', () async {}, input: song);
      expect(untouched.db[0], closeTo(dry.db[0], 0.01), reason: 'nothing past full scale: the sound as it was');
      await tester.runAsync(() => c.audio.setExclusive(false));
    }

    c.dispose();
  });
}

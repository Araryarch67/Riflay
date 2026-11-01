import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/beta_features.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:riflay/services/audio_engine.dart';
import 'package:riflay/services/visualizer_spectrum.dart';

import '../integration_test/wav_util.dart';

void main() {
  test('mpv metering preserves every PCM sample and the complete song', () async {
    final dir = Directory.systemTemp.createTempSync('riflay-meter-pcm-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final source = writeWav('${dir.path}/source.wav', 48000, (i) {
      final amplitude = i < 4800 ? 0 : 0.4 * (1 + math.sin(i / 700));
      return (amplitude * math.sin(i * 0.2), amplitude * math.sin(i * 0.35));
    }, float: true);
    Future<List<int>> render(String name, String filter) async {
      final out = '${dir.path}/$name.pcm';
      final result = await Process.run('mpv', [
        '--no-config',
        '--no-video',
        '--no-terminal',
        '--ao=pcm',
        '--ao-pcm-file=$out',
        '--ao-pcm-waveheader=no',
        '--audio-format=float',
        if (filter.isNotEmpty) '--af=$filter',
        source.path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      return File(out).readAsBytes();
    }

    final plain = await render('plain', '');
    final metered = await render('metered', AudioEngine.visualizerFilter);
    expect(plain.length, 48000 * 2 * 4);
    expect(metered, plain, reason: 'visualization must not change audio samples or truncate the end');
  }, skip: !Platform.isLinux);

  for (final (channels, layout) in [(1, 'mono'), (6, '5.1')]) {
    test('spectrum preserves every original channel for $layout audio', () async {
      final dir = Directory.systemTemp.createTempSync('riflay-spectrum-channels-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final source = '${dir.path}/source.wav';
      final generated = await Process.run('ffmpeg', [
        '-loglevel',
        'error',
        '-f',
        'lavfi',
        '-i',
        'aevalsrc=${List.generate(channels, (i) => '0.3*sin(2*PI*${90 + i * 310}*t)').join('|')}:s=48000:d=0.1:c=$layout',
        '-c:a',
        'pcm_f32le',
        source,
      ]);
      expect(generated.exitCode, 0, reason: '${generated.stderr}');
      Future<List<int>> render(String name, {String? filter}) async {
        final path = '${dir.path}/$name.pcm';
        final result = await Process.run('mpv', [
          '--no-config',
          '--no-video',
          '--no-terminal',
          '--ao=pcm',
          '--audio-channels=auto',
          '--ao-pcm-file=$path',
          '--ao-pcm-waveheader=no',
          '--audio-format=float',
          if (filter != null) '--af=$filter',
          source,
        ]);
        expect(result.exitCode, 0, reason: '${result.stderr}');
        return File(path).readAsBytes();
      }

      final plain = await render('plain');
      final metered = await render(
        'metered',
        filter: VisualizerSpectrum.filter(channels: channels, layout: layout),
      );
      expect(plain.length, 4800 * channels * 4);
      expect(metered, plain, reason: 'the analysis must not reorder, mix or truncate original channels');
    }, skip: !Platform.isLinux);
  }

  test('turning beta off blocks analysis even while a view holds a lease', () async {
    SharedPreferences.setMockInitialValues({});
    await BetaFeatures.instance.reload();
    final engine = AudioEngine();
    final release = engine.watchVisualizer();
    expect(engine.filterChain, isNot(contains('@visualizer')));
    await BetaFeatures.instance.set(BetaFeature.audioVisualizer, true);
    expect(engine.filterChain, contains('@visualizer'));
    engine.visualizerLevels.add('-6');
    await BetaFeatures.instance.set(BetaFeature.audioVisualizer, false);
    expect(engine.filterChain, isNot(contains('@visualizer')));
    expect(engine.visualizerLevels.value, everyElement(0));
    release();
    engine.dispose();
  });

  test('bit-perfect audio never acquires an analysis filter', () async {
    SharedPreferences.setMockInitialValues({'features.audioVisualizer': true});
    await BetaFeatures.instance.reload();
    final engine = AudioEngine();
    final release = engine.watchVisualizer();
    expect(engine.filterChain, contains('@visualizer'));
    engine.bitPerfect = true;
    expect(engine.filterChain, isNot(contains('@visualizer')));
    release();
    release(); // A disposed or hidden view can release only once.
    expect(engine.visualizerActive, isFalse);
    engine.dispose();
  });
}

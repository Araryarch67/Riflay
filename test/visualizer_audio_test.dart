import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/audio_engine.dart';

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

  test('bit-perfect audio never acquires an analysis filter', () {
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

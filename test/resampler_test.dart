import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/audio_engine.dart';
import 'package:riflay/services/linux_alsa.dart';

/// mpv and ffmpeg on the PATH (Linux development machines): the measurements below need both.
bool get _tools => ['mpv', 'ffmpeg'].every((t) {
  try {
    return Process.runSync('which', [t]).exitCode == 0;
  } catch (_) {
    return false;
  }
});

void main() {
  group("PipeWire's rate", () {
    String meta({String rate = '48000', String allowed = '[ 48000 ]', String force = '0'}) =>
        "update: id:0 key:'clock.rate' value:'$rate' type:''\n"
        "update: id:0 key:'clock.allowed-rates' value:'$allowed' type:''\n"
        "update: id:0 key:'clock.force-rate' value:'$force' type:''\n";

    test('one allowed rate (the default): Riflay resamples to it', () {
      expect(LinuxAlsa.fixedRateOf(meta()), 48000);
    });
    test('several allowed rates: PipeWire follows the song, nothing resamples', () {
      expect(LinuxAlsa.fixedRateOf(meta(allowed: '[ 44100, 48000, 96000 ]')), isNull);
    });
    test('a forced rate wins', () {
      expect(LinuxAlsa.fixedRateOf(meta(allowed: '[ 44100, 48000 ]', force: '96000')), 96000);
    });
    test('nothing readable: leave the rate alone', () {
      expect(LinuxAlsa.fixedRateOf(''), isNull);
    });
  });

  group('the high-quality resampler, measured through mpv', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('resampler'));
    tearDown(() => dir.deleteSync(recursive: true));

    /// A 0.7 sine at [hz] in [rate], resampled by mpv to 48 kHz with [options]; returns its level change in dB.
    Future<double> gain(int hz, int rate, String options) async {
      final src = '${dir.path}/in.wav', out = '${dir.path}/out.wav';
      await Process.run('ffmpeg', [
        '-loglevel', 'error', '-y', '-f', 'lavfi', //
        '-i', 'aevalsrc=0.7*sin(2*PI*$hz*t):s=$rate:d=2', '-c:a', 'pcm_f32le', src,
      ]);
      await Process.run('mpv', [
        '--no-config', '--really-quiet', '--ao=pcm', '--ao-pcm-file=$out', '--audio-format=floatp', //
        '--audio-samplerate=48000', '--audio-swresample-o=$options', src,
      ]);
      final raw = await Process.run('ffmpeg', [
        '-loglevel',
        'error',
        '-i',
        out,
        '-f',
        'f64le',
        '-ac',
        '1',
        '-',
      ], stdoutEncoding: null);
      final x = Float64List.view(Uint8List.fromList(raw.stdout as List<int>).buffer);
      final mid = x.sublist(x.length ~/ 4, 3 * x.length ~/ 4);
      final rms = sqrt(mid.fold<double>(0, (a, v) => a + v * v) / mid.length);
      return 20 * log(max(rms, 1e-12) / (0.7 / sqrt2)) / ln10;
    }

    test('flat to 21 kHz from 44.1 kHz (SoX\'s default rolled 20 kHz off by 8.5 dB)', () async {
      for (final hz in [1000, 15000, 20000, 21000]) {
        expect(await gain(hz, 44100, AudioEngine.soxrOptions), closeTo(0, 0.1), reason: '$hz Hz');
      }
    }, skip: !_tools);

    test('keeps what lies above 24 kHz out when a 96 kHz file goes to 48 kHz', () async {
      for (final hz in [25000, 30000]) {
        expect(await gain(hz, 96000, AudioEngine.soxrOptions), lessThan(-120), reason: '$hz Hz');
      }
    }, skip: !_tools);
  });
}

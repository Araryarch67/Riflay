import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/audio_analysis_core.dart';

/// [seconds] of stereo at [rate], the same in both channels, from [sample] (time in seconds → -1…1).
AudioReport measure(int rate, double seconds, double Function(double t) sample) {
  final a = AudioAnalyzer(rate: rate, channels: 2);
  final n = (rate * seconds).round();
  const chunk = 9600;
  for (var start = 0; start < n; start += chunk) {
    final len = math.min(chunk, n - start);
    final data = Float64List(len * 2);
    for (var i = 0; i < len; i++) {
      final v = sample((start + i) / rate);
      data[i * 2] = v;
      data[i * 2 + 1] = v;
    }
    a.add(data);
  }
  return a.finish();
}

/// Many sines at random frequencies below [top]: sound up to a wall, nothing past it (as an MP3 is cut).
double Function(double) below(double top, {int seed = 1}) {
  final r = math.Random(seed);
  final parts = [for (var i = 0; i < 300; i++) (100 + r.nextDouble() * (top - 100), r.nextDouble() * 2 * math.pi)];
  return (t) {
    var v = 0.0;
    for (final (f, phase) in parts) {
      v += math.sin(2 * math.pi * f * t + phase);
    }
    return v / parts.length * 2;
  };
}

void main() {
  test('a 1 kHz sine at -20 dBFS in both channels is -20 LUFS, peaks at -20 dBFS, and has no dynamics', () {
    final r = measure(48000, 10, (t) => 0.1 * math.sin(2 * math.pi * 1000 * t));
    expect(r.lufs, closeTo(-20, 0.3));
    expect(r.gainDb, closeTo(2, 0.3), reason: 'ReplayGain 2.0 brings it to -18 LUFS');
    expect(r.peakDb, closeTo(-20, 0.05));
    expect(r.dr, 0);
  });

  test('noise is full band with the DR its peak-to-loudness gives', () {
    final random = math.Random(3);
    final r = measure(44100, 20, (_) => random.nextDouble() * 1.6 - 0.8);
    expect(r.verdict, SourceVerdict.fullBand);
    expect(r.cutoffHz, isNull);
    expect(r.dr, 2, reason: 'uniform noise: peak over √2 × RMS is √(3/2), 1.8 dB');
  });

  test('a lossless file cut sharply at 16 kHz came from a lossy one', () {
    final r = measure(44100, 12, below(16000));
    expect(r.verdict, SourceVerdict.lossyCut);
    expect(r.cutoffHz, closeTo(16000, 400));
  });

  test('a 96 kHz file with nothing above 22 kHz is upsampled', () {
    final r = measure(96000, 8, below(21500, seed: 2));
    expect(r.verdict, SourceVerdict.upsampled);
  });

  test("a 96 kHz file whose sound slopes away from 21 to 26 kHz (a resampler's filter) is upsampled", () {
    final r = measure(96000, 8, (t) {
      var v = below(21000, seed: 4)(t);
      // A quieter band above, as a resampler's slope leaves.
      for (var f = 22000.0; f < 25500; f += 350) {
        v += 0.004 * math.sin(2 * math.pi * f * t + f);
      }
      return v;
    });
    expect(r.verdict, SourceVerdict.upsampled);
  });

  test('a spectrogram over the song, saved without it', () {
    final r = measure(44100, 12, below(16000));
    expect(r.columns, greaterThan(40));
    expect(r.spectrogram!.length, r.columns * AudioAnalyzer.rows);
    // Bright under the wall, dark over it.
    int rowAt(double hz) => (hz / 22050 * AudioAnalyzer.rows).floor();
    int at(double hz) => r.spectrogram![rowAt(hz) * r.columns + r.columns ~/ 2];
    expect(at(8000), greaterThan(at(19000) + 60));
    final saved = AudioReport.fromJson(r.toJson());
    expect(saved.verdict, SourceVerdict.lossyCut);
    expect(saved.lufs, r.lufs);
    expect(saved.spectrogram, isNull);
  });

  test('silence has no loudness', () {
    final r = measure(48000, 3, (_) => 0);
    expect(r.lufs, isNull);
    expect(r.gainDb, isNull);
  });
}

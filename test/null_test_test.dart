import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/null_test.dart';

const _rate = 48000;

/// Music-like sound that can be read at any time, so a delay or a resample is exact: short tone bursts (5 to 30 ms
/// each, 40 Hz to 15 kHz) at random moments, many at once, so it has starts to line up on like music does.
class _Sound {
  _Sound(int seed) {
    final r = math.Random(seed);
    for (var i = 0; i < 2400; i++) {
      _bursts.add((
        at: r.nextDouble() * 4.2 * _rate,
        width: (0.005 + r.nextDouble() * 0.025) * _rate,
        freq: 2 * math.pi * (40 + math.pow(r.nextDouble(), 2) * 15000) / _rate,
        amp: 0.01 + r.nextDouble() * 0.05,
        phase: [r.nextDouble() * 2 * math.pi, r.nextDouble() * 2 * math.pi],
      ));
    }
    _bursts.sort((a, b) => a.at.compareTo(b.at));
  }

  final _bursts = <({double at, double width, double freq, double amp, List<double> phase})>[];
  static const _longest = 0.03 * _rate * 4;

  /// Channel [c] at frame [t].
  double at(double t, int c) {
    var s = 0.0;
    var lo = 0, hi = _bursts.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_bursts[mid].at < t - _longest) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    for (var i = lo; i < _bursts.length && _bursts[i].at <= t + _longest; i++) {
      final b = _bursts[i], x = (t - b.at) / b.width;
      if (x.abs() > 4) continue;
      s += b.amp * math.exp(-x * x) * math.sin(b.freq * (t - b.at) + b.phase[c]);
    }
    return s;
  }

  /// [frames] stereo frames from [start], every [step] frames apart, as 16-bit samples when [quantize].
  Float64List read(double start, int frames, {double step = 1, bool quantize = false}) {
    final x = Float64List(frames * 2);
    for (var i = 0; i < frames; i++) {
      for (var c = 0; c < 2; c++) {
        final v = at(start + i * step, c);
        x[i * 2 + c] = quantize ? (v * 32768).roundToDouble() / 32768 : v;
      }
    }
    return x;
  }
}

void main() {
  final sound = _Sound(7);
  const lead = 24000; // half a second of source before the output's expected start
  final reference = sound.read(0, 4 * _rate, quantize: true);
  Float64List slice(int from, int frames) => Float64List.sublistView(reference, from * 2, (from + frames) * 2);

  NullTestResult run(Float64List output) =>
      NullTest.compare(reference, output, channels: 2, rate: _rate, expected: lead.toDouble())!;

  test('the same samples are bit-perfect and null to the floor', () {
    final r = run(Float64List.fromList(slice(lead, 3 * _rate)));
    expect(r.identical, 1);
    expect(r.bitPerfect, isTrue);
    expect(r.gainDb, 0);
    expect(r.offsetMs, 0);
    expect(r.diffRmsDb, NullTest.floorDb);
    expect(r.diffRmsDba, NullTest.floorDb);
    expect(r.nullDb, -NullTest.floorDb);
    expect(r.nullDba, -NullTest.floorDb);
    expect(r.driftPpm, 0);
    expect(r.quality, FitQuality.excellent);
  });

  test('a gain change shows as gain and nulls out', () {
    final out = Float64List.fromList(slice(lead, 3 * _rate));
    for (var i = 0; i < out.length; i++) {
      out[i] *= 0.5;
    }
    final r = run(out);
    expect(r.bitPerfect, isFalse);
    expect(r.gainDb, closeTo(-6.0206, 0.001));
    expect(r.nullDb, greaterThan(150));
    expect(r.quality, FitQuality.excellent);
  });

  test('a delay of whole samples is the offset, and still bit-perfect', () {
    final r = run(Float64List.fromList(slice(lead + 48, 3 * _rate)));
    expect(r.bitPerfect, isTrue);
    expect(r.offsetMs, closeTo(1, 1e-9));
    final early = run(Float64List.fromList(slice(lead - 4320, 3 * _rate)));
    expect(early.offsetMs, closeTo(-90, 1e-9));
  });

  test('a delay of a fraction of a sample is found to the fraction', () {
    final r = run(sound.read(lead + 10.5, 3 * _rate));
    expect(r.offsetMs, closeTo(10.5 / 48, 0.002));
    expect(r.driftPpm.abs(), lessThan(0.5));
    expect(r.gainDb.abs(), lessThan(0.01));
    expect(r.nullDb, greaterThan(60));
    expect(r.quality, FitQuality.excellent);
  });

  test('a resample to a faster clock is drift', () {
    // The output takes 100 ppm more samples for the same sound.
    final r = run(sound.read(lead + 3, 3 * _rate, step: 1 / (1 + 100e-6)));
    expect(r.driftPpm, closeTo(100, 0.2));
    expect(r.offsetMs, closeTo(3 / 48, 0.01));
    expect(r.nullDb, greaterThan(50));
    expect(r.identical, lessThan(0.01));
  });

  test('added noise is the difference', () {
    final noise = math.Random(3);
    final out = Float64List.fromList(slice(lead, 3 * _rate));
    var signal = 0.0;
    for (final v in out) {
      signal += v * v;
    }
    signal = math.sqrt(signal / out.length);
    const level = 1e-4; // -80 dBFS
    for (var i = 0; i < out.length; i++) {
      // Gaussian, Box-Muller.
      final g = math.sqrt(-2 * math.log(1 - noise.nextDouble())) * math.cos(2 * math.pi * noise.nextDouble());
      out[i] += g * level;
    }
    final r = run(out);
    expect(r.diffRmsDb, closeTo(-80, 0.3));
    // White noise loses a few dB to A-weighting (most of its power is high, where the weighting falls again).
    expect(r.diffRmsDba, inInclusiveRange(-86, -80));
    expect(r.nullDb, closeTo(20 * math.log(signal / level) / math.ln10, 0.3));
    expect(r.gainDb.abs(), lessThan(0.001));
    expect(r.driftPpm, 0);
    expect(r.offsetMs, 0);
    expect(r.bitPerfect, isFalse);
    expect(r.quality, FitQuality.excellent);
  });

  test('silence or too little to compare gives nothing', () {
    expect(NullTest.compare(reference, Float64List(3 * _rate * 2), channels: 2, rate: _rate, expected: 0), isNull);
    expect(NullTest.compare(reference, slice(0, 1000), channels: 2, rate: _rate, expected: 0), isNull);
  });
}

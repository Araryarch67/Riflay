import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/true_peak.dart';

void main() {
  // fs/4 with a 45° phase: every sample is ±0.7071, yet the wave itself reaches 1.0, always between samples.
  final between = [for (var n = 0; n < 400; n++) math.sin(math.pi / 2 * n + math.pi / 4)];

  test('a sine peaking between samples reads about 0 dBTP while its samples top out at -3 dBFS', () {
    final sampleDb = 20 * math.log(between.map((x) => x.abs()).reduce(math.max)) / math.ln10;
    expect(sampleDb, closeTo(-3.01, 0.01));
    expect(truePeakDb(between), closeTo(0, 0.3));
  });

  test('a sine that hits its peak on a sample reads the same as the sample peak', () {
    final on = [for (var n = 0; n < 400; n++) 0.5 * math.sin(math.pi / 2 * n + math.pi / 2)];
    expect(truePeakDb(on), closeTo(-6.02, 0.05));
  });

  test('silence is -120 and a negative peak counts like a positive one', () {
    expect(truePeakDb(List.filled(100, 0.0)), -120);
    expect(truePeakDb(between.map((x) => -x)), closeTo(truePeakDb(between), 1e-9));
  });

  test('feeding in pieces gives the same peak as feeding at once', () {
    final m = TruePeakMeter();
    between.forEach(m.add);
    expect(20 * math.log(m.peak) / math.ln10, closeTo(truePeakDb(between), 1e-9));
  });
}

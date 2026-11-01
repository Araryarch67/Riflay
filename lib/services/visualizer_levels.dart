import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// A short history of the decoded audio's RMS level, not a synthetic spectrum.
/// Logarithmic display keeps quiet passages visible without animating silence.
class VisualizerLevels extends ValueNotifier<List<double>> {
  VisualizerLevels() : super(List.filled(samples, 0));

  static const samples = 64;
  double _level = 0;
  double frame = 0;
  double backgroundEnergy = 0;

  static double amplitude(String metadata) {
    final db = double.tryParse(metadata);
    if (db == null || !db.isFinite || db <= -60) return 0;
    return ((db + 60) / 60).clamp(0.0, 1.0);
  }

  void add(String metadata) {
    frame++;
    final target = amplitude(metadata);
    // Fast attack, slower release. The history itself is the horizontal wave.
    _level += (target - _level) * (target > _level ? 0.7 : 0.22);
    backgroundEnergy = _level;
    value = [...value.skip(1), math.max(0, _level)];
  }

  void clear() {
    _level = 0;
    backgroundEnergy = 0;
    value = List.filled(samples, 0);
  }

  /// Smooth display updates at the screen's refresh rate without polling audio
  /// more often. The exponential blend behaves the same at 60 and 120 Hz.
  bool follow(VisualizerLevels source, Duration elapsed) {
    final blend = 1 - math.exp(-elapsed.inMicroseconds / 45000);
    var moving = false;
    double approach(double from, double to) {
      if ((to - from).abs() < 0.001) return to;
      moving = true;
      return from + (to - from) * blend;
    }

    frame = approach(frame, source.frame);
    backgroundEnergy = approach(backgroundEnergy, source.backgroundEnergy);
    value = List.generate(samples, (i) => approach(value[i], source.value[i]));
    return moving;
  }
}

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// A short history of the decoded audio's RMS level, not a synthetic spectrum.
/// Logarithmic display keeps quiet passages visible without animating silence.
class VisualizerLevels extends ValueNotifier<List<double>> {
  VisualizerLevels() : super(List.filled(samples, 0));

  static const samples = 64;
  double _level = 0;
  int frame = 0;
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
    value = List.filled(samples, 0);
  }
}

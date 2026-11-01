import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'visualizer_spectrum.dart';

/// Current logarithmic frequency bands. Band positions stay fixed while heights move.
class VisualizerLevels extends ValueNotifier<List<double>> {
  VisualizerLevels() : super(List.filled(samples, 0));

  static const samples = VisualizerSpectrum.bands;
  double _level = 0;
  double frame = 0;
  double backgroundEnergy = 0;
  double beat = 0;

  static double amplitude(String metadata) {
    final db = double.tryParse(metadata);
    if (db == null || !db.isFinite || db <= -60) return 0;
    return ((db + 60) / 60).clamp(0.0, 1.0);
  }

  /// One value per frequency band in the current audio frame, ordered bass to treble.
  /// The map is read whole to avoid the bundled mpv's unsafe sub-key lookup.
  void addMetadata(String metadata, {int firstBandChannel = 3}) {
    Map<String, dynamic> values = const {};
    try {
      final decoded = jsonDecode(metadata);
      if (decoded is Map<String, dynamic>) values = decoded;
    } on FormatException {
      // No frame yet, or the filter was just removed.
    }
    final levels = List.generate(samples, (i) {
      final raw = values['lavfi.astats.${firstBandChannel + i}.RMS_level'];
      return amplitude(raw?.toString() ?? '');
    });
    addBands(levels);
  }

  void addBands(List<double> bands) {
    frame++;
    var onset = 0.0;
    for (var i = 0; i < math.min(10, bands.length); i++) {
      if (bands[i].isFinite) onset += math.max(0, bands[i].clamp(0.0, 1.0) - value[i]);
    }
    // Bass onsets produce a visible kick; sustained tones never fabricate beats.
    beat = math.max(beat * 0.72, (onset * 1.8).clamp(0.0, 1.0));
    value = List.generate(samples, (i) {
      final target = i < bands.length && bands[i].isFinite ? bands[i].clamp(0.0, 1.0) : 0.0;
      final current = value[i];
      return current + (target - current) * (target > current ? 0.85 : 0.28);
    });
    _level = value.reduce(math.max);
    backgroundEnergy = _level;
  }

  /// A scalar input is a simultaneous level, never a scrolling history.
  void add(String metadata) => addBands(List.filled(samples, amplitude(metadata)));

  void clear() {
    _level = 0;
    backgroundEnergy = 0;
    beat = 0;
    value = List.filled(samples, 0);
  }

  /// Smooth display updates at the screen's refresh rate without polling audio
  /// more often. The exponential blend behaves the same at 60 and 120 Hz.
  bool follow(VisualizerLevels source, Duration elapsed) {
    final blend = 1 - math.exp(-elapsed.inMicroseconds / 28000);
    var moving = false;
    double approach(double from, double to) {
      if ((to - from).abs() < 0.001) return to;
      moving = true;
      return from + (to - from) * blend;
    }

    frame = approach(frame, source.frame);
    backgroundEnergy = approach(backgroundEnergy, source.backgroundEnergy);
    beat = approach(beat, source.beat);
    value = List.generate(samples, (i) => approach(value[i], source.value[i]));
    return moving;
  }
}

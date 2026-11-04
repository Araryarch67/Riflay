import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'visualizer_spectrum.dart';

/// Current logarithmic frequency bands. Band positions stay fixed while heights move.
class VisualizerLevels extends ValueNotifier<List<double>> {
  VisualizerLevels() : super(Float64List(samples));

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
  /// The map is read whole to avoid the bundled mpv's unsafe sub-key lookup; the keys are
  /// scanned in place rather than jsonDecoded, since this runs every 40 ms.
  void addMetadata(String metadata, {int firstBandChannel = 3}) {
    final levels = _scratch;
    levels.fillRange(0, samples, 0);
    const prefix = '"lavfi.astats.';
    const suffix = '.RMS_level"';
    var at = metadata.indexOf(prefix);
    while (at >= 0) {
      var i = at + prefix.length;
      var channel = 0;
      while (i < metadata.length) {
        final digit = metadata.codeUnitAt(i) - 0x30;
        if (digit < 0 || digit > 9) break;
        channel = channel * 10 + digit;
        i++;
      }
      final band = channel - firstBandChannel;
      if (i > at + prefix.length && band >= 0 && band < samples && metadata.startsWith(suffix, i)) {
        i += suffix.length;
        while (i < metadata.length && (metadata.codeUnitAt(i) == 0x3a || metadata.codeUnitAt(i) == 0x20)) {
          i++;
        }
        if (i < metadata.length && metadata.codeUnitAt(i) == 0x22) i++;
        var end = i;
        while (end < metadata.length) {
          final c = metadata.codeUnitAt(end);
          if (c == 0x22 || c == 0x2c || c == 0x7d) break;
          end++;
        }
        levels[band] = amplitude(metadata.substring(i, end));
      }
      at = metadata.indexOf(prefix, at + prefix.length);
    }
    addBands(levels);
  }

  final _scratch = Float64List(samples);

  void addBands(List<double> bands) {
    frame++;
    var onset = 0.0;
    for (var i = 0; i < math.min(10, bands.length); i++) {
      if (bands[i].isFinite) onset += math.max(0, bands[i].clamp(0.0, 1.0) - value[i]);
    }
    // Bass onsets produce a visible kick; sustained tones never fabricate beats.
    beat = math.max(beat * 0.72, (onset * 1.8).clamp(0.0, 1.0));
    // A fresh list per update: listeners compare by identity to see that the levels moved.
    final next = Float64List(samples);
    var peak = 0.0;
    for (var i = 0; i < samples; i++) {
      final target = i < bands.length && bands[i].isFinite ? bands[i].clamp(0.0, 1.0) : 0.0;
      final current = value[i];
      final v = current + (target - current) * (target > current ? 0.85 : 0.28);
      next[i] = v;
      if (v > peak) peak = v;
    }
    value = next;
    _level = peak;
    backgroundEnergy = _level;
  }

  /// A scalar input is a simultaneous level, never a scrolling history.
  void add(String metadata) => addBands(List.filled(samples, amplitude(metadata)));

  void clear() {
    _level = 0;
    backgroundEnergy = 0;
    beat = 0;
    value = Float64List(samples);
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
    final next = Float64List(samples), from = value, to = source.value;
    for (var i = 0; i < samples; i++) {
      next[i] = approach(from[i], to[i]);
    }
    value = next;
    return moving;
  }
}

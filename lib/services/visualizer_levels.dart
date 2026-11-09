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

  static double amplitude(String metadata) => amplitudeOfDb(double.tryParse(metadata));

  /// A level in dB as 0..1: -60 dB and below is nothing, 0 dB is full.
  static double amplitudeOfDb(double? db) {
    if (db == null || !db.isFinite || db <= -60) return 0;
    return ((db + 60) / 60).clamp(0.0, 1.0);
  }

  /// One value per frequency band in the current audio frame, ordered bass to treble, from `aspectralstats` (mean
  /// and variance per channel) or `astats` (RMS per channel). The map is read whole to avoid the bundled mpv's unsafe
  /// sub-key lookup; the keys are scanned in place rather than jsonDecoded, since this runs every 40 ms.
  /// [bands] measured (fewer than [samples]: Balanced's, see [VisualizerSpectrum.frugalBands]) are spread over the
  /// bars, each bar from the two measured bands either side of it; [window] is the FFT's length.
  void addMetadata(String metadata, {int firstBandChannel = 3, int bands = samples, int window = 1024}) {
    final levels = _scratch..fillRange(0, samples, 0);
    if (metadata.contains(_spectral)) {
      final mean = _mean..fillRange(0, samples, 0);
      final variance = _variance..fillRange(0, samples, 0);
      _scan(metadata, _spectral, '.mean"', firstBandChannel, bands, (band, v) => mean[band] = double.tryParse(v) ?? 0);
      _scan(
        metadata,
        _spectral,
        '.variance"',
        firstBandChannel,
        bands,
        (band, v) => variance[band] = double.tryParse(v) ?? 0,
      );
      for (var i = 0; i < bands; i++) {
        levels[i] = amplitudeOfDb(spectralDb(mean[i], variance[i], window: window));
      }
    } else {
      _scan(
        metadata,
        '"lavfi.astats.',
        '.RMS_level"',
        firstBandChannel,
        bands,
        (band, v) => levels[band] = amplitude(v),
      );
    }
    if (bands < samples) _spread(levels, bands);
    addBands(levels);
  }

  /// [measured] bands in the first slots of [levels], spread over all [samples] bars in place.
  static void _spread(Float64List levels, int measured) {
    final from = Float64List.fromList(levels.sublist(0, measured));
    for (var i = 0; i < samples; i++) {
      final at = i * (measured - 1) / (samples - 1);
      final lo = at.floor(), hi = math.min(lo + 1, measured - 1);
      levels[i] = from[lo] + (from[hi] - from[lo]) * (at - lo);
    }
  }

  static const _spectral = '"lavfi.aspectralstats.';

  /// A band's RMS in dB from `aspectralstats`' mean and variance of its [window]-point magnitude spectrum: variance
  /// plus mean squared is the window's power (Parseval), 34.6 dB under what `astats` reports for the same samples at
  /// 1024 points, for a tone, noise or any band (within 0.4 dB), and 6 dB further under at 4096 (measured: 6.06-6.42).
  /// So the bars stand as tall as they did with `astats`.
  static double? spectralDb(double mean, double variance, {int window = 1024}) {
    final power = variance + mean * mean;
    return power > 0 && power.isFinite
        ? 10 * math.log(power) / math.ln10 + 34.6 + 10 * math.log(window / 1024) / math.ln10
        : null;
  }

  /// Calls [found] with the band and raw value of every `<prefix><channel><suffix>` key in [metadata].
  static void _scan(
    String metadata,
    String prefix,
    String suffix,
    int firstBandChannel,
    int bands,
    void Function(int band, String value) found,
  ) {
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
      if (i > at + prefix.length && band >= 0 && band < bands && metadata.startsWith(suffix, i)) {
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
        found(band, metadata.substring(i, end));
      }
      at = metadata.indexOf(prefix, at + prefix.length);
    }
  }

  final _mean = Float64List(samples);
  final _variance = Float64List(samples);
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

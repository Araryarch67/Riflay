import 'dart:math' as math;

import 'audio_engine.dart';

/// How much louder (+) or quieter (-), in dB, music sounds through [bands] and their [preamp] than
/// without the equalizer. Pink-noise-like music has equal energy in every octave, so the curve's power
/// response is averaged over log-spaced frequencies (20 Hz to 20 kHz), not over the sliders.
double eqLoudnessChange(List<EqBand> bands, double preamp) {
  final on = bands.where((b) => b.gain.abs() > 0.05).toList();
  if (on.isEmpty) return 0;
  const steps = 300, rate = 48000.0;
  var sum = 0.0;
  for (var i = 0; i < steps; i++) {
    final f = 20 * math.pow(1000, i / (steps - 1)).toDouble();
    var db = 0.0;
    for (final b in on) {
      db += _peakingDb(b, f, rate);
    }
    sum += math.pow(10, db / 10);
  }
  return 10 * math.log(sum / steps) / math.ln10 + preamp;
}

/// The gain, in dB (never above 0, so it can't clip), the bypassed side of an A/B comparison gets to
/// sound as loud as the equalized one: the quieter of the two stays as it is, the louder is turned down.
double eqBypassTrim(List<EqBand> bands, double preamp) => math.min(0, eqLoudnessChange(bands, preamp));

/// One RBJ peaking filter's response at [f], as FFmpeg's `equalizer` makes it.
double _peakingDb(EqBand b, double f, double rate) {
  final w0 = 2 * math.pi * b.frequency / rate, alpha = math.sin(w0) / (2 * b.q);
  final a = math.pow(10, b.gain / 40).toDouble(), c = -2 * math.cos(w0);
  final cos1 = math.cos(2 * math.pi * f / rate), cos2 = 2 * cos1 * cos1 - 1;
  double power(double c0, double c1, double c2) =>
      c0 * c0 + c1 * c1 + c2 * c2 + 2 * c1 * (c0 + c2) * cos1 + 2 * c0 * c2 * cos2;
  final num = power(1 + alpha * a, c, 1 - alpha * a), den = power(1 + alpha / a, c, 1 - alpha / a);
  return 10 * math.log(num / den) / math.ln10;
}

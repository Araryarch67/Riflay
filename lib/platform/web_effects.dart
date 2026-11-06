/// The sound effects the web build can apply with Web Audio, handed from `AudioEngine` to `web_audio.dart`, and
/// the visualizer's band arithmetic. Plain Dart, so both builds (and tests) can use it.
library;

import 'dart:math' as math;

/// One peaking filter, as `AudioEngine`'s `EqBand`: [gain] in dB, [q] its Q (1.41 is one octave).
typedef WebEqBand = ({double frequency, double gain, double q});

/// Which side(s) Mono audio plays on; [WebEffects.mono] is null in stereo.
enum WebMono { both, left, right }

/// Everything Web Audio does to the sound. The default changes nothing.
class WebEffects {
  const WebEffects({this.preamp = 0, this.eq = const [], this.crossfeed = 0, this.crossfeedRange = 0.5, this.mono});

  /// dB before the equalizer (negative, so boosted bands can't clip).
  final double preamp;

  /// The equalizer's bands; empty when it is off.
  final List<WebEqBand> eq;

  /// Headphone crossfeed strength 0..1 (0 = off).
  final double crossfeed;

  /// The crossfeed's soundstage 0..1: how far up the other side's sound reaches.
  final double crossfeedRange;

  final WebMono? mono;

  /// How much of the other side's low end each ear hears: [crossfeed]'s 0..1 as FFmpeg's `crossfeed` strength
  /// (0.1..0.7, as `AudioEngine.filterChain` sets it), halved since here it is a plain gain.
  double get crossfeedGain => crossfeed <= 0 ? 0 : (0.1 + crossfeed * 0.6) / 2;

  /// The low-pass on the other side's sound: about 1550 Hz at the default range, as FFmpeg's.
  double get crossfeedCutoff => 1000 + crossfeedRange * 1100;
}

/// Where each visualizer band starts and ends, in Hz, around [centers]: half a [widthOctaves] either side.
List<(double, double)> bandEdges(List<double> centers, double widthOctaves) {
  final factor = math.pow(2, widthOctaves / 2);
  return [for (final c in centers) (c / factor, c * factor)];
}

/// The total level, in dB, of the FFT bins (each a dB value, [binHz] apart) from [low] to [high] Hz; at least the
/// nearest bin counts. -infinity when the bins are silent.
double bandLevel(List<double> bins, double binHz, double low, double high) {
  if (bins.isEmpty || binHz <= 0) return double.negativeInfinity;
  var from = (low / binHz).ceil();
  var to = (high / binHz).floor();
  if (to < from) from = to = ((low + high) / 2 / binHz).round();
  from = from.clamp(1, bins.length - 1);
  to = to.clamp(from, bins.length - 1);
  var power = 0.0;
  for (var i = from; i <= to; i++) {
    final db = bins[i];
    if (db.isFinite) power += math.pow(10, db / 10);
  }
  return power <= 0 ? double.negativeInfinity : 10 * math.log(power) / math.ln10;
}

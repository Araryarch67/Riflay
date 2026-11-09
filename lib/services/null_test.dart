import 'dart:math' as math;
import 'dart:typed_data';

/// How well the output lined up with the source.
enum FitQuality { excellent, good, poor }

/// A null test of what came out against the source it was played from: the numbers DeltaWave shows, without jitter.
class NullTestResult {
  const NullTestResult({
    required this.identical,
    required this.gainDb,
    required this.offsetMs,
    required this.diffRmsDb,
    required this.diffRmsDba,
    required this.nullDb,
    required this.nullDba,
    required this.driftPpm,
    required this.quality,
    required this.seconds,
  });

  /// Share of samples (every channel's) that came out exactly as they went in, 0 to 1.
  final double identical;

  /// Every sample came out exactly as it went in.
  bool get bitPerfect => identical >= 1;

  /// The output's level against the source's, in dB (0: the same).
  final double gainDb;

  /// Where the output sat against where the player said it was, in ms. Negative: the sound came out later.
  final double offsetMs;

  /// The level of what is left once the source is taken from the output (its gain matched), in dBFS, plain and
  /// A-weighted; [NullTest.floorDb] when nothing is left.
  final double diffRmsDb, diffRmsDba;

  /// How far below the output that difference is, in dB, plain and A-weighted; -[NullTest.floorDb] when nothing is
  /// left.
  final double nullDb, nullDba;

  /// How much faster the output's clock ran than the source's, in parts per million.
  final double driftPpm;

  final FitQuality quality;

  /// How long a stretch was compared.
  final double seconds;

  @override
  String toString() =>
      'identical ${(identical * 100).toStringAsFixed(2)}%, gain ${gainDb.toStringAsFixed(3)} dB, '
      'offset ${offsetMs.toStringAsFixed(2)} ms, diff ${diffRmsDb.toStringAsFixed(2)} dB / '
      '${diffRmsDba.toStringAsFixed(2)} dBA, null ${nullDb.toStringAsFixed(2)} dB / ${nullDba.toStringAsFixed(2)} dBA, '
      'drift ${driftPpm.toStringAsFixed(3)} ppm, $quality, ${seconds.toStringAsFixed(1)} s';
}

/// Compares a recording of what a player sent out with the source it played, DeltaWave's way: line them up by
/// cross-correlation (to the sample, then to a fraction of one, and how that slides over the recording: the clock
/// drift), match their levels, take one from the other and measure what is left. Pure Dart, for an isolate.
abstract final class NullTest {
  /// Where a difference of nothing sits: no real difference reaches it.
  static const floorDb = -300.0;

  /// How far (in samples, either way) each block's fit looks around the last block's: 16 samples a block is a clock
  /// over 250 ppm off at 48 kHz.
  static const _driftReach = 16;
  static const _blocks = 8;

  /// Lines [output] up inside [reference] (both interleaved, [channels] wide, at [rate], full scale ±1) and measures
  /// the difference. [reference] must hold the whole of [output] somewhere, with room around it; [expected] is the
  /// frame of [reference] where [output] was expected to start (what [NullTestResult.offsetMs] is measured from).
  ///
  /// Null when the two can't be lined up (one is silent, or [output] is longer than [reference]).
  static NullTestResult? compare(
    Float64List reference,
    Float64List output, {
    required int channels,
    required int rate,
    required double expected,
  }) {
    final refFrames = reference.length ~/ channels, outFrames = output.length ~/ channels;
    if (outFrames < rate ~/ 2 || refFrames < outFrames) return null;
    final ref = _mono(reference, channels), out = _mono(output, channels);
    if (_energy(out) == 0 || _energy(ref) == 0) return null;

    // To the sample: a coarse search over everything on a decimated copy, then the full rate around it. Only the
    // first block: over the whole recording a drifting clock smears the peak.
    final block = outFrames ~/ _blocks;
    final step = math.max(1, rate ~/ 12000);
    final coarse = _bestLag(_decimate(ref, step), _decimate(Float64List.sublistView(out, 0, block), step)) * step;
    final lag = _refine(ref, out, coarse, 2 * step, 0, block);
    if (lag == null) return null;

    // To a fraction, block by block: a straight line through the blocks is the start and the drift.
    final xs = <double>[], ys = <double>[];
    var near = lag;
    for (var b = 0; b < _blocks; b++) {
      final at = b * block;
      final found = _refineFraction(ref, out, near, _driftReach, at, block);
      if (found == null) continue;
      xs.add(at + block / 2);
      ys.add(found);
      near = found.round();
    }
    if (xs.length < 3) return null;
    var (start, slope) = _line(xs, ys);
    var spread = _spread(xs, ys, start, slope);

    // Bit-perfect is judged on whole samples: the output's sample against the source's at the same place.
    var same = 0, counted = 0;
    for (var i = 0; i < outFrames && lag + i < refFrames; i++) {
      for (var c = 0; c < channels; c++) {
        counted++;
        if (output[i * channels + c] == reference[(lag + i) * channels + c]) same++;
      }
    }
    final identical = counted == 0 ? 0.0 : same / counted;

    // The source as it lines up with the output: as it is when the fit is a whole sample with no drift, else
    // interpolated to the fit.
    final whole = identical > 0.5 || ((start - lag).abs() < 0.05 && (slope * outFrames).abs() < 0.05);
    final aligned = Float64List(output.length);
    var first = 0, last = outFrames; // the frames both have
    if (whole) {
      last = math.min(outFrames, refFrames - lag);
      for (var i = 0; i < last * channels; i++) {
        aligned[i] = reference[lag * channels + i];
      }
    } else {
      // A parabola's peak leans toward the nearer whole sample, and over a 10 s recording a lean of a tenth of a
      // sample is a few ppm, enough to spoil the null at the top of the band: fit again against the source moved to
      // the first fit, where what is left to find is near zero and the lean with it.
      for (var pass = 0; pass < 2; pass++) {
        (first, last) = _span(start, slope, outFrames, refFrames);
        if (last - first < rate ~/ 2) return null;
        final moved = Float64List(outFrames);
        for (var i = first; i < last; i++) {
          moved[i] = _sinc(ref, 1, 0, start + (1 + slope) * i);
        }
        final rx = <double>[], ry = <double>[];
        for (var b = 0; b < _blocks; b++) {
          final at = math.max(first, b * block), count = math.min(last, (b + 1) * block) - at;
          if (count < block ~/ 2) continue;
          final found = _refineFraction(moved, out, 0, 1, at, count);
          if (found == null) continue;
          rx.add(at + count / 2);
          ry.add(found);
        }
        if (rx.length < 3) break;
        final (a, b) = _line(rx, ry);
        spread = _spread(rx, ry, a, b);
        start += a * (1 + slope);
        slope += b * (1 + slope);
      }
      (first, last) = _span(start, slope, outFrames, refFrames);
      for (var c = 0; c < channels; c++) {
        for (var i = first; i < last; i++) {
          aligned[i * channels + c] = _sinc(reference, channels, c, start + (1 + slope) * i);
        }
      }
    }
    if (last - first < rate ~/ 2) return null;

    // Levels matched by least squares, then what is left.
    var dot = 0.0, power = 0.0;
    for (var i = first * channels; i < last * channels; i++) {
      dot += output[i] * aligned[i];
      power += aligned[i] * aligned[i];
    }
    if (power == 0 || dot <= 0) return null;
    final gain = dot / power;
    final n = (last - first) * channels;
    final residual = Float64List(n), kept = Float64List(n);
    for (var i = 0; i < n; i++) {
      final at = first * channels + i;
      kept[i] = output[at];
      residual[i] = output[at] - gain * aligned[at];
    }
    final (diff, nul) = _levels(kept, residual);
    final weighted = _AWeighting(rate);
    final (diffA, nulA) = _levels(weighted.apply(kept, channels), weighted.apply(residual, channels));

    final quality = spread <= 0.02 && nul >= 20
        ? FitQuality.excellent
        : spread <= 0.25 && nul >= 6
        ? FitQuality.good
        : FitQuality.poor;
    return NullTestResult(
      identical: identical,
      gainDb: 20 * math.log(gain) / math.ln10,
      offsetMs: ((whole ? lag.toDouble() : start) - expected) / rate * 1000,
      diffRmsDb: diff,
      diffRmsDba: diffA,
      nullDb: nul,
      nullDba: nulA,
      driftPpm: whole ? 0 : -slope * 1e6,
      quality: quality,
      seconds: (last - first) / rate,
    );
  }

  /// The difference's rms in dBFS and how far below [signal] it is, in dB.
  static (double, double) _levels(Float64List signal, Float64List difference) {
    final s = _energy(signal), d = _energy(difference);
    if (d == 0) return (floorDb, -floorDb);
    final rms = 10 * math.log(d / difference.length) / math.ln10;
    return (math.max(floorDb, rms), math.min(-floorDb, 10 * math.log(s / d) / math.ln10));
  }

  static double _energy(Float64List x) {
    var e = 0.0;
    for (final v in x) {
      e += v * v;
    }
    return e;
  }

  static Float64List _mono(Float64List x, int channels) {
    final m = Float64List(x.length ~/ channels);
    for (var i = 0; i < m.length; i++) {
      var s = 0.0;
      for (var c = 0; c < channels; c++) {
        s += x[i * channels + c];
      }
      m[i] = s;
    }
    return m;
  }

  /// Averages of [step] samples.
  static Float64List _decimate(Float64List x, int step) {
    if (step == 1) return x;
    final d = Float64List(x.length ~/ step);
    for (var i = 0; i < d.length; i++) {
      var s = 0.0;
      for (var j = 0; j < step; j++) {
        s += x[i * step + j];
      }
      d[i] = s / step;
    }
    return d;
  }

  /// Where in [ref] [out] fits best (the start of [out] at that frame of [ref]), by FFT cross-correlation with the
  /// phase transform: every frequency weighs the same, so a held note's long hum doesn't outvote where sounds start.
  static int _bestLag(Float64List ref, Float64List out) {
    var size = 1;
    while (size < ref.length + out.length) {
      size <<= 1;
    }
    final ar = Float64List(size), ai = Float64List(size), br = Float64List(size), bi = Float64List(size);
    ar.setRange(0, ref.length, ref);
    br.setRange(0, out.length, out);
    _fft(ar, ai, false);
    _fft(br, bi, false);
    // ref ⋆ out: A · conj(B), each frequency brought to the same weight.
    for (var i = 0; i < size; i++) {
      final re = ar[i] * br[i] + ai[i] * bi[i], im = ai[i] * br[i] - ar[i] * bi[i];
      final mag = math.sqrt(re * re + im * im) + 1e-20;
      ar[i] = re / mag;
      ai[i] = im / mag;
    }
    _fft(ar, ai, true);
    var best = 0, bestValue = double.negativeInfinity;
    for (var lag = 0; lag <= ref.length - out.length; lag++) {
      if (ar[lag] > bestValue) {
        bestValue = ar[lag];
        best = lag;
      }
    }
    return best;
  }

  /// Σ out[i] · ref[lag + i] over the frames [from, from + count) of [out] (those [ref] has).
  static double _dot(Float64List ref, Float64List out, int lag, int from, int count) {
    var s = 0.0;
    final lo = math.max(from, -lag), hi = math.min(from + count, ref.length - lag);
    for (var i = lo; i < hi; i++) {
      s += out[i] * ref[lag + i];
    }
    return s;
  }

  /// The best whole lag within [reach] of [around], over [count] frames of [out] from [from].
  static int? _refine(Float64List ref, Float64List out, int around, int reach, int from, int count) {
    int? best;
    var bestValue = double.negativeInfinity;
    for (var lag = around - reach; lag <= around + reach; lag++) {
      if (lag < 0 || lag + from + count > ref.length) continue;
      final v = _dot(ref, out, lag, from, count);
      if (v > bestValue) {
        bestValue = v;
        best = lag;
      }
    }
    return best;
  }

  /// [_refine] to a fraction of a sample: the peak of a parabola through the best lag and its neighbours.
  static double? _refineFraction(Float64List ref, Float64List out, int around, int reach, int from, int count) {
    final lag = _refine(ref, out, around, reach, from, count);
    if (lag == null) return null;
    final a = _dot(ref, out, lag - 1, from, count), b = _dot(ref, out, lag, from, count);
    final c = _dot(ref, out, lag + 1, from, count);
    final bend = a - 2 * b + c;
    return bend >= 0 ? lag.toDouble() : lag + 0.5 * (a - c) / bend;
  }

  /// The frames of the output that the source covers, interpolation and all, at the fit ([start], [slope]).
  static (int, int) _span(double start, double slope, int outFrames, int refFrames) {
    var first = 0, last = outFrames;
    while (first < outFrames && start + (1 + slope) * first - _taps < 0) {
      first++;
    }
    while (last > first && start + (1 + slope) * (last - 1) + _taps + 1 >= refFrames) {
      last--;
    }
    return (first, last);
  }

  /// How far, in samples (rms), the blocks' fits sit off the line.
  static double _spread(List<double> xs, List<double> ys, double a, double b) {
    var sum = 0.0;
    for (var i = 0; i < xs.length; i++) {
      final e = ys[i] - (a + b * xs[i]);
      sum += e * e;
    }
    return math.sqrt(sum / xs.length);
  }

  /// Least squares: y = a + b x.
  static (double, double) _line(List<double> xs, List<double> ys) {
    final n = xs.length;
    var sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0;
    for (var i = 0; i < n; i++) {
      sx += xs[i];
      sy += ys[i];
      sxx += xs[i] * xs[i];
      sxy += xs[i] * ys[i];
    }
    final b = (n * sxy - sx * sy) / (n * sxx - sx * sx);
    return ((sy - b * sx) / n, b);
  }

  static const _taps = 48;

  /// Channel [channel] of interleaved [x] at the fractional frame [at]: a Blackman-windowed sinc.
  static double _sinc(Float64List x, int channels, int channel, double at) {
    final centre = at.floor(), frac = at - centre;
    if (frac == 0) return x[centre * channels + channel];
    var s = 0.0;
    for (var k = -_taps + 1; k <= _taps; k++) {
      final t = k - frac; // distance from [at]
      final w = 0.42 + 0.5 * math.cos(math.pi * t / _taps) + 0.08 * math.cos(2 * math.pi * t / _taps);
      final sinc = math.sin(math.pi * t) / (math.pi * t);
      s += x[(centre + k) * channels + channel] * sinc * w;
    }
    return s;
  }

  /// In-place radix-2 FFT of ([re], [im]); [inverse] scales by 1/n.
  static void _fft(Float64List re, Float64List im, bool inverse) {
    final n = re.length;
    for (var i = 1, j = 0; i < n; i++) {
      var bit = n >> 1;
      for (; j & bit != 0; bit >>= 1) {
        j ^= bit;
      }
      j ^= bit;
      if (i < j) {
        var t = re[i];
        re[i] = re[j];
        re[j] = t;
        t = im[i];
        im[i] = im[j];
        im[j] = t;
      }
    }
    for (var len = 2; len <= n; len <<= 1) {
      final angle = (inverse ? 2 : -2) * math.pi / len;
      final wr = math.cos(angle), wi = math.sin(angle);
      for (var i = 0; i < n; i += len) {
        var cr = 1.0, ci = 0.0;
        for (var j = 0; j < len ~/ 2; j++) {
          final ur = re[i + j], ui = im[i + j];
          final xr = re[i + j + len ~/ 2], xi = im[i + j + len ~/ 2];
          final vr = xr * cr - xi * ci, vi = xr * ci + xi * cr;
          re[i + j] = ur + vr;
          im[i + j] = ui + vi;
          re[i + j + len ~/ 2] = ur - vr;
          im[i + j + len ~/ 2] = ui - vi;
          final next = cr * wr - ci * wi;
          ci = cr * wi + ci * wr;
          cr = next;
        }
      }
    }
    if (inverse) {
      for (var i = 0; i < n; i++) {
        re[i] /= n;
        im[i] /= n;
      }
    }
  }
}

/// IEC 61672 A-weighting at a sample rate: its analogue poles through the bilinear transform, one first-order
/// section each, scaled to 0 dB at 1 kHz.
class _AWeighting {
  _AWeighting(this.rate) {
    final k = 2.0 * rate;
    // s/(s+w) twice at 20.6 Hz, once each at 107.7 and 737.9 Hz; 1/(s+w) twice at 12194 Hz.
    const poles = [20.598997, 20.598997, 107.65265, 737.86223, 12194.217, 12194.217];
    for (var i = 0; i < poles.length; i++) {
      final w = 2 * math.pi * poles[i], d = k + w;
      final highPass = i < 4;
      _b0.add(highPass ? k / d : 1 / d);
      _b1.add(highPass ? -k / d : 1 / d);
      _a1.add((w - k) / d);
    }
    // The response at 1 kHz.
    final omega = 2 * math.pi * 1000 / rate;
    var re = 1.0, im = 0.0;
    for (var i = 0; i < _b0.length; i++) {
      // (b0 + b1 z^-1) / (1 + a1 z^-1), z^-1 = e^{-jω}.
      final c = math.cos(omega), s = -math.sin(omega);
      final nr = _b0[i] + _b1[i] * c, ni = _b1[i] * s;
      final dr = 1 + _a1[i] * c, di = _a1[i] * s;
      final mag = (dr * dr + di * di);
      final hr = (nr * dr + ni * di) / mag, hi = (ni * dr - nr * di) / mag;
      final r = re * hr - im * hi;
      im = re * hi + im * hr;
      re = r;
    }
    _scale = 1 / math.sqrt(re * re + im * im);
  }

  final int rate;
  final _b0 = <double>[], _b1 = <double>[], _a1 = <double>[];
  late final double _scale;

  /// [x] (interleaved, [channels] wide) weighted; the first 50 ms, while the filter settles, are left out.
  Float64List apply(Float64List x, int channels) {
    final frames = x.length ~/ channels, skip = math.min(frames ~/ 4, rate ~/ 20);
    final y = Float64List((frames - skip) * channels);
    for (var c = 0; c < channels; c++) {
      final xPrev = List.filled(_b0.length, 0.0), yPrev = List.filled(_b0.length, 0.0);
      for (var i = 0; i < frames; i++) {
        var v = x[i * channels + c];
        for (var s = 0; s < _b0.length; s++) {
          final out = _b0[s] * v + _b1[s] * xPrev[s] - _a1[s] * yPrev[s];
          xPrev[s] = v;
          yPrev[s] = out;
          v = out;
        }
        if (i >= skip) y[(i - skip) * channels + c] = v * _scale;
      }
    }
    return y;
  }
}

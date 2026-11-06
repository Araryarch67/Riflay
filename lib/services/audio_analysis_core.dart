import 'dart:math' as math;
import 'dart:typed_data';

/// What the spectrum says about where a lossless file came from.
enum SourceVerdict {
  /// Sound up to the top of its band, as a lossless recording has.
  fullBand,

  /// A sharp wall below 20 kHz with nothing above it: how an MP3 or AAC is cut, so a lossless file like this was
  /// most likely made from one.
  lossyCut,

  /// A high-resolution file (88.2 kHz and up) with nothing above 22 kHz: made from a 44.1 / 48 kHz one.
  upsampled,
}

/// One song's measurements: loudness (EBU R128), its dynamic range (the DR Meter's way), its peak and where its
/// spectrum ends.
class AudioReport {
  const AudioReport({
    required this.lufs,
    required this.peakDb,
    required this.dr,
    required this.rate,
    this.cutoffHz,
    this.verdict = SourceVerdict.fullBand,
    this.spectrogram,
    this.columns = 0,
  });

  /// Integrated loudness, LUFS; null for silence.
  final double? lufs;

  /// The highest sample, dBFS.
  final double peakDb;

  /// Dynamic range, DR Meter style (DR14 is very dynamic, DR5 brick-walled); null when too short to tell.
  final int? dr;

  /// The rate it was measured at.
  final int rate;

  /// Where a sharp wall cuts the spectrum off, when there is one.
  final double? cutoffHz;
  final SourceVerdict verdict;

  /// Levels over time, [columns] wide and [AudioAnalyzer.rows] tall, bottom row first: 0 is silence (-120 dB and
  /// below) and 255 the loudest (0 dB). Not saved; measured again when shown.
  final Uint8List? spectrogram;
  final int columns;

  /// ReplayGain 2.0's gain: what brings the song to -18 LUFS.
  double? get gainDb => lufs == null ? null : (-18 - lufs!).clamp(-24.0, 12.0);

  Map<String, Object?> toJson() => {
    'lufs': lufs,
    'peak': peakDb,
    'dr': dr,
    'rate': rate,
    'cutoff': cutoffHz,
    'verdict': verdict.name,
  };

  static AudioReport fromJson(Map<String, dynamic> j) => AudioReport(
    lufs: (j['lufs'] as num?)?.toDouble(),
    peakDb: (j['peak'] as num).toDouble(),
    dr: (j['dr'] as num?)?.toInt(),
    rate: (j['rate'] as num).toInt(),
    cutoffHz: (j['cutoff'] as num?)?.toDouble(),
    verdict: SourceVerdict.values.asNameMap()[j['verdict']] ?? SourceVerdict.fullBand,
  );

  AudioReport withSpectrogram(Uint8List data, int columns) => AudioReport(
    lufs: lufs,
    peakDb: peakDb,
    dr: dr,
    rate: rate,
    cutoffHz: cutoffHz,
    verdict: verdict,
    spectrogram: data,
    columns: columns,
  );
}

/// Measures a song fed to it in pieces ([add]), then [finish]es with its [AudioReport]. Pure Dart, so it runs in an
/// isolate of its own beside the decoder.
class AudioAnalyzer {
  AudioAnalyzer({required this.rate, required this.channels})
    : _kb = _kWeighting(rate),
      _state = List.generate(channels, (_) => Float64List(8)),
      _drSquares = List.generate(channels, (_) => <double>[]),
      _drPeaks = List.generate(channels, (_) => <double>[]),
      _blockSquares = Float64List(channels),
      _blockPeaks = Float64List(channels),
      _fftFrame = Float64List(_fft),
      _power = Float64List(_fft ~/ 2 + 1);

  final int rate;
  final int channels;

  static const rows = 160;
  static const _fft = 4096;

  // ── Loudness: K-weighted energy in 100 ms steps, 400 ms blocks ───────────
  final List<double> _kb; // b0 b1 b2 a1 a2 of the shelf, then of the high pass
  final List<Float64List> _state; // per channel: x1 x2 y1 y2 of each stage
  double _stepEnergy = 0;
  int _stepCount = 0;
  final _steps = <double>[];

  // ── DR: 3 s blocks per channel ──────────────────────────────────────────
  final List<List<double>> _drSquares, _drPeaks;
  final Float64List _blockSquares, _blockPeaks;
  int _blockCount = 0;

  double _peak = 0;

  // ── Spectrum: one 4096-point frame every quarter second ─────────────────
  final Float64List _fftFrame;
  int _fftFill = 0;
  int _ring = 0;
  int _sinceFrame = 0;
  final Float64List _power;
  int _frames = 0;
  final _columns = <Float32List>[];

  /// Interleaved samples, each -1…1.
  void add(Float64List interleaved) {
    final step = rate ~/ 10, drBlock = rate * 3, hop = rate ~/ 4;
    final b0 = _kb[0], b1 = _kb[1], b2 = _kb[2], a1 = _kb[3], a2 = _kb[4];
    final c0 = _kb[5], c1 = _kb[6], c2 = _kb[7], d1 = _kb[8], d2 = _kb[9];
    for (var i = 0; i + channels <= interleaved.length; i += channels) {
      var mono = 0.0, energy = 0.0;
      for (var ch = 0; ch < channels; ch++) {
        final x = interleaved[i + ch];
        mono += x;
        final a = x.abs();
        if (a > _peak) _peak = a;
        if (a > _blockPeaks[ch]) _blockPeaks[ch] = a;
        _blockSquares[ch] += x * x;
        final s = _state[ch];
        final y = b0 * x + b1 * s[0] + b2 * s[1] - a1 * s[2] - a2 * s[3];
        s[1] = s[0];
        s[0] = x;
        s[3] = s[2];
        s[2] = y;
        final z = c0 * y + c1 * s[4] + c2 * s[5] - d1 * s[6] - d2 * s[7];
        s[5] = s[4];
        s[4] = y;
        s[7] = s[6];
        s[6] = z;
        energy += z * z;
      }
      _stepEnergy += energy;
      if (++_stepCount == step) {
        _steps.add(_stepEnergy / step);
        _stepEnergy = 0;
        _stepCount = 0;
      }
      if (++_blockCount == drBlock) _closeDrBlock();
      // The spectrum's frame: the last 4096 samples (a ring), taken every quarter second.
      _fftFrame[_ring] = mono / channels;
      _ring = (_ring + 1) & (_fft - 1);
      if (_fftFill < _fft) _fftFill++;
      if (++_sinceFrame >= hop && _fftFill == _fft) {
        _sinceFrame = 0;
        _spectrumFrame();
      }
    }
  }

  void _closeDrBlock() {
    for (var ch = 0; ch < channels; ch++) {
      _drSquares[ch].add(_blockSquares[ch] / _blockCount);
      _drPeaks[ch].add(_blockPeaks[ch]);
      _blockSquares[ch] = 0;
      _blockPeaks[ch] = 0;
    }
    _blockCount = 0;
  }

  final _re = Float64List(_fft), _im = Float64List(_fft);
  late final _window = Float64List.fromList([
    for (var i = 0; i < _fft; i++) 0.5 - 0.5 * math.cos(2 * math.pi * i / (_fft - 1)),
  ]);

  void _spectrumFrame() {
    for (var i = 0; i < _fft; i++) {
      _re[i] = _fftFrame[(_ring + i) & (_fft - 1)] * _window[i];
      _im[i] = 0;
    }
    _transform(_re, _im);
    // The spectrogram keeps each frame as [rows] bands (the loudest bin of each), not 2049 bins.
    final column = Float32List(rows);
    const bins = _fft ~/ 2;
    for (var k = 0; k <= bins; k++) {
      // Scaled so a full-scale sine reads about 0 dB.
      final p = (_re[k] * _re[k] + _im[k] * _im[k]) / (_fft * _fft / 16);
      _power[k] += p;
      final row = math.min(rows - 1, k * rows ~/ bins);
      if (p > column[row]) column[row] = p;
    }
    _frames++;
    _columns.add(column);
  }

  /// In-place radix-2 FFT.
  static void _transform(Float64List re, Float64List im) {
    final n = re.length;
    for (var i = 1, j = 0; i < n; i++) {
      var bit = n >> 1;
      for (; j & bit != 0; bit >>= 1) {
        j ^= bit;
      }
      j ^= bit;
      if (i < j) {
        final tr = re[i], ti = im[i];
        re[i] = re[j];
        im[i] = im[j];
        re[j] = tr;
        im[j] = ti;
      }
    }
    for (var len = 2; len <= n; len <<= 1) {
      final angle = -2 * math.pi / len;
      final wr = math.cos(angle), wi = math.sin(angle);
      for (var i = 0; i < n; i += len) {
        var cr = 1.0, ci = 0.0;
        for (var k = 0; k < len ~/ 2; k++) {
          final ar = re[i + k + len ~/ 2], ai = im[i + k + len ~/ 2];
          final xr = ar * cr - ai * ci, xi = ar * ci + ai * cr;
          re[i + k + len ~/ 2] = re[i + k] - xr;
          im[i + k + len ~/ 2] = im[i + k] - xi;
          re[i + k] += xr;
          im[i + k] += xi;
          final next = cr * wr - ci * wi;
          ci = cr * wi + ci * wr;
          cr = next;
        }
      }
    }
  }

  AudioReport finish({bool spectrogram = true}) {
    if (_blockCount > rate) _closeDrBlock(); // a last block of more than a second counts
    return AudioReport(
      lufs: _integratedLoudness(),
      peakDb: _db(_peak),
      dr: _dynamicRange(),
      rate: rate,
      cutoffHz: _cutoff().$1,
      verdict: _cutoff().$2,
      spectrogram: spectrogram ? _image() : null,
      columns: spectrogram ? math.min(_columns.length, 600) : 0,
    );
  }

  static double _db(double amplitude) => amplitude <= 0 ? -120 : 20 * math.log(amplitude) / math.ln10;

  /// EBU R128 / ITU-R BS.1770: 400 ms blocks every 100 ms, gated at -70 LUFS, then 10 LU under their mean.
  double? _integratedLoudness() {
    if (_steps.length < 4) return null;
    final blocks = [
      for (var i = 0; i + 4 <= _steps.length; i++) (_steps[i] + _steps[i + 1] + _steps[i + 2] + _steps[i + 3]) / 4,
    ];
    double loudness(double energy) => -0.691 + 10 * math.log(energy) / math.ln10;
    final loud = blocks.where((e) => e > 0 && loudness(e) > -70).toList();
    if (loud.isEmpty) return null;
    final relative = loudness(loud.reduce((a, b) => a + b) / loud.length) - 10;
    final gated = loud.where((e) => loudness(e) > relative).toList();
    if (gated.isEmpty) return null;
    return loudness(gated.reduce((a, b) => a + b) / gated.length);
  }

  /// The DR Meter's measure: per channel, the second-highest block peak over the RMS of the loudest 20% of
  /// 3-second blocks (RMS taken as √2 × the root mean square, so a sine's RMS equals its peak), averaged over
  /// the channels and rounded.
  int? _dynamicRange() {
    final values = <double>[];
    for (var ch = 0; ch < channels; ch++) {
      final squares = _drSquares[ch], peaks = _drPeaks[ch];
      if (squares.isEmpty) return null;
      final rms = [for (final s in squares) math.sqrt(2 * s)]..sort((a, b) => b.compareTo(a));
      final top = rms.take(math.max(1, (rms.length * 0.2).round()));
      final loud = math.sqrt(top.map((r) => r * r).reduce((a, b) => a + b) / top.length);
      final sorted = [...peaks]..sort((a, b) => b.compareTo(a));
      final peak = sorted.length > 1 ? sorted[1] : sorted[0];
      if (loud <= 0 || peak <= 0) continue;
      values.add(20 * math.log(peak / loud) / math.ln10);
    }
    if (values.isEmpty) return null;
    return (values.reduce((a, b) => a + b) / values.length).round();
  }

  int _bin(double hz) => (hz * _fft / rate).round().clamp(0, _fft ~/ 2);

  late final (double?, SourceVerdict) _cut = _findCutoff();
  (double?, SourceVerdict) _cutoff() => _cut;

  /// A wall in the average spectrum: a drop of 25 dB within a kilohertz above 10 kHz, with next to nothing above it
  /// up to the top. Below 20.5 kHz it is a lossy codec's; in a file of 88.2 kHz and up, one below 27 kHz (or nothing
  /// at all above 26.5 kHz) is a 44.1 / 48 kHz recording's top and its resampler's slope. Otherwise the band is full.
  (double?, SourceVerdict) _findCutoff() {
    if (_frames == 0) return (null, SourceVerdict.fullBand);
    final db = Float64List(_power.length);
    for (var k = 0; k < db.length; k++) {
      db[k] = 10 * math.log(_power[k] / _frames + 1e-14) / math.ln10;
    }
    double mean(double from, double to) {
      final a = _bin(from), b = math.max(_bin(to), a + 1);
      var sum = 0.0;
      for (var k = a; k < b; k++) {
        sum += db[k];
      }
      return sum / (b - a);
    }

    final nyquist = rate / 2;
    final reference = mean(1000, 6000);
    double? wall;
    var steepest = 0.0;
    for (var hz = 10000.0; hz <= nyquist - 1200; hz += rate / _fft) {
      final drop = mean(hz - 1000, hz - 300) - mean(hz + 300, hz + 1000);
      if (drop > steepest) {
        steepest = drop;
        wall = hz;
      }
    }
    if (wall != null && steepest >= 25 && mean(wall + 300, nyquist) < reference - 60) {
      if (wall < 20500) return (wall, SourceVerdict.lossyCut);
      // A 44.1 / 48 kHz source's wall, with its resampler's slope up to about 26 kHz: no hi-res recording has one.
      if (rate >= 88200 && wall < 27000) return (wall, SourceVerdict.upsampled);
      return (wall, SourceVerdict.fullBand);
    }
    if (rate >= 88200 && mean(26500, nyquist - 500) < reference - 80) return (22050.0, SourceVerdict.upsampled);
    return (null, SourceVerdict.fullBand);
  }

  /// The spectrogram: up to 600 columns over the song, [rows] tall up to its top frequency, in dB from -120 to 0.
  Uint8List _image() {
    final width = math.min(_columns.length, 600);
    final out = Uint8List(width * rows);
    if (width == 0) return out;
    for (var x = 0; x < width; x++) {
      final from = x * _columns.length ~/ width, to = math.max(from + 1, (x + 1) * _columns.length ~/ width);
      for (var y = 0; y < rows; y++) {
        var p = 0.0;
        for (var c = from; c < to; c++) {
          if (_columns[c][y] > p) p = _columns[c][y];
        }
        final level = 10 * math.log(p + 1e-14) / math.ln10;
        out[y * width + x] = ((level + 120) / 120 * 255).round().clamp(0, 255);
      }
    }
    return out;
  }

  /// BS.1770's K-weighting at [rate]: a high shelf (the head) and a high pass, as libebur128 derives them.
  static List<double> _kWeighting(int rate) {
    var f0 = 1681.974450955533, q = 0.7071752369554196;
    const g = 3.999843853973347;
    var k = math.tan(math.pi * f0 / rate);
    final vh = math.pow(10, g / 20).toDouble(), vb = math.pow(vh, 0.4996667741545416).toDouble();
    var a0 = 1 + k / q + k * k;
    final shelf = [
      (vh + vb * k / q + k * k) / a0,
      2 * (k * k - vh) / a0,
      (vh - vb * k / q + k * k) / a0,
      2 * (k * k - 1) / a0,
      (1 - k / q + k * k) / a0,
    ];
    f0 = 38.13547087602444;
    q = 0.5003270373238773;
    k = math.tan(math.pi * f0 / rate);
    a0 = 1 + k / q + k * k;
    return [...shelf, 1, -2, 1, 2 * (k * k - 1) / a0, (1 - k / q + k * k) / a0];
  }
}

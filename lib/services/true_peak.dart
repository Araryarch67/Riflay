import 'dart:math' as math;

/// ITU-R BS.1770 true peak of one channel: the highest point of the waveform a DAC rebuilds, which can sit
/// between two samples and so above the highest sample. Found by 4× oversampling (a 12-tap windowed-sinc per
/// new phase) and taking the largest |value|. Fed in pieces, so a song never has to sit in memory.
class TruePeakMeter {
  static const _taps = 12, _phases = 4;

  // Hann-windowed sinc for phases 1…3 of 4; phase 0 is the sample itself. Tap k reads the sample k-5 steps from
  // the one just before the new point.
  static final List<List<double>> _kernel = [
    for (var p = 1; p < _phases; p++)
      [
        for (var k = 0; k < _taps; k++)
          _sinc(k - 5 - p / _phases) * (0.5 + 0.5 * math.cos(math.pi * (k - 5 - p / _phases) / 6)),
      ],
  ];

  static double _sinc(double x) => x == 0 ? 1 : math.sin(math.pi * x) / (math.pi * x);

  final _history = List<double>.filled(_taps, 0); // oldest first
  double _peak = 0;

  /// The highest |value| seen so far, linear (1.0 is full scale).
  double get peak => _peak;

  void add(double x) {
    for (var i = 0; i < _taps - 1; i++) {
      _history[i] = _history[i + 1];
    }
    _history[_taps - 1] = x;
    final a = x.abs();
    if (a > _peak) _peak = a;
    // The three points between the two middle samples.
    for (final k in _kernel) {
      var y = 0.0;
      for (var i = 0; i < _taps; i++) {
        y += k[i] * _history[i];
      }
      if (y.abs() > _peak) _peak = y.abs();
    }
  }
}

/// [samples]' true peak in dBTP (-120 for silence).
double truePeakDb(Iterable<double> samples) {
  final m = TruePeakMeter();
  samples.forEach(m.add);
  return m.peak <= 1e-6 ? -120 : 20 * math.log(m.peak) / math.ln10;
}

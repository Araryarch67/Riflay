import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/platform/web_effects.dart';
import 'package:riflay/services/audio_engine.dart';
import 'package:riflay/services/visualizer_levels.dart';
import 'package:riflay/services/visualizer_spectrum.dart';

/// The web build's effects and visualizer (lib/platform/web_effects.dart), and how AudioEngine's settings map onto
/// them: the same settings must mean the same thing as mpv's filter chain.
void main() {
  group('visualizer bands from FFT bins', () {
    test('edges sit half the width either side of each centre', () {
      final edges = bandEdges([1000], 1);
      expect(edges.single.$1, closeTo(1000 / math.sqrt2, 1e-9));
      expect(edges.single.$2, closeTo(1000 * math.sqrt2, 1e-9));
    });

    test('a band sums the power of its bins', () {
      // 10 Hz bins; 100-120 Hz holds bins 10, 11 and 12, each -30 dB: three times the power is +4.77 dB.
      final bins = List<double>.filled(100, -120)..fillRange(10, 13, -30);
      expect(bandLevel(bins, 10, 100, 120), closeTo(-30 + 10 * math.log(3) / math.ln10, 1e-9));
    });

    test('a band narrower than a bin reads the nearest one', () {
      final bins = List<double>.filled(100, -120)..[42] = -12;
      expect(bandLevel(bins, 10, 419, 421), closeTo(-12, 1e-9));
    });

    test('silence is minus infinity, which the visualizer shows as nothing', () {
      final bins = List<double>.filled(64, double.negativeInfinity);
      final db = bandLevel(bins, 10, 100, 200);
      expect(db, double.negativeInfinity);
      expect(VisualizerLevels.amplitudeOfDb(db), 0);
      expect(VisualizerLevels.amplitudeOfDb(-30), closeTo(0.5, 1e-9));
    });

    test('the bands cover what mpv\'s filter bank does', () {
      final edges = bandEdges([
        for (var i = 0; i < VisualizerSpectrum.bands; i++) VisualizerSpectrum.frequency(i, 48000),
      ], 0.55);
      expect(edges, hasLength(VisualizerSpectrum.bands));
      expect(edges.first.$1, lessThan(35));
      expect(edges.last.$2, greaterThan(16000));
    });
  });

  group('AudioEngine settings as Web Audio effects', () {
    test('nothing on: nothing changes', () {
      final fx = AudioEngine().webEffectsNow;
      expect(fx.eq, isEmpty);
      expect(fx.preamp, 0);
      expect(fx.crossfeed, 0);
      expect(fx.mono, isNull);
    });

    test('the equalizer sends its audible bands and the headroom mpv would use', () {
      final a = AudioEngine()
        ..eqEnabled = true
        ..bands = const [EqBand(32, 6), EqBand(1000, 0), EqBand(16000, -3, q: 2)];
      final fx = a.webEffectsNow;
      expect(fx.eq.map((b) => b.frequency), [32, 16000]);
      expect(fx.eq.last.q, 2);
      expect(fx.preamp, a.preamp);
      expect(fx.preamp, lessThan(0));
    });

    test('mono wins over crossfeed, as in the filter chain', () {
      final a = AudioEngine()
        ..crossfeed = 0.5
        ..mono = MonoAudio.left;
      expect(a.webEffectsNow.mono, WebMono.left);
      expect(a.webEffectsNow.crossfeed, 0);
      a.mono = MonoAudio.off;
      expect(a.webEffectsNow.mono, isNull);
      expect(a.webEffectsNow.crossfeed, 0.5);
    });

    test('crossfeed strength and range follow FFmpeg\'s', () {
      expect(const WebEffects().crossfeedGain, 0);
      expect(const WebEffects(crossfeed: 1).crossfeedGain, closeTo(0.35, 1e-9));
      expect(const WebEffects(crossfeedRange: 0.5).crossfeedCutoff, 1550);
      expect(const WebEffects(crossfeedRange: 1).crossfeedCutoff, 2100);
    });
  });
}

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'web_effects.dart';

/// `--dart-define=RIFLAY_NO_WEB_AUDIO=true`: songs play straight from their `<audio>` element, with no effects and
/// no visualizer, to tell whether a playback problem is this graph's.
const _off = bool.fromEnvironment('RIFLAY_NO_WEB_AUDIO');

/// The browser: every `<audio>` element just_audio plays (the song, and the crossfade's second player) is routed
/// into one Web Audio graph the first time it plays:
///
///     element → preamp → equalizer → stereo stage (crossfeed or mono) → output → speakers
///                                                                          ↘ analyser (visualizer)
///
/// just_audio keeps its element to itself, so `HTMLMediaElement.prototype.play` is wrapped to meet it. Once routed
/// an element sounds only through the graph, which hears nothing from a cross-origin stream without CORS: only
/// same-origin, `blob:` and `data:` sources and elements with `crossOrigin` set (the proxy answers CORS) are
/// routed. See `web_audio.dart`.
abstract final class WebAudio {
  static final bool available = !_off && globalContext.has('AudioContext');

  static web.AudioContext? _context;
  static web.GainNode? _preamp;
  static web.GainNode? _stereoIn;
  static web.GainNode? _output;
  static web.AnalyserNode? _analyser;
  static var _eq = <web.BiquadFilterNode>[];
  static var _stereo = <web.AudioNode>[];
  static var _effects = const WebEffects();
  static bool _installed = false;
  static final _routed = <web.HTMLMediaElement>[];

  static JSFloat32Array? _bins;

  static double get sampleRate => _context?.sampleRate ?? 48000;

  /// Wraps `play` so each element is routed as it starts. Once, before anything plays.
  static void install() {
    if (!available || _installed) return;
    _installed = true;
    try {
      final prototype = (globalContext['HTMLMediaElement'] as JSObject)['prototype'] as JSObject;
      final play = prototype['play'] as JSFunction;
      prototype['play'] = ((web.HTMLMediaElement self) {
        _route(self);
        return play.callAsFunction(self);
      }).toJSCaptureThis;
    } catch (e) {
      debugPrint('Web Audio unavailable: $e');
    }
  }

  static void _route(web.HTMLMediaElement element) {
    try {
      if (element.tagName.toUpperCase() != 'AUDIO') return;
      final context = _graph();
      // Started by a click, so the browser lets the graph start too.
      if (context.state == 'suspended') context.resume();
      if (_routed.contains(element) || !_readable(element)) return;
      context.createMediaElementSource(element).connect(_preamp!);
      _routed.add(element);
    } catch (e) {
      debugPrint('Routing a song through Web Audio failed: $e');
    }
  }

  /// Whether the graph would hear [element]'s samples (see the class comment).
  static bool _readable(web.HTMLMediaElement element) {
    if (element.crossOrigin != null) return true;
    final src = element.currentSrc.isNotEmpty ? element.currentSrc : element.src;
    if (src.startsWith('blob:') || src.startsWith('data:')) return true;
    final uri = Uri.tryParse(src);
    return uri != null && uri.hasScheme && uri.origin == web.window.location.origin;
  }

  static web.AudioContext _graph() {
    if (_context case final c?) return c;
    final c = web.AudioContext();
    _preamp = c.createGain();
    _stereoIn = c.createGain();
    _output = c.createGain();
    _analyser = c.createAnalyser()
      ..fftSize = 4096
      ..smoothingTimeConstant = 0.55;
    _bins = Float32List(_analyser!.frequencyBinCount).toJS;
    _output!
      ..connect(c.destination)
      ..connect(_analyser!);
    _context = c;
    _build(_effects);
    return c;
  }

  /// Applies [effects]; slider moves only change the filters' values, other changes rebuild the stage they touch.
  static void apply(WebEffects effects) {
    if (!available) return;
    final before = _effects;
    _effects = effects;
    final c = _context;
    if (c == null) return; // nothing played yet: built with these when something does
    try {
      _preamp!.gain.value = _gain(effects.preamp);
      final sameBands =
          before.eq.length == effects.eq.length &&
          _eq.length == effects.eq.length &&
          [for (var i = 0; i < effects.eq.length; i++) i]
              .every((i) => before.eq[i].frequency == effects.eq[i].frequency && before.eq[i].q == effects.eq[i].q);
      if (sameBands) {
        for (var i = 0; i < _eq.length; i++) {
          _eq[i].gain.value = effects.eq[i].gain;
        }
      } else {
        _buildEq(c, effects);
      }
      final sameStereo =
          before.mono == effects.mono &&
          (before.crossfeed > 0) == (effects.crossfeed > 0) &&
          _stereo.isNotEmpty == (effects.mono != null || effects.crossfeed > 0);
      if (sameStereo && effects.crossfeed > 0 && effects.mono == null) {
        _tuneCrossfeed(effects);
      } else if (!sameStereo) {
        _buildStereo(c, effects);
      }
    } catch (e) {
      debugPrint('Applying Web Audio effects failed: $e');
    }
  }

  static void _build(WebEffects effects) {
    final c = _context!;
    _preamp!.gain.value = _gain(effects.preamp);
    _buildEq(c, effects);
    _buildStereo(c, effects);
  }

  static void _buildEq(web.AudioContext c, WebEffects effects) {
    _preamp!.disconnect();
    for (final f in _eq) {
      f.disconnect();
    }
    _eq = [
      for (final b in effects.eq)
        c.createBiquadFilter()
          ..type = 'peaking'
          ..frequency.value = b.frequency
          ..Q.value = b.q
          ..gain.value = b.gain,
    ];
    web.AudioNode last = _preamp!;
    for (final f in _eq) {
      last.connect(f);
      last = f;
    }
    last.connect(_stereoIn!);
  }

  static void _buildStereo(web.AudioContext c, WebEffects effects) {
    _stereoIn!.disconnect();
    for (final n in _stereo) {
      n.disconnect();
    }
    _stereo = [];
    final mono = effects.mono;
    if (mono != null) {
      // One channel, mixed down the speakers' way ((L + R) / 2), then sent to one side or both.
      final down = c.createGain()
        ..channelCount = 1
        ..channelCountMode = 'explicit'
        ..channelInterpretation = 'speakers';
      _stereoIn!.connect(down);
      _stereo.add(down);
      if (mono == WebMono.both) {
        down.connect(_output!);
      } else {
        final merger = c.createChannelMerger(2);
        down.connect(merger, 0, mono == WebMono.left ? 0 : 1);
        merger.connect(_output!);
        _stereo.add(merger);
      }
    } else if (effects.crossfeed > 0) {
      // Each ear also hears the other side's low end, a little later and quieter, as from speakers in a room.
      final split = c.createChannelSplitter(2);
      final merge = c.createChannelMerger(2);
      _stereoIn!.connect(split);
      final direct = [c.createGain(), c.createGain()];
      final cross = [c.createGain(), c.createGain()];
      final lowpass = [
        for (var i = 0; i < 2; i++)
          c.createBiquadFilter()
            ..type = 'lowpass'
            ..Q.value = 0.5,
      ];
      final delay = [c.createDelay(0.01), c.createDelay(0.01)];
      for (var side = 0; side < 2; side++) {
        delay[side].delayTime.value = 0.0003;
        split.connect(direct[side], side);
        direct[side].connect(merge, 0, side);
        split.connect(lowpass[side], side);
        lowpass[side].connect(delay[side]);
        delay[side].connect(cross[side]);
        cross[side].connect(merge, 0, 1 - side);
      }
      merge.connect(_output!);
      _stereo = [split, merge, ...direct, ...cross, ...lowpass, ...delay];
      _crossfeed = (direct: direct, cross: cross, lowpass: lowpass);
      _tuneCrossfeed(effects);
    } else {
      _stereoIn!.connect(_output!);
    }
  }

  static ({List<web.GainNode> direct, List<web.GainNode> cross, List<web.BiquadFilterNode> lowpass})? _crossfeed;

  static void _tuneCrossfeed(WebEffects effects) {
    final nodes = _crossfeed;
    if (nodes == null) return;
    final g = effects.crossfeedGain;
    for (var side = 0; side < 2; side++) {
      // Lowered as much as the other side adds at its loudest, so the sum can't clip.
      nodes.direct[side].gain.value = 1 / (1 + g);
      nodes.cross[side].gain.value = g / (1 + g);
      nodes.lowpass[side].frequency.value = effects.crossfeedCutoff;
    }
  }

  static double _gain(double db) => math.pow(10, db / 20).toDouble();

  /// The level, in dB, of the sound leaving the graph between each pair of [edges] (Hz), into [levels]; false when
  /// nothing has been routed yet.
  static bool readBands(List<(double, double)> edges, Float64List levels) {
    final analyser = _analyser, bins = _bins;
    if (analyser == null || bins == null || _routed.isEmpty) return false;
    analyser.getFloatFrequencyData(bins);
    final data = bins.toDart;
    final binHz = sampleRate / analyser.fftSize;
    for (var i = 0; i < edges.length && i < levels.length; i++) {
      levels[i] = bandLevel(data, binHz, edges[i].$1, edges[i].$2);
    }
    return true;
  }
}

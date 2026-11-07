import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/audio_engine.dart';
import '../../services/layout_prefs.dart';
import '../../services/player_controller.dart';
import '../../services/ui_beat.dart';
import '../../services/visualizer_levels.dart';
import 'playing_motion.dart';
import '../../services/language.dart';

/// Why the visualizer can't be on at all right now, in words for its switch; null when it can.
/// These are settings of their own: the switch is greyed out until they change.
String? visualizerBlockedBy(PlayerController c, {bool reduceMotion = false}) {
  if (c.audio.bitPerfect) return tr.vizOffBitPerfect;
  if (LayoutPrefs.lightweight) return tr.vizOffLightweight;
  if (!LayoutPrefs.moves || reduceMotion) return tr.vizOffReducedMotion;
  return null;
}

/// Why the visualizer is on but hidden for the song playing now; null when it shows.
String? visualizerHiddenBy(PlayerController c) {
  if (c.audio.dopPlaying != null) return tr.vizHiddenDop;
  if (c.casting) return tr.vizHiddenCasting;
  return null;
}

/// Shares one audio analysis stream between player decorations. No microphone,
/// extra network requests, or player is needed for reactive visuals.
class AudioReactiveView extends StatefulWidget {
  const AudioReactiveView({super.key, required this.builder, this.enabled = true, this.maxFps});
  final Widget Function(BuildContext, VisualizerLevels) builder;
  final bool enabled;

  /// Caps how often the smoothed levels (and so the painters listening to them) update, for
  /// slow decorations that gain nothing from the display's full refresh rate. Unset, views
  /// update at most 20 times a second in Balanced (the levels themselves arrive 25 times a
  /// second, and 20 shares its frames with the seek bar's wave and the cover's flower) and 60 in
  /// Heavy: following a 144-240 Hz display would cost several times the CPU for motion the eye
  /// can't tell apart.
  final double? maxFps;
  @override
  State<AudioReactiveView> createState() => _AudioReactiveViewState();
}

class _AudioReactiveViewState extends State<AudioReactiveView> with WidgetsBindingObserver {
  PlayerController? _controller;
  StreamSubscription<dynamic>? _playState;
  StreamSubscription<dynamic>? _song;
  VoidCallback? _release;
  bool _visible = true;
  bool _foreground = true;
  bool _attached = true;
  bool _reduceMotion = false;
  final _levels = VisualizerLevels();
  // The shared UI beat, not a ticker: a ticker wakes the app on every vsync (240 times a
  // second on a 240 Hz screen) even when it skips most of them, and a timer of its own
  // would land its frames between the seek bar's.
  UiBeatListener? _beat;

  double get _cap => math.min(widget.maxFps ?? 60, LayoutPrefs.heavy ? 60 : 20);

  bool get _running => _beat != null;

  void _start() {
    if (_running) return;
    _beat = UiBeat.listen(Duration(microseconds: (1000000 / _cap).round()), (elapsed) {
      if (!_levels.follow(_controller!.audio.visualizerLevels, elapsed)) _halt();
    });
  }

  void _halt() {
    _beat?.cancel();
    _beat = null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // While the window can be seen, focused or behind another app (people watch it beside their work); minimized
    // or hidden, the meter is let go and mpv drops its filter bank too.
    _foreground = PlayingMotion.visible(WidgetsBinding.instance.lifecycleState);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = PlayerScope.identity(context);
    if (!identical(c, _controller)) {
      _stop();
      _playState?.cancel();
      _song?.cancel();
      _controller?.audio.removeListener(_sync);
      _controller?.audio.visualizerLevels.removeListener(_animate);
      _controller = c;
      _playState = c.player.playerStateStream.listen((_) => _sync());
      _song = c.player.currentIndexStream.distinct().listen((_) => c.audio.visualizerLevels.clear());
      c.audio.addListener(_sync);
      c.audio.visualizerLevels.addListener(_animate);
    }
    _visible = TickerMode.valuesOf(context).enabled;
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _sync();
  }

  void _animate() {
    if (!_attached || _release == null) return;
    if (_controller!.audio.visualizerLevels.value.every((v) => v == 0)) {
      _halt();
      // Silence comes in 25 times a second: clearing what is already clear repainted the view each time.
      if (_levels.value.any((v) => v != 0)) _levels.clear();
    } else {
      _start();
    }
  }

  @override
  void deactivate() {
    _attached = false;
    _stop();
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _attached = true;
    // Dependencies are refreshed before the next build.
  }

  void _stop() {
    final release = _release;
    _release = null;
    release?.call();
    _halt();
    _levels.clear();
  }

  @override
  void didUpdateWidget(AudioReactiveView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _beat?.period = Duration(microseconds: (1000000 / _cap).round());
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = PlayingMotion.visible(state);
    _sync();
  }

  void _sync() {
    final c = _controller;
    if (c == null || !_attached) return;
    final active =
        widget.enabled &&
        LayoutPrefs.instance.visualizerEnabled &&
        !LayoutPrefs.lightweight &&
        LayoutPrefs.moves &&
        !_reduceMotion &&
        _visible &&
        _foreground &&
        c.showsPlaying &&
        !c.casting &&
        !c.audio.bitPerfect &&
        c.audio.dopPlaying == null &&
        (AudioEngine.supported || AudioEngine.webEffects);
    if (active) {
      _release ??= c.audio.watchVisualizer();
      _animate();
    } else {
      _stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.audio.removeListener(_sync);
    _controller?.audio.visualizerLevels.removeListener(_animate);
    _playState?.cancel();
    _song?.cancel();
    _release?.call();
    _halt();
    _levels.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _levels);
}

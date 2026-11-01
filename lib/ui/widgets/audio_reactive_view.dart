import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../services/audio_engine.dart';
import '../../services/layout_prefs.dart';
import '../../services/player_controller.dart';
import '../../services/video_mode.dart';
import '../../services/visualizer_levels.dart';

/// Shares one audio analysis stream between player decorations. No microphone,
/// extra network requests, or player is needed for reactive visuals.
class AudioReactiveView extends StatefulWidget {
  const AudioReactiveView({super.key, required this.builder, this.enabled = true});
  final Widget Function(BuildContext, VisualizerLevels) builder;
  final bool enabled;
  @override
  State<AudioReactiveView> createState() => _AudioReactiveViewState();
}

class _AudioReactiveViewState extends State<AudioReactiveView>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  PlayerController? _controller;
  StreamSubscription<dynamic>? _playState;
  StreamSubscription<dynamic>? _song;
  VoidCallback? _release;
  bool _visible = true;
  bool _foreground = true;
  bool _attached = true;
  bool _reduceMotion = false;
  final _levels = VisualizerLevels();
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      final delta = elapsed - _lastTick;
      _lastTick = elapsed;
      if (!_levels.follow(_controller!.audio.visualizerLevels, delta)) {
        _ticker.stop();
      }
    });
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed ||
            WidgetsBinding.instance.lifecycleState == AppLifecycleState.inactive);
    VideoMode.instance.addListener(_sync);
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
      _ticker.stop();
      _levels.clear();
    } else if (!_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
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
    _ticker.stop();
    _levels.clear();
  }

  @override
  void didUpdateWidget(AudioReactiveView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed || state == AppLifecycleState.inactive;
    _sync();
  }

  void _sync() {
    final c = _controller;
    if (c == null || !_attached) return;
    final active =
        widget.enabled &&
        LayoutPrefs.moves &&
        !_reduceMotion &&
        _visible &&
        _foreground &&
        c.showsPlaying &&
        !c.casting &&
        !c.audio.bitPerfect &&
        c.audio.dopPlaying == null &&
        !VideoMode.instance.on &&
        AudioEngine.supported;
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
    VideoMode.instance.removeListener(_sync);
    _controller?.audio.removeListener(_sync);
    _controller?.audio.visualizerLevels.removeListener(_animate);
    _playState?.cancel();
    _song?.cancel();
    _release?.call();
    _ticker.dispose();
    _levels.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _levels);
}

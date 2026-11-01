import 'dart:async';

import 'package:flutter/material.dart';

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

class _AudioReactiveViewState extends State<AudioReactiveView> with WidgetsBindingObserver {
  PlayerController? _controller;
  StreamSubscription<dynamic>? _playState;
  StreamSubscription<dynamic>? _song;
  VoidCallback? _release;
  bool _visible = true;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
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
      _release?.call();
      _release = null;
      _playState?.cancel();
      _song?.cancel();
      _controller?.audio.removeListener(_sync);
      _controller = c;
      _playState = c.player.playerStateStream.listen((_) => _sync());
      _song = c.player.currentIndexStream.distinct().listen((_) => c.audio.visualizerLevels.clear());
      c.audio.addListener(_sync);
    }
    _visible = TickerMode.valuesOf(context).enabled;
    _sync();
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
    if (c == null) return;
    final active =
        widget.enabled &&
        LayoutPrefs.moves &&
        !MediaQuery.disableAnimationsOf(context) &&
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
    } else {
      _release?.call();
      _release = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    VideoMode.instance.removeListener(_sync);
    _controller?.audio.removeListener(_sync);
    _playState?.cancel();
    _song?.cancel();
    _release?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _controller!.audio.visualizerLevels);
}

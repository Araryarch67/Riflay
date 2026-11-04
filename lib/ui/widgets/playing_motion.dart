import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../services/layout_prefs.dart';
import '../../services/player_controller.dart';
import '../../services/ui_beat.dart';

/// Slow motion for a decoration that moves while a song plays: the seek bar's wave and the
/// cover's flower. Painters listen to it and read [time] and [eased].
class MotionClock extends ChangeNotifier {
  MotionClock({bool moving = false}) : _amount = moving ? 1 : 0, _target = moving ? 1 : 0;

  /// How long motion takes to fade in or out.
  static const _fade = 0.6;

  double _time = 0;
  double _amount;
  double _target;

  /// Seconds of motion so far. It stands still while [amount] is 0, so a pause keeps the shape.
  double get time => _time;

  /// 0 at rest, 1 at full motion, moving linearly towards what is wanted.
  double get amount => _amount;

  /// [amount] with soft ends: a pause flattens and a start grows back without a jolt.
  double get eased => Curves.easeInOut.transform(_amount);

  bool get settled => _amount == _target;

  set moving(bool v) => _target = v ? 1 : 0;

  /// Moves on by [elapsed] (the time since the last beat). Time runs slower as motion fades.
  void advance(Duration elapsed) {
    // A stalled app (a dragged window) returns with one big step: don't jump.
    final dt = (elapsed.inMicroseconds / 1e6).clamp(0.0, 0.1);
    final step = dt / _fade;
    _amount = _target > _amount ? (_amount + step).clamp(0.0, _target) : (_amount - step).clamp(_target, 1.0);
    _time += dt * _amount;
    notifyListeners();
  }
}

/// Hands [builder] a [MotionClock] that runs while the song plays, or null when nothing should
/// move: Lightweight, reduced motion, no player, or this part of the app isn't the page in view.
///
/// The clock rides the shared [UiBeat] (a ticker would wake the app on every vsync) at 60 fps in
/// Heavy and 30 fps otherwise, and only while it's needed: playing, on screen, app in front, or
/// easing out after a pause. The widget around it is not rebuilt for a beat; painters listening
/// to the clock repaint themselves.
class PlayingMotion extends StatefulWidget {
  const PlayingMotion({super.key, required this.builder});

  final Widget Function(BuildContext context, MotionClock? clock) builder;

  @override
  State<PlayingMotion> createState() => _PlayingMotionState();
}

class _PlayingMotionState extends State<PlayingMotion> with WidgetsBindingObserver {
  final _clock = MotionClock();
  PlayerController? _controller;
  UiBeatListener? _beat;
  bool _visible = true;
  bool _foreground = true;
  bool _reduceMotion = false;
  bool _allowed = false;

  /// 33 ms: Balanced draws 30 times a second, and the beat rounds to whole 60 Hz steps.
  static const _slow = Duration(microseconds: 33333);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    LayoutPrefs.instance.addListener(_sync);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed || state == AppLifecycleState.inactive;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = context.getInheritedWidgetOfExactType<PlayerScope>() == null ? null : PlayerScope.identity(context);
    if (!identical(c, _controller)) {
      _controller?.removeListener(_sync);
      _controller = c?..addListener(_sync);
    }
    _visible = TickerMode.valuesOf(context).enabled;
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _sync(first: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed || state == AppLifecycleState.inactive;
    _sync();
  }

  void _sync({bool first = false}) {
    if (!mounted) return;
    final allowed = _controller != null && !LayoutPrefs.lightweight && LayoutPrefs.moves && !_reduceMotion;
    final playing = allowed && _visible && _foreground && _controller!.showsPlaying;
    if (first && !_allowed) _clock._amount = _clock._target = playing ? 1 : 0;
    _clock.moving = playing;
    if (!_clock.settled || playing) {
      _beat ??= UiBeat.listen(_every, _tick);
      _beat!.period = _every;
    } else {
      _halt();
    }
    if (allowed != _allowed) setState(() => _allowed = allowed);
  }

  Duration get _every => LayoutPrefs.heavy ? UiBeat.period : _slow;

  void _tick(Duration elapsed) {
    _clock.advance(elapsed);
    if (_clock.settled && _clock.amount == 0) _halt();
  }

  void _halt() {
    _beat?.cancel();
    _beat = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    LayoutPrefs.instance.removeListener(_sync);
    _controller?.removeListener(_sync);
    _halt();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _allowed ? _clock : null);
}

/// Repaints the nearest repaint boundary when [listenable] changes, without rebuilding or
/// re-laying out [child]: for a painter that lives inside a widget that offers no `repaint`.
class RepaintOn extends SingleChildRenderObjectWidget {
  const RepaintOn({super.key, required this.listenable, super.child});

  final Listenable? listenable;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderRepaintOn(listenable);

  @override
  void updateRenderObject(BuildContext context, covariant RenderObject renderObject) =>
      (renderObject as _RenderRepaintOn).listenable = listenable;
}

class _RenderRepaintOn extends RenderProxyBox {
  _RenderRepaintOn(this._listenable);

  Listenable? _listenable;

  set listenable(Listenable? v) {
    if (identical(v, _listenable)) return;
    if (attached) _listenable?.removeListener(markNeedsPaint);
    _listenable = v;
    if (attached) v?.addListener(markNeedsPaint);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _listenable?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _listenable?.removeListener(markNeedsPaint);
    super.detach();
  }
}

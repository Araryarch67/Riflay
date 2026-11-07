import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The music video's own window on Windows (`runner/video_window.cpp`), which mpv draws into.
abstract final class NativeVideoWindow {
  static const _channel = MethodChannel('riflay/video_window');

  static int? _window;

  /// The window mpv is handed (made the first time, hidden until a [NativeVideoSurface] places it).
  static Future<int> ensure() async => _window ??= (await _channel.invokeMethod<int>('ensure'))!;

  /// Whether the box now showing the video wants it to cover the box (cropped), not fit inside it.
  static final cover = ValueNotifier(false);

  /// The colour the box's foot fades into, as Flutter drew over the video before; null for none.
  static final fade = ValueNotifier<Color?>(null);

  static List<int>? _placed;

  /// Shows the video's [full] box cut to [clip] (physical pixels from the window's top left); null hides it.
  static void _place(Rect? clip, Rect full) {
    final r = clip == null || clip.isEmpty
        ? const <int>[0, 0, 0, 0, 0, 0, 0, 0]
        : [
            clip.left.round(),
            clip.top.round(),
            clip.right.round(),
            clip.bottom.round(),
            full.left.round(),
            full.top.round(),
            full.right.round(),
            full.bottom.round(),
          ];
    if (_placed != null && listEquals(_placed!, r)) return;
    _placed = r;
    if (_window == null) return;
    _channel.invokeMethod<void>('place', r).ignore();
  }

  static bool listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Where the video goes: the native window is kept over this box after every frame that moves it (a scroll, a
/// resize, the panel opening), cut to the scroll view it sits in, and hidden while a menu or dialog is on top
/// (Flutter can't draw over another window). [child] is what shows when the window is hidden (the cover).
///
/// The newest one on screen gets the video; Video mode has one player.
class NativeVideoSurface extends StatefulWidget {
  const NativeVideoSurface({super.key, required this.child, this.cover = false, this.fade});

  final Widget child;

  /// Fills the box, cropping what overflows (as [BoxFit.cover]); otherwise the whole picture fits inside it.
  final bool cover;

  /// The picture's foot fades into this colour (the panel under it), and its top is shaded a little:
  /// drawn by mpv on the graphics card, since nothing Flutter draws can lie over the video's window.
  final Color? fade;

  @override
  State<NativeVideoSurface> createState() => _NativeVideoSurfaceState();
}

class _NativeVideoSurfaceState extends State<NativeVideoSurface> {
  static final _surfaces = <_NativeVideoSurfaceState>[];
  static bool _watching = false;

  /// After every frame (none while nothing changes): where the newest showing surface is now.
  static void _afterFrame(Duration _) {
    for (final s in _surfaces.reversed) {
      final rects = s._rects();
      if (rects != null) {
        NativeVideoWindow.cover.value = s.widget.cover;
        NativeVideoWindow.fade.value = s.widget.fade;
        return NativeVideoWindow._place(rects.clip, rects.full);
      }
    }
    NativeVideoWindow._place(null, Rect.zero);
  }

  ({Rect clip, Rect full})? _rects() {
    if (!mounted) return null;
    if (!TickerMode.valuesOf(context).enabled) return null;
    if (ModalRoute.of(context)?.isCurrent == false) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final ratio = View.of(context).devicePixelRatio;
    final full = MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size);
    var clip = full;
    final Object? viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport is RenderBox && viewport.hasSize) {
      clip = clip.intersect(MatrixUtils.transformRect(viewport.getTransformTo(null), Offset.zero & viewport.size));
    }
    final window = Offset.zero & View.of(context).physicalSize / ratio;
    clip = clip.intersect(window);
    if (clip.width < 1 || clip.height < 1) return null;
    Rect px(Rect r) => Rect.fromLTRB(r.left * ratio, r.top * ratio, r.right * ratio, r.bottom * ratio);
    // Whole pixels, the clip inside the box.
    final f = px(full), c = px(clip);
    return (
      clip: Rect.fromLTRB(
        math.max(c.left, f.left).roundToDouble(),
        math.max(c.top, f.top).roundToDouble(),
        math.min(c.right, f.right).roundToDouble(),
        math.min(c.bottom, f.bottom).roundToDouble(),
      ),
      full: Rect.fromLTRB(
        f.left.roundToDouble(),
        f.top.roundToDouble(),
        f.right.roundToDouble(),
        f.bottom.roundToDouble(),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _surfaces.add(this);
    if (!_watching) {
      _watching = true;
      SchedulerBinding.instance.addPersistentFrameCallback(_afterFrame);
    }
    // The window comes over this box after the first frame it is laid out in.
    SchedulerBinding.instance.scheduleFrame();
  }

  @override
  void dispose() {
    _surfaces.remove(this);
    // Gone (a page closed, the song changed): the next frame hides or moves the window.
    SchedulerBinding.instance.scheduleFrame();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

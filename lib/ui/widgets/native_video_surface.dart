import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../platform/host.dart';
import 'over_video.dart';

/// A Windows child window or Linux GTK surface that mpv draws into independently of Flutter.
abstract final class NativeVideoWindow {
  static const _channel = MethodChannel('riflay/video_window');

  static int? _window;

  /// The window mpv is handed (made the first time, hidden until a [NativeVideoSurface] places it).
  static Future<int> ensure() async {
    // A detached renderer hides its surface. The next player must place it
    // again even if its box has exactly the same coordinates.
    _placed = null;
    return _window ??= (await _channel.invokeMethod<int>('ensure'))!;
  }

  /// Windows: the video's window lies under the Flutter view, which leaves the video's box clear, so whatever the
  /// app draws over the box (a menu, a sheet, a dialog, its barrier) lies over the playing video. Linux's GTK
  /// surface stays over the view and makes room for them instead ([OverVideo]).
  static bool get behind => Host.isWindows;

  /// Whether the box now showing the video wants it to cover the box (cropped), not fit inside it.
  static final cover = ValueNotifier(false);

  /// The colour the box's foot fades into; null for none.
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
    if (_window == null) return;
    _placed = r;
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

/// Where the video goes: the native window is kept on this box after every frame that moves it (a scroll, a
/// resize, the panel opening) and cut to the scroll view it sits in. Windows: it lies under the Flutter view and
/// the box goes clear, so menus and dialogs draw over the playing video. Linux: it lies over the view and makes
/// room for them ([OverVideo]). [child] is what shows when the window is hidden (the cover).
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
    _NativeVideoSurfaceState? showing;
    for (final s in _surfaces.reversed) {
      final rects = s._rects();
      if (rects != null) {
        NativeVideoWindow.cover.value = s.widget.cover;
        NativeVideoWindow.fade.value = s.widget.fade;
        NativeVideoWindow._place(rects.clip, rects.full);
        showing = s;
        break;
      }
    }
    if (showing == null) NativeVideoWindow._place(null, Rect.zero);
    // The box with the video under it goes clear (its cover drawn again once the video leaves it), from the next
    // frame: this one is already painted.
    if (!NativeVideoWindow.behind) return;
    for (final s in _surfaces) {
      final on = identical(s, showing);
      if (s._clear.value != on) SchedulerBinding.instance.addPostFrameCallback((_) => s._clear.value = on);
    }
  }

  /// Whether this box is clear, the video showing through it.
  final _clear = ValueNotifier(false);

  ({Rect clip, Rect full})? _rects() {
    if (!mounted) return null;
    if (!TickerMode.valuesOf(context).enabled) return null;
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
    // Linux: a dialog, sheet or menu open over the app: the video makes room for it (nothing the app draws can lie
    // over the video's surface) and plays on beside it, unless too little of it would be left. Windows' lies under.
    final covered = NativeVideoWindow.behind ? null : OverVideo.covering(clip);
    if (covered != null) {
      clip = OverVideo.beside(clip, covered);
      if (clip.width * clip.height < full.width * full.height * 0.15) return null;
    }
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
    _clear.dispose();
    // Gone (a page closed, the song changed): the next frame hides or moves the window.
    SchedulerBinding.instance.scheduleFrame();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Clear(clear: _clear, child: widget.child);
}

/// Paints [child] (the cover), or clears its box while [clear] is on: the video's window under the Flutter view
/// shows there, and what is painted after it (menus, dialogs) lies over the video.
class _Clear extends SingleChildRenderObjectWidget {
  const _Clear({required this.clear, required super.child});

  final ValueListenable<bool> clear;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderClear(clear);

  @override
  void updateRenderObject(BuildContext context, _RenderClear renderObject) => renderObject.clear = clear;
}

class _RenderClear extends RenderProxyBox {
  _RenderClear(this._clear);

  ValueListenable<bool> _clear;
  set clear(ValueListenable<bool> v) {
    if (identical(v, _clear)) return;
    if (attached) {
      _clear.removeListener(markNeedsPaint);
      v.addListener(markNeedsPaint);
    }
    _clear = v;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _clear.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _clear.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_clear.value) return super.paint(context, offset);
    context.canvas.drawRect(offset & size, Paint()..blendMode = BlendMode.clear);
  }
}

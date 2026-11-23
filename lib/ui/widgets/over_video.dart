import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Dialogs, sheets and menus open over the app (Signal path, the ⋮ menu…), so the music video can make room for
/// them instead of going away.
///
/// On Linux the video is a GTK surface over the app ([NativeVideoSurface]): nothing the app draws can lie over it.
/// It gives up only the part of the screen these take instead of hiding. (Windows' video window lies under the app,
/// which draws them over the playing video.)
/// Navigators report what they open here: one observer for each.
class OverVideo extends NavigatorObserver {
  OverVideo._();

  /// For the app's own navigator (dialogs) and the desktop page history (sheets and menus opened from a page).
  static final root = OverVideo._(), pages = OverVideo._();

  static final _open = <ModalRoute<dynamic>>{};

  /// Something is open over the app.
  static bool get any => _open.isNotEmpty;

  static bool _over(Route<dynamic>? route) => route is ModalRoute && !route.opaque;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_over(route)) _open.add(route as ModalRoute);
    _changed();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _open.remove(route);
    _changed();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _open.remove(route);
    _changed();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _open.remove(oldRoute);
    if (_over(newRoute)) _open.add(newRoute! as ModalRoute);
    _changed();
  }

  // The video's window moves after a frame.
  static void _changed() => SchedulerBinding.instance.scheduleFrame();

  /// The part of [area] (in the window's coordinates) that what is open takes up, or null. Measured by where
  /// each one answers a touch: its sheet or box, not the dimmed barrier around it.
  static Rect? covering(Rect area) {
    if (_open.isEmpty || area.isEmpty) return null;
    const columns = 24, rows = 14;
    final stepX = area.width / columns, stepY = area.height / rows;
    Rect? covered;
    for (final route in _open) {
      if (!route.isActive) continue;
      final box = route.subtreeContext?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      for (var i = 0; i <= columns; i++) {
        for (var j = 0; j <= rows; j++) {
          final point = Offset(area.left + i * stepX, area.top + j * stepY);
          if (!box.hitTest(BoxHitTestResult(), position: box.globalToLocal(point))) continue;
          // A point stands for the cells around it: the room left never reaches under the edge of a sheet.
          final cell = Rect.fromCenter(center: point, width: stepX * 2, height: stepY * 2);
          covered = covered == null ? cell : covered.expandToInclude(cell);
        }
      }
    }
    return covered?.intersect(area);
  }

  /// The largest part of [area] beside [covered]: above, below, left or right of it.
  static Rect beside(Rect area, Rect covered) {
    final options = [
      Rect.fromLTRB(area.left, area.top, area.right, covered.top),
      Rect.fromLTRB(area.left, covered.bottom, area.right, area.bottom),
      Rect.fromLTRB(area.left, area.top, covered.left, area.bottom),
      Rect.fromLTRB(covered.right, area.top, area.right, area.bottom),
    ].map((r) => r.intersect(area)).where((r) => r.width > 0 && r.height > 0);
    Rect best = Rect.zero;
    for (final r in options) {
      if (r.width * r.height > best.width * best.height) best = r;
    }
    return best;
  }

  @visibleForTesting
  static void reset() => _open.clear();
}

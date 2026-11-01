import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Coordinated incoming/outgoing page motion; these never animate audio state.
enum PageMotionStyle {
  classic('Classic'),
  glide('Glide'),
  fadeThrough('Fade through'),
  zoom('Soft zoom'),
  slide('Slide'),
  reveal('Curtain reveal'),
  circularReveal('Circular reveal'),
  wipe('Side reveal'),
  diamondReveal('Diamond reveal');

  const PageMotionStyle(this.label);
  final String label;
}

enum PageMotionSpeed {
  fast('Fast', 0.75),
  balanced('Balanced', 1),
  relaxed('Relaxed', 1.3);

  const PageMotionSpeed(this.label, this.factor);
  final String label;
  final double factor;
}

abstract final class PageMotion {
  static Widget build(
    Animation<double> animation,
    Animation<double> secondary,
    Widget child, {
    required PageMotionStyle style,
    bool reduced = false,
    bool disabled = false,
    bool player = false,
  }) {
    if (disabled) return child;
    // Drive curve tweens directly: no per-build CurvedAnimation listeners to leak.
    Animation<double> curve(Curve c) => animation.drive(CurveTween(curve: c));
    if (reduced) return FadeTransition(opacity: curve(Curves.easeOut), child: child);
    final ease = curve(const Cubic(0.22, 1, 0.36, 1));
    final fade = curve(const Interval(0, 0.8, curve: Curves.easeOutCubic));
    Widget slide(Offset from, {Widget? body}) => SlideTransition(
      position: ease.drive(Tween(begin: from, end: Offset.zero)),
      child: body ?? child,
    );
    Widget scale(double from, {Widget? body}) => ScaleTransition(
      scale: ease.drive(Tween(begin: from, end: 1.0)),
      child: body ?? child,
    );
    final Widget incoming = switch (style) {
      PageMotionStyle.classic =>
        player ? slide(const Offset(0, 1)) : FadeTransition(opacity: fade, child: slide(const Offset(0.03, 0))),
      PageMotionStyle.glide => FadeTransition(
        opacity: fade,
        child: slide(player ? const Offset(0, 0.09) : const Offset(0.065, 0.015), body: scale(0.985)),
      ),
      PageMotionStyle.fadeThrough => FadeTransition(
        opacity: curve(const Interval(0.25, 1, curve: Curves.easeOutCubic)),
        child: scale(0.975),
      ),
      PageMotionStyle.zoom => FadeTransition(opacity: fade, child: scale(0.94)),
      PageMotionStyle.slide => ClipRect(child: slide(player ? const Offset(0, 0.22) : const Offset(0.16, 0))),
      PageMotionStyle.reveal ||
      PageMotionStyle.circularReveal ||
      PageMotionStyle.wipe ||
      PageMotionStyle.diamondReveal => ClipPath(
        clipper: PageRevealClipper(progress: curve(const Cubic(0.76, 0, 0.24, 1)), style: style),
        child: child,
      ),
    };
    if (style == PageMotionStyle.classic ||
        style == PageMotionStyle.reveal ||
        style == PageMotionStyle.circularReveal ||
        style == PageMotionStyle.wipe ||
        style == PageMotionStyle.diamondReveal) {
      return incoming;
    }
    final outgoing = secondary.drive(
      CurveTween(
        curve: style == PageMotionStyle.fadeThrough
            ? const Interval(0, 0.25, curve: Curves.easeOutCubic)
            : Curves.easeInOutCubic,
      ),
    );
    return FadeTransition(
      opacity: outgoing.drive(Tween(begin: 1.0, end: style == PageMotionStyle.fadeThrough ? 0.0 : 0.55)),
      child: SlideTransition(
        position: outgoing.drive(
          Tween(begin: Offset.zero, end: style == PageMotionStyle.slide ? const Offset(-0.035, 0) : Offset.zero),
        ),
        child: incoming,
      ),
    );
  }
}

class PresetPageTransitions extends PageTransitionsBuilder {
  const PresetPageTransitions({
    required this.style,
    required this.duration,
    this.reduced = false,
    this.disabled = false,
  });
  final PageMotionStyle style;
  final Duration duration;
  final bool reduced;
  final bool disabled;

  @override
  Duration get transitionDuration => duration;
  @override
  Duration get reverseTransitionDuration => Duration(microseconds: (duration.inMicroseconds * 0.8).round());

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => PageMotion.build(
    animation,
    secondaryAnimation,
    child,
    style: style,
    reduced: reduced,
    disabled: disabled || MediaQuery.disableAnimationsOf(context),
  );
}

/// Clips a stationary page, so opening the mask never moves text or controls.
/// Re-clipping follows the animation without rebuilding the page underneath.
class PageRevealClipper extends CustomClipper<Path> {
  PageRevealClipper({required this.progress, required this.style}) : super(reclip: progress);
  final Animation<double> progress;
  final PageMotionStyle style;

  @override
  Path getClip(Size size) {
    final t = progress.value.clamp(0.0, 1.0);
    final rect = Offset.zero & size;
    if (t >= 1) return Path()..addRect(rect);
    if (t <= 0) return Path();
    final center = rect.center;
    return switch (style) {
      PageMotionStyle.circularReveal =>
        Path()..addOval(
          Rect.fromCircle(
            center: center,
            radius: math.sqrt(size.width * size.width + size.height * size.height) * 0.5 * t,
          ),
        ),
      PageMotionStyle.diamondReveal =>
        Path()
          ..moveTo(center.dx, center.dy - (size.width + size.height) * 0.5 * t)
          ..lineTo(center.dx + (size.width + size.height) * 0.5 * t, center.dy)
          ..lineTo(center.dx, center.dy + (size.width + size.height) * 0.5 * t)
          ..lineTo(center.dx - (size.width + size.height) * 0.5 * t, center.dy)
          ..close(),
      PageMotionStyle.wipe => Path()..addRect(Rect.fromLTWH(0, 0, size.width * t, size.height)),
      _ => Path()..addRect(Rect.fromLTWH(0, size.height * (1 - t), size.width, size.height * t)),
    };
  }

  @override
  bool shouldReclip(PageRevealClipper oldClipper) => oldClipper.progress != progress || oldClipper.style != style;
}

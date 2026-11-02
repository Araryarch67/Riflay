import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Shared resting geometry for player covers and their audio-driven borders.
abstract final class FlowerContour {
  static double radius(double side, double phase) => side * (0.35 + 0.018 * (1 + math.cos(phase * 24)) / 2);

  static Path path(Size size, {double Function(double phase)? radiusAt}) {
    final center = (Offset.zero & size).center;
    const count = 192;
    final points = List.generate(count, (i) {
      final phase = i / count * math.pi * 2;
      final angle = phase - math.pi / 2;
      final r = radiusAt?.call(phase) ?? radius(size.shortestSide, phase);
      return center + Offset(math.cos(angle), math.sin(angle)) * r;
    });
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    Offset point(int i) => points[i % count];
    for (var i = 0; i < count; i++) {
      final p0 = point(i - 1), p1 = point(i), p2 = point(i + 1), p3 = point(i + 2);
      final c1 = p1 + (p2 - p0) / 6, c2 = p2 - (p3 - p1) / 6;
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    return path..close();
  }
}

/// A static flower cover requires neither an audio player nor a running ticker.
class FlowerCover extends StatelessWidget {
  const FlowerCover({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ClipPath(clipper: const FlowerClipper(), child: child);
}

class FlowerClipper extends CustomClipper<Path> {
  const FlowerClipper({this.fit = false});
  final bool fit;
  @override
  Path getClip(Size size) => FlowerContour.path(
    size,
    radiusAt: fit ? (phase) => FlowerContour.radius(size.shortestSide, phase) * (0.5 / 0.368) : null,
  );
  @override
  bool shouldReclip(FlowerClipper oldClipper) => oldClipper.fit != fit;
}

/// A solid flower silhouette for the optional play/pause button shape.
class FlowerBorder extends ShapeBorder {
  const FlowerBorder();
  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;
  @override
  ShapeBorder scale(double t) => this;
  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => FlowerContour.path(
    rect.size,
    radiusAt: (phase) => rect.shortestSide * (0.43 + 0.07 * (1 + math.cos(phase * 10)) / 2),
  ).shift(rect.topLeft);
  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => getOuterPath(rect, textDirection: textDirection);
  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}
}

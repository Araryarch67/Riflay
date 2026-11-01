import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/layout_prefs.dart';
import '../../services/visualizer_levels.dart';
import '../theme.dart';
import 'audio_reactive_view.dart';

/// Optional player decoration. Disabled means the original child and layout.
class AudioVisualizer extends StatelessWidget {
  const AudioVisualizer({super.key, this.child, this.radialOnly = false, this.linearOnly = false});
  final Widget? child;
  final bool radialOnly;
  final bool linearOnly;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: LayoutPrefs.instance,
    builder: (context, _) {
      final prefs = LayoutPrefs.instance;
      final style = prefs.visualizerStyle;
      if (!prefs.visualizer ||
          !LayoutPrefs.moves ||
          MediaQuery.disableAnimationsOf(context) ||
          (radialOnly && !style.radial) ||
          (linearOnly && style.radial)) {
        return child ?? const SizedBox.shrink();
      }
      return AudioReactiveView(
        builder: (context, levels) {
          final canvas = VisualizerCanvas(
            levels: levels,
            color: AppColors.of(context).accent,
            style: style,
            radius: LayoutPrefs.radius(8),
            child: child,
          );
          return RepaintBoundary(
            child: child != null
                ? canvas
                : IgnorePointer(
                    child: SizedBox(height: 88, width: double.infinity, child: canvas),
                  ),
          );
        },
      );
    },
  );
}

/// Paints only when measured audio changes; the cover does not rebuild per frame.
class VisualizerCanvas extends StatelessWidget {
  const VisualizerCanvas({
    super.key,
    required this.levels,
    required this.color,
    required this.style,
    this.radius = 8,
    this.child,
  });
  final VisualizerLevels levels;
  final Color color;
  final VisualizerStyle style;
  final double radius;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    Widget? art = child;
    if (art != null && style.radial) {
      art = style == VisualizerStyle.petals
          ? ClipPath(clipper: const _PetalClipper(), child: art)
          : ClipOval(child: art);
    }
    return CustomPaint(
      foregroundPainter: _VisualizerPainter(levels, color, style, child != null, radius),
      child: child == null ? null : Padding(padding: const EdgeInsets.all(16), child: art),
    );
  }
}

Path _petalPath(Rect rect) {
  final path = Path();
  final base = rect.shortestSide / 2;
  for (var i = 0; i <= 144; i++) {
    final angle = i / 144 * math.pi * 2;
    final radius = base * (0.95 + 0.04 * math.cos(angle * 12));
    final point = rect.center + Offset(math.cos(angle), math.sin(angle)) * radius;
    if (i == 0) {
      path.moveTo(point.dx, point.dy);
    } else {
      path.lineTo(point.dx, point.dy);
    }
  }
  return path..close();
}

class _PetalClipper extends CustomClipper<Path> {
  const _PetalClipper();
  @override
  Path getClip(Size size) => _petalPath(Offset.zero & size);
  @override
  bool shouldReclip(_PetalClipper oldClipper) => false;
}

class _VisualizerPainter extends CustomPainter {
  _VisualizerPainter(this.levels, this.color, this.style, this.border, this.radius) : super(repaint: levels);
  final VisualizerLevels levels;
  final Color color;
  final VisualizerStyle style;
  final bool border;
  final double radius;

  Paint pen(double opacity, {double width = 2, bool fill = false}) => Paint()
    ..color = color.withValues(alpha: opacity)
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = fill ? PaintingStyle.fill : PaintingStyle.stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final values = levels.value;
    if (size.isEmpty || values.every((v) => v < 0.001)) return;
    if (style.radial) {
      _radial(canvas, size, values);
      return;
    }
    if (border) {
      _border(canvas, size, values);
      return;
    }
    _linear(canvas, size, values);
  }

  void _radial(Canvas canvas, Size size, List<double> values) {
    final center = (Offset.zero & size).center;
    final base = math.max(1.0, size.shortestSide / 2 - 16);
    final energy = values.skip(values.length - 12).reduce((a, b) => a + b) / 12;
    if (style == VisualizerStyle.pulse) {
      for (var i = 0; i < 3; i++) {
        canvas.drawCircle(
          center,
          base + 2 + energy * 3 + i * (3 + energy * 2),
          pen(0.75 / (i + 1), width: i == 0 ? 2 + energy * 3 : 1),
        );
      }
      return;
    }
    final phase = style == VisualizerStyle.orbit ? levels.frame * 0.012 : 0.0;
    final contour = Path();
    for (var i = 0; i <= 96; i++) {
      final angle = i / 96 * 2 * math.pi + phase;
      final ray = Offset(math.cos(angle), math.sin(angle));
      final r = style == VisualizerStyle.petals ? base * (0.95 + 0.04 * math.cos(angle * 12)) : base;
      final level = values[((i % 96) * values.length / 96).floor()];
      final start = center + ray * (r + 2);
      final end = center + ray * (r + 3 + level * 11);
      if (style == VisualizerStyle.petals) {
        canvas.drawLine(start, end, pen(0.85, width: (base / 65).clamp(1.4, 3.0)));
      } else {
        canvas.drawCircle(end, 1.0 + level * 1.5, pen(0.85, fill: true));
      }
      if (i == 0) {
        contour.moveTo(start.dx, start.dy);
      } else {
        contour.lineTo(start.dx, start.dy);
      }
    }
    canvas.drawPath(contour..close(), pen(0.3, width: 1.2));
    if (style == VisualizerStyle.orbit) {
      final point = center + Offset(math.cos(phase * 2), math.sin(phase * 2)) * (base + 8);
      canvas.drawCircle(point, 7, pen(0.12, fill: true));
      canvas.drawCircle(point, 3, pen(0.95, fill: true));
    }
  }

  void _border(Canvas canvas, Size size, List<double> values) {
    final rect = (Offset.zero & size).deflate(16);
    if (rect.isEmpty) return;
    final metric = (Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)))).computeMetrics().first;
    final outside = Path(), inside = Path();
    for (var i = 0; i <= 96; i++) {
      final tangent = metric.getTangentForOffset(metric.length * (i % 96) / 96)!;
      final normal = Offset(tangent.vector.dy, -tangent.vector.dx);
      final level = values[((i % 96) * values.length / 96).floor()];
      final length = level * 11;
      final start = tangent.position + normal * 3;
      final end = tangent.position + normal * (3 + length);
      switch (style) {
        case VisualizerStyle.bars:
          canvas.drawLine(start, end, pen(0.85));
        case VisualizerStyle.mirror:
          canvas.drawLine(
            tangent.position + normal * (9 - length * 0.5),
            tangent.position + normal * (9 + length * 0.5),
            pen(0.85),
          );
        case VisualizerStyle.dots:
          canvas.drawCircle(end, 1.2 + level, pen(0.85, fill: true));
        case VisualizerStyle.peaks:
          if (i < 96) {
            final next = metric.getTangentForOffset(metric.length * ((i + 1) % 96) / 96)!;
            final nextNormal = Offset(next.vector.dy, -next.vector.dx);
            canvas.drawPath(
              Path()
                ..moveTo(start.dx, start.dy)
                ..lineTo(end.dx, end.dy)
                ..lineTo(next.position.dx + nextNormal.dx * 3, next.position.dy + nextNormal.dy * 3)
                ..close(),
              pen(0.65, fill: true),
            );
          }
        default:
          final inset = tangent.position + normal * (14 - length);
          if (i == 0) {
            outside.moveTo(end.dx, end.dy);
            inside.moveTo(inset.dx, inset.dy);
          } else {
            outside.lineTo(end.dx, end.dy);
            inside.lineTo(inset.dx, inset.dy);
          }
      }
    }
    if (style == VisualizerStyle.line || style == VisualizerStyle.wave || style == VisualizerStyle.twinWaves) {
      outside.close();
      if (style != VisualizerStyle.line) canvas.drawPath(outside, pen(0.18, width: 6));
      canvas.drawPath(outside, pen(0.85));
      if (style == VisualizerStyle.twinWaves) canvas.drawPath(inside..close(), pen(0.55, width: 1.5));
    }
  }

  void _linear(Canvas canvas, Size size, List<double> values) {
    final step = size.width / values.length;
    if (style == VisualizerStyle.bars || style == VisualizerStyle.dots || style == VisualizerStyle.mirror) {
      final stroke = (step * 0.6).clamp(1.0, 9.0);
      for (var i = 0; i < values.length; i++) {
        final height = values[i] * (size.height - 6) * math.sin(math.pi * (i + 0.5) / values.length);
        final x = (i + 0.5) * step;
        if (style == VisualizerStyle.dots) {
          for (var y = 4.0; y < height; y += 7) {
            canvas.drawCircle(Offset(x, size.height - y), 2, pen(0.8, fill: true));
          }
        } else {
          final baseline = style == VisualizerStyle.mirror ? size.height / 2 : size.height - 2;
          canvas.drawLine(
            Offset(x, baseline + (style == VisualizerStyle.mirror ? height / 2 : 0)),
            Offset(x, baseline - (style == VisualizerStyle.mirror ? height / 2 : height)),
            pen(0.8, width: stroke),
          );
        }
      }
      return;
    }
    if (style == VisualizerStyle.peaks) {
      final path = Path()..moveTo(0, size.height);
      for (var i = 0; i < values.length; i++) {
        final x = (i + 0.5) * step;
        path.lineTo(x, size.height - values[i] * (size.height - 4));
        path.lineTo(x + step / 2, size.height);
      }
      canvas.drawPath(path..close(), pen(0.65, fill: true));
      return;
    }
    final twin = style == VisualizerStyle.twinWaves;
    for (var layer = 0; layer < (style == VisualizerStyle.line ? 1 : 2); layer++) {
      final baseline = twin ? size.height / 2 : size.height;
      final path = Path()..moveTo(0, baseline);
      for (var i = 0; i < values.length; i++) {
        final index = layer == 0 ? i : values.length - 1 - i;
        final x = size.width * i / (values.length - 1);
        final height = values[index] * (size.height - 4) * math.sin(math.pi * i / (values.length - 1));
        final y = baseline + height * (twin ? (layer == 0 ? -0.48 : 0.48) : (layer == 0 ? -1 : -0.65));
        if (i == 0) {
          path.lineTo(x, y);
        } else {
          final px = size.width * (i - 1) / (values.length - 1);
          final previous = values[layer == 0 ? i - 1 : values.length - i];
          final ph = previous * (size.height - 4) * math.sin(math.pi * (i - 1) / (values.length - 1));
          final py = baseline + ph * (twin ? (layer == 0 ? -0.48 : 0.48) : (layer == 0 ? -1 : -0.65));
          path.quadraticBezierTo(px, py, (px + x) / 2, (py + y) / 2);
        }
      }
      if (style == VisualizerStyle.line || twin) {
        canvas.drawPath(path, pen(twin ? 0.7 : 0.9, width: twin ? 2 : 2.5));
      } else {
        path.lineTo(size.width, baseline);
        path.close();
        canvas.drawPath(path, pen(layer == 0 ? 0.5 : 0.25, fill: true));
      }
    }
  }

  @override
  bool shouldRepaint(_VisualizerPainter old) =>
      old.levels != levels || old.color != color || old.border != border || old.radius != radius || old.style != style;
}

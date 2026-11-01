import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/layout_prefs.dart';
import '../theme.dart';
import 'audio_reactive_view.dart';

/// Optional player decoration. Disabled means the original child and layout.
class AudioVisualizer extends StatelessWidget {
  const AudioVisualizer({super.key, this.child});

  /// A cover gets a compact border; without a child, draws desktop waves.
  final Widget? child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: LayoutPrefs.instance,
    builder: (context, _) {
      if (!LayoutPrefs.instance.visualizer || !LayoutPrefs.moves || MediaQuery.disableAnimationsOf(context)) {
        return child ?? const SizedBox.shrink();
      }
      return AudioReactiveView(
        builder: (context, levels) {
          final border = child != null;
          final paint = CustomPaint(
            foregroundPainter: _VisualizerPainter(
              levels: levels,
              color: AppColors.of(context).accent,
              border: border,
              radius: LayoutPrefs.radius(8),
              style: LayoutPrefs.instance.visualizerStyle,
            ),
            child: border ? Padding(padding: const EdgeInsets.all(16), child: child) : null,
          );
          return RepaintBoundary(
            child: border
                ? paint
                : IgnorePointer(
                    child: SizedBox(height: 88, width: double.infinity, child: paint),
                  ),
          );
        },
      );
    },
  );
}

class _VisualizerPainter extends CustomPainter {
  _VisualizerPainter({
    required this.levels,
    required this.color,
    required this.border,
    required this.radius,
    required this.style,
  }) : super(repaint: levels);

  final ValueNotifier<List<double>> levels;
  final Color color;
  final bool border;
  final double radius;
  final VisualizerStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final values = levels.value;
    if (size.isEmpty || values.every((v) => v < 0.001)) return;
    if (border) {
      final rect = (Offset.zero & size).deflate(16);
      if (rect.isEmpty) return;
      final outline = Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
      final metric = outline.computeMetrics().first;
      final pen = Paint()
        ..color = color.withValues(alpha: 0.85)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      // One compact outline, with bars perpendicular to its actual corners.
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(2), Radius.circular(radius + 2)),
        Paint()
          ..color = color.withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      final contour = Path();
      for (var i = 0; i <= 96; i++) {
        final tangent = metric.getTangentForOffset(metric.length * (i % 96) / 96)!;
        final normal = Offset(tangent.vector.dy, -tangent.vector.dx);
        final level = values[((i % 96) * values.length / 96).floor()];
        final tip = tangent.position + normal * (3 + level * 11);
        switch (style) {
          case VisualizerStyle.bars:
            canvas.drawLine(tangent.position + normal * 3, tip, pen);
          case VisualizerStyle.dots:
            canvas.drawCircle(tip, 1.2 + level, pen);
          case VisualizerStyle.line || VisualizerStyle.wave:
            if (i == 0) {
              contour.moveTo(tip.dx, tip.dy);
            } else {
              contour.lineTo(tip.dx, tip.dy);
            }
        }
      }
      if (style == VisualizerStyle.line || style == VisualizerStyle.wave) {
        contour.close();
        if (style == VisualizerStyle.wave) {
          canvas.drawPath(
            contour,
            Paint()
              ..color = color.withValues(alpha: 0.18)
              ..strokeWidth = 6
              ..style = PaintingStyle.stroke,
          );
        }
        canvas.drawPath(contour, pen..style = PaintingStyle.stroke);
      }
      return;
    }
    if (style == VisualizerStyle.bars || style == VisualizerStyle.dots) {
      final pen = Paint()
        ..color = color.withValues(alpha: 0.8)
        ..strokeCap = StrokeCap.round;
      final step = size.width / values.length;
      pen.strokeWidth = (step * 0.6).clamp(1.0, 9.0);
      for (var i = 0; i < values.length; i++) {
        final height = values[i] * (size.height - 6) * math.sin(math.pi * (i + 0.5) / values.length);
        final x = (i + 0.5) * step;
        if (style == VisualizerStyle.bars) {
          canvas.drawLine(Offset(x, size.height - 2), Offset(x, size.height - 2 - height), pen);
        } else {
          for (var y = 4.0; y < height; y += 7) {
            canvas.drawCircle(Offset(x, size.height - y), 2, pen);
          }
        }
      }
      return;
    }
    // Smoothed audio level history: two translucent shores meet the bottom edge.
    for (var layer = 0; layer < (style == VisualizerStyle.line ? 1 : 2); layer++) {
      final path = Path()..moveTo(0, size.height - (style == VisualizerStyle.line ? 4 : 0));
      for (var i = 0; i < values.length; i++) {
        final index = layer == 0 ? i : values.length - 1 - i;
        final x = size.width * i / (values.length - 1);
        final taper = math.sin(math.pi * i / (values.length - 1));
        final y = size.height - values[index] * (size.height - 4) * taper * (layer == 0 ? 1 : 0.65);
        if (i == 0) {
          path.lineTo(x, y);
        } else {
          final previous = values[layer == 0 ? i - 1 : values.length - i];
          final px = size.width * (i - 1) / (values.length - 1);
          final py =
              size.height -
              previous *
                  (size.height - 4) *
                  math.sin(math.pi * (i - 1) / (values.length - 1)) *
                  (layer == 0 ? 1 : 0.65);
          path.quadraticBezierTo(px, py, (px + x) / 2, (py + y) / 2);
        }
      }
      if (style == VisualizerStyle.line) {
        canvas.drawPath(
          path,
          Paint()
            ..color = color.withValues(alpha: 0.9)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5,
        );
      } else {
        path.lineTo(size.width, size.height);
        path.close();
        canvas.drawPath(path, Paint()..color = color.withValues(alpha: layer == 0 ? 0.5 : 0.25));
      }
    }
  }

  @override
  bool shouldRepaint(_VisualizerPainter old) =>
      old.levels != levels || old.color != color || old.border != border || old.radius != radius || old.style != style;
}

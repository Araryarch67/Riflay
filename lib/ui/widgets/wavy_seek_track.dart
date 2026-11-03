import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Only the elapsed portion is wavy. Slider gestures and semantics stay native.
class WavySeekTrack extends SliderTrackShape with BaseSliderTrackShape {
  const WavySeekTrack();

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
  }) {
    final height = sliderTheme.trackHeight ?? 4;
    if (height <= 0) return;
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final active = ColorTween(
      begin: sliderTheme.disabledActiveTrackColor,
      end: sliderTheme.activeTrackColor,
    ).evaluate(enableAnimation)!;
    final inactive = ColorTween(
      begin: sliderTheme.disabledInactiveTrackColor,
      end: sliderTheme.inactiveTrackColor,
    ).evaluate(enableAnimation)!;
    final rtl = textDirection == TextDirection.rtl;
    final start = rtl ? rect.right : rect.left;
    final end = rtl ? rect.left : rect.right;
    final thumb = thumbCenter.dx.clamp(rect.left, rect.right);
    final pen = Paint()
      ..strokeWidth = height
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    context.canvas.drawLine(Offset(thumb, rect.center.dy), Offset(end, rect.center.dy), pen..color = inactive);
    final length = (thumb - start).abs();
    if (length < 0.01) return;
    final amplitude = (height * 0.4 + 2).clamp(3.0, 5.0);
    final wavelength = 16 + height * 0.5;
    final path = Path()..moveTo(start, rect.center.dy);
    final steps = length.ceil();
    for (var i = 1; i <= steps; i++) {
      final distance = length * i / steps;
      // Join the straight remainder and thumb at the baseline, without a jump.
      final fade = math.min(1.0, math.min(distance, length - distance) / (wavelength / 4));
      path.lineTo(
        start + (rtl ? -distance : distance),
        rect.center.dy + math.sin(distance / wavelength * math.pi * 2) * amplitude * fade,
      );
    }
    context.canvas.drawPath(path, pen..color = active);
  }
}

/// A thick, fully rounded track: the elapsed part is a pill, a small dot marks the end.
class PillSeekTrack extends SliderTrackShape with BaseSliderTrackShape {
  const PillSeekTrack();

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
  }) {
    final height = sliderTheme.trackHeight ?? 9;
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final active = sliderTheme.activeTrackColor ?? Colors.white;
    final inactive = sliderTheme.inactiveTrackColor ?? Colors.white24;
    final canvas = context.canvas;
    final radius = Radius.circular(height / 2);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), Paint()..color = inactive);
    final thumb = thumbCenter.dx.clamp(rect.left + height, rect.right);
    canvas.drawRRect(RRect.fromLTRBR(rect.left, rect.top, thumb, rect.bottom, radius), Paint()..color = active);
    // The end dot hides under the pill once it reaches it.
    final dot = Offset(rect.right - height / 2, rect.center.dy);
    if (thumb < dot.dx - height / 2) {
      canvas.drawCircle(dot, height * 0.2, Paint()..color = active.withValues(alpha: 0.6));
    }
  }
}

/// A short vertical bar, for the pill track.
class BarThumbShape extends SliderComponentShape {
  const BarThumbShape({this.height = 24});

  final double height;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => Size(4, height);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: center, width: 4, height: height), const Radius.circular(2)),
      Paint()..color = sliderTheme.thumbColor ?? Colors.white,
    );
  }
}

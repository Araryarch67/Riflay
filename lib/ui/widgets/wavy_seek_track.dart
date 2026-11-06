import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'playing_motion.dart';

/// Only the elapsed portion is wavy. Slider gestures and semantics stay native.
class WavySeekTrack extends SliderTrackShape with BaseSliderTrackShape {
  /// With a [motion] clock the wave travels towards the thumb while it runs and flattens to a
  /// line as it eases out (a pause). Without one it is the still wave.
  const WavySeekTrack({this.motion});

  final MotionClock? motion;

  /// Wavelengths the wave travels in a second.
  static const _speed = 0.55;

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
    final amplitude = (height * 0.4 + 2).clamp(3.0, 5.0) * (motion?.eased ?? 1);
    final shift = (motion?.time ?? 0) * _speed;
    final wavelength = 16 + height * 0.5;
    final path = Path()..moveTo(start, rect.center.dy);
    final steps = length.ceil();
    for (var i = 1; i <= steps; i++) {
      final distance = length * i / steps;
      // Join the straight remainder and thumb at the baseline, without a jump.
      final fade = math.min(1.0, math.min(distance, length - distance) / (wavelength / 4));
      path.lineTo(
        start + (rtl ? -distance : distance),
        rect.center.dy + math.sin((distance / wavelength - shift) * math.pi * 2) * amplitude * fade,
      );
    }
    context.canvas.drawPath(path, pen..color = active);
  }
}

/// The song's waveform for a track: [bars] (0-255 each) side by side, the elapsed ones in the active colour.
class WaveformSeekTrack extends SliderTrackShape with BaseSliderTrackShape {
  const WaveformSeekTrack(this.bars);

  final Uint8List bars;

  /// The bars' height; the slider's track height is only its line through the middle.
  static const height = 26.0;

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
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    if (bars.isEmpty || rect.width <= 0) return;
    final active = ColorTween(
      begin: sliderTheme.disabledActiveTrackColor,
      end: sliderTheme.activeTrackColor,
    ).evaluate(enableAnimation)!;
    final inactive = ColorTween(
      begin: sliderTheme.disabledInactiveTrackColor,
      end: sliderTheme.inactiveTrackColor,
    ).evaluate(enableAnimation)!;
    final rtl = textDirection == TextDirection.rtl;
    // As many bars as fit at 3 px each (a gap of a pixel), each the loudest of the song's bars it stands for.
    final count = math.max(1, (rect.width / 3).floor());
    final step = rect.width / count;
    final width = math.max(1.0, step - 1);
    final thumb = thumbCenter.dx;
    final pen = Paint();
    for (var i = 0; i < count; i++) {
      final from = i * bars.length ~/ count, to = math.max(from + 1, (i + 1) * bars.length ~/ count);
      var level = 0;
      for (var k = from; k < to && k < bars.length; k++) {
        if (bars[k] > level) level = bars[k];
      }
      final h = math.max(2.0, height * level / 255);
      final x = rtl ? rect.right - (i + 1) * step : rect.left + i * step;
      final played = rtl ? x + width / 2 >= thumb : x + width / 2 <= thumb;
      context.canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, rect.center.dy - h / 2, width, h),
          Radius.circular(width / 2),
        ),
        pen..color = played ? active : inactive,
      );
    }
  }
}

/// A thick, fully rounded track, as in Material 3 Expressive: the elapsed part and the rest are two pills with a
/// small gap either side of the thumb bar, and a dot marks the end.
class PillSeekTrack extends SliderTrackShape with BaseSliderTrackShape {
  const PillSeekTrack();

  /// Clear space between the thumb bar and the track on each side of it.
  static const gap = 6.0;

  /// The elapsed pill and the rest, for a thumb at [thumbX] on [rect] of [height]. Each is rounded only at its outer
  /// end (the far left of the elapsed one, the far right of the rest); the ends facing the thumb are square, as in
  /// Material 3 Expressive. Null where a part is too short to draw (the very start or end of the song).
  @visibleForTesting
  static (RRect?, RRect?) segments(Rect rect, double thumbX, double height) {
    final round = Radius.circular(height / 2);
    final thumb = thumbX.clamp(rect.left, rect.right);
    // The thumb bar is 4 px wide: its half and the gap keep both pills clear of it.
    final playedEnd = thumb - gap - 2, restStart = thumb + gap + 2;
    return (
      playedEnd - rect.left > 0.5
          ? RRect.fromRectAndCorners(
              Rect.fromLTRB(rect.left, rect.top, playedEnd, rect.bottom),
              topLeft: round,
              bottomLeft: round,
            )
          : null,
      rect.right - restStart > 0.5
          ? RRect.fromRectAndCorners(
              Rect.fromLTRB(restStart, rect.top, rect.right, rect.bottom),
              topRight: round,
              bottomRight: round,
            )
          : null,
    );
  }

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
    final (played, rest) = segments(rect, thumbCenter.dx, height);
    // A part shorter than 0.5 px (the very start or end of the song) is not drawn at all.
    if (played != null) canvas.drawRRect(played, Paint()..color = active);
    if (rest != null) {
      canvas.drawRRect(rest, Paint()..color = inactive);
      final restStart = rest.left;
      // The end dot hides under the thumb's side once the rest is shorter than it.
      final dot = Offset(rect.right - height / 2, rect.center.dy);
      if (restStart < dot.dx - 4) canvas.drawCircle(dot, 2, Paint()..color = active);
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

/// A flat, fully rounded track: the elapsed part in the active colour, the rest translucent. Nothing marks the
/// position (see [DragDotShape]), like the thin bars of streaming apps.
class ThinSeekTrack extends SliderTrackShape with BaseSliderTrackShape {
  const ThinSeekTrack();

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
    final radius = Radius.circular(rect.height / 2);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), Paint()..color = inactive);
    final rtl = textDirection == TextDirection.rtl;
    final thumb = thumbCenter.dx.clamp(rect.left, rect.right);
    if ((thumb - (rtl ? rect.right : rect.left)).abs() < 0.5) return;
    final played = rtl
        ? Rect.fromLTRB(thumb, rect.top, rect.right, rect.bottom)
        : Rect.fromLTRB(rect.left, rect.top, thumb, rect.bottom);
    canvas.drawRRect(RRect.fromRectAndRadius(played, radius), Paint()..color = active);
  }
}

/// A small dot for the handle of a [ThinSeekTrack]. Used as the slider's overlay, so it only shows while the bar is
/// being dragged or hovered and has no size at rest.
class DragDotShape extends SliderComponentShape {
  const DragDotShape({this.radius = 6});

  final double radius;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => Size.zero;

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
    final t = activationAnimation.value;
    if (t <= 0) return;
    context.canvas.drawCircle(center, radius * t, Paint()..color = sliderTheme.thumbColor ?? Colors.white);
  }
}

/// The slider look of the Pill shape (Material 3 expressive): a thick track, square where it meets the tall bar
/// thumb, with a dot at its end. For the progress bar and the volume slider.
SliderThemeData pillSliderTheme(SliderThemeData base, Color color, {double height = 16, double thumb = 36}) =>
    base.copyWith(
      trackHeight: height,
      trackShape: const PillSeekTrack(),
      activeTrackColor: color,
      inactiveTrackColor: color.withValues(alpha: 0.18),
      thumbColor: color,
      thumbShape: BarThumbShape(height: thumb),
      overlayColor: Colors.transparent,
      padding: EdgeInsets.zero,
    );

/// The slider look of the Thin line shape: 4 px, white on translucent, no handle at rest. For the progress bar and
/// the volume slider.
SliderThemeData thinSliderTheme(SliderThemeData base, Color color) => base.copyWith(
  trackHeight: 4,
  trackShape: const ThinSeekTrack(),
  activeTrackColor: color,
  inactiveTrackColor: color.withValues(alpha: 0.28),
  thumbColor: color,
  thumbShape: SliderComponentShape.noThumb,
  overlayShape: const DragDotShape(),
  overlayColor: Colors.transparent,
  padding: EdgeInsets.zero,
);

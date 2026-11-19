import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Riflay's mark, drawn from the same shapes as the app icon
/// (assets/icon/riflay-transparent.svg). The light parts take the theme's
/// text colour, so the mark reads on light themes too; the orange stays.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 16, this.monochromeColor});

  final double size;
  final Color? monochromeColor;

  static const orange = Color(0xFFFF7A1A);

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _LogoPainter(monochromeColor ?? AppColors.textPrimary, monochromeColor ?? orange)),
  );
}

/// The mark's four pieces in the design's 1440-unit square, for painters that
/// move them on their own (the desktop intro). The mark spans [bounds].
abstract final class LogoMark {
  static const bounds = Rect.fromLTRB(368, 328, 1111, 1111);
  static const _radius = 94.0; // the left chevron's rounded tip

  static final top = _poly(const [Offset(720, 328), Offset(831, 439.5), Offset(720, 551), Offset(609, 439.5)]);
  static final bottom = _poly(const [Offset(720, 888), Offset(831, 999.5), Offset(720, 1111), Offset(609, 999.5)]);

  /// Left chevron: its outer corner (328.5, 719.5) rounded off.
  static final left = () {
    final t = _radius / math.sqrt2;
    final cx = 328.5 + _radius * math.sqrt2;
    return Path()
      ..moveTo(580, 468)
      ..lineTo(691, 579.5)
      ..lineTo(552, 719.5)
      ..lineTo(691, 859.5)
      ..lineTo(580, 971)
      ..lineTo(cx - t, 719.5 + t)
      ..arcToPoint(Offset(cx - t, 719.5 - t), radius: const Radius.circular(_radius))
      ..close();
  }();

  /// The orange chevron.
  static final right = _poly(const [
    Offset(859, 468),
    Offset(1111, 719.5),
    Offset(859, 971),
    Offset(748, 859.5),
    Offset(887, 719.5),
    Offset(748, 579.5),
  ]);

  static Path _poly(List<Offset> points) => Path()..addPolygon(points, true);

  /// Scales and centres [canvas] so the mark fits [size].
  static void fit(Canvas canvas, Size size) {
    final k = math.min(size.width / bounds.width, size.height / bounds.height);
    canvas
      ..translate((size.width - bounds.width * k) / 2, (size.height - bounds.height * k) / 2)
      ..scale(k)
      ..translate(-bounds.left, -bounds.top);
  }
}

class _LogoPainter extends CustomPainter {
  _LogoPainter(this.light, this.accent);

  final Color light;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    LogoMark.fit(canvas, size);
    final white = Paint()..color = light;
    canvas
      ..drawPath(LogoMark.top, white)
      ..drawPath(LogoMark.bottom, white)
      ..drawPath(LogoMark.left, white)
      ..drawPath(LogoMark.right, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(_LogoPainter old) => old.light != light || old.accent != accent;
}

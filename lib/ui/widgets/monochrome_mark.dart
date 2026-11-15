import 'package:flutter/material.dart';

/// Monochrome's stepped square mark, drawn in the current foreground colour.
class MonochromeMark extends StatelessWidget {
  const MonochromeMark({super.key, this.size = 18, this.color});
  final double size;
  final Color? color;
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _MonochromePainter(color ?? IconTheme.of(context).color ?? Colors.white)),
  );
}

class _MonochromePainter extends CustomPainter {
  const _MonochromePainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 22, size.height / 22);
    final paint = Paint()
      ..color = color
      ..isAntiAlias = false;
    for (final rect in const [
      Rect.fromLTRB(8, 0, 22, 7),
      Rect.fromLTRB(15, 7, 22, 15),
      Rect.fromLTRB(0, 8, 7, 15),
      Rect.fromLTRB(0, 15, 15, 22),
    ]) {
      canvas.drawRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(_MonochromePainter oldDelegate) => oldDelegate.color != color;
}

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../models/track.dart';
import '../theme.dart';
import '../widgets/controls.dart' show AccentBuilder, Artwork;

/// How a poster's song cards look: a light or dark widget, frosted glass (the photo blurred through it), liquid glass
/// (clear, the photo bent by its thick edge, light caught on its rim), or the cover's own colour.
enum PosterCardStyle { light, dark, glass, liquid, cover }

/// A song as a phone's "now playing" widget, drawn for a poster: the cover, the song, a progress bar at [progress]
/// (0–1) with its times, the transport and a volume bar. Not a control: nothing on it can be pressed.
class PosterCard extends StatelessWidget {
  const PosterCard({super.key, required this.track, this.progress = 0.4, this.style = PosterCardStyle.light});

  final Track track;
  final double progress;
  final PosterCardStyle style;

  /// The width it is laid out at; a poster scales it.
  static const width = 260.0;

  static const _outline = Color(0xE6000000);

  /// Raised off the photo: a tight shadow where it nearly touches, a wide soft one under it, lower down.
  static const _lift = [
    BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 2)),
    BoxShadow(color: Color(0x73000000), blurRadius: 38, offset: Offset(0, 22)),
  ];

  @override
  Widget build(BuildContext context) => style == PosterCardStyle.cover
      ? AccentBuilder(track: track, builder: (context, accent) => _card(context, accent))
      : _card(context, null);

  Widget _card(BuildContext context, Color? accent) {
    final light = style == PosterCardStyle.light;
    final glass = style == PosterCardStyle.glass;
    final liquid = style == PosterCardStyle.liquid;
    final ink = light ? const Color(0xFF1C1C1E) : Colors.white;
    final soft = ink.withValues(alpha: 0.55);
    final text = Theme.of(context).textTheme;
    final length = track.duration ?? const Duration(minutes: 3, seconds: 30);
    final at = length * progress.clamp(0.0, 1.0);
    String time(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
    Widget bar(double value) => ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: LinearProgressIndicator(
        value: value,
        minHeight: 4,
        color: ink.withValues(alpha: 0.85),
        backgroundColor: ink.withValues(alpha: 0.18),
      ),
    );
    final corners = BorderRadius.circular(30);
    final body = Container(
      width: width,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: switch (style) {
          PosterCardStyle.light => const Color(0xE6D9DCE1),
          PosterCardStyle.dark => const Color(0xD91C1C1E),
          PosterCardStyle.glass => Colors.white.withValues(alpha: 0.12),
          // Lightly tinted (its gradient below): darker towards the foot, where the text and controls are.
          PosterCardStyle.liquid => null,
          PosterCardStyle.cover => AppColors.sink(accent ?? Colors.grey, 0.45).withValues(alpha: 0.92),
        },
        // Glass: light caught at the top edge fading down, as a pane of glass does.
        gradient: liquid
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black.withValues(alpha: 0.10), Colors.black.withValues(alpha: 0.32)],
              )
            : glass
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.white.withValues(alpha: 0.32), Colors.white.withValues(alpha: 0.06)],
              )
            : null,
        borderRadius: corners,
        // A firm black edge, every look: the card stands clear of any photo.
        border: Border.all(color: _outline, width: 2.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Decoded four times sharper than drawn: the poster enlarges its cards, zooms in while editing and is
          // saved at 1080 pixels or more, where a cover decoded at its laid-out size went soft.
          MediaQuery(
            data: MediaQuery.of(context).copyWith(devicePixelRatio: 4),
            child: Artwork(track: track, size: width - 28, radius: 20),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium?.copyWith(color: ink, fontWeight: FontWeight.w700),
                    ),
                    Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(color: soft),
                    ),
                  ],
                ),
              ),
              Icon(Icons.favorite_border_rounded, size: 20, color: ink),
            ],
          ),
          const SizedBox(height: 12),
          bar(progress),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(time(at), style: text.labelSmall?.copyWith(color: soft)),
              Text('-${time(length - at)}', style: text.labelSmall?.copyWith(color: soft)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.fast_rewind_rounded, size: 30, color: ink),
              const SizedBox(width: 26),
              Icon(Icons.pause_rounded, size: 36, color: ink),
              const SizedBox(width: 26),
              Icon(Icons.fast_forward_rounded, size: 30, color: ink),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.volume_mute_rounded, size: 14, color: soft),
              const SizedBox(width: 6),
              Expanded(child: bar(0.6)),
              const SizedBox(width: 6),
              Icon(Icons.volume_up_rounded, size: 14, color: soft),
            ],
          ),
        ],
      ),
    );
    final shadow = DecoratedBox(
      decoration: BoxDecoration(borderRadius: corners, boxShadow: _lift),
      child: body,
    );
    if (liquid) {
      // What is behind softened through its body (a card behind it is not read through it, doubled), but bent sharp
      // and larger along its thick edge, as glass bends light; then the light on its rim. All drawn in the card's own
      // space, so it follows the card in 3D.
      return DecoratedBox(
        decoration: BoxDecoration(borderRadius: corners, boxShadow: _lift),
        child: ClipRRect(
          borderRadius: corners,
          child: _Lens(
            scale: 1.03,
            blur: 7,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipPath(
                    clipper: _Ring(9, corners.topLeft.x),
                    child: const _Lens(scale: 1.14, blur: 0.8, child: SizedBox.expand()),
                  ),
                ),
                body,
                Positioned.fill(
                  child: IgnorePointer(child: CustomPaint(painter: _Rim(corners.topLeft.x))),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (!glass) return shadow;
    // The photo behind seen through it, blurred: drawn by the poster itself, so it follows the card in 3D (the
    // app's liquid glass places its shapes unturned).
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: corners, boxShadow: _lift),
      child: ClipRRect(
        borderRadius: corners,
        child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18), child: body),
      ),
    );
  }
}

/// [child] (a card) drawn with [transform], with a body behind it: thin layers of its shape set back in depth, so a
/// card turned in 3D shows an edge, as a slab of glass or plastic does, instead of a flat sheet. Each layer has its
/// own whole matrix, side by side with the card, not nested in it: a renderer that flattens a nested 3D transform
/// (once part of the card is drawn into a layer of its own) had dropped the body.
class PosterSlab extends StatelessWidget {
  const PosterSlab({super.key, required this.style, required this.transform, required this.child, this.thickness = 4});

  final PosterCardStyle style;
  final Matrix4 transform;
  final Widget child;

  /// How deep the card is, before it is scaled.
  final double thickness;

  static const _layers = 10;

  @override
  Widget build(BuildContext context) {
    final face = Transform(alignment: Alignment.center, transform: transform, child: child);
    if (thickness <= 0) return face;
    final edge = switch (style) {
      PosterCardStyle.light => const Color(0xFFAEB3BC),
      PosterCardStyle.dark => const Color(0xFF0B0B0D),
      PosterCardStyle.glass => Colors.white.withValues(alpha: 0.28),
      PosterCardStyle.liquid => Colors.white.withValues(alpha: 0.16),
      PosterCardStyle.cover => const Color(0xB3000000),
    };
    final clear = style == PosterCardStyle.glass || style == PosterCardStyle.liquid;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // The farthest first; the card's own face over them.
        for (var i = _layers; i >= 1; i--)
          Positioned.fill(
            child: IgnorePointer(
              child: Transform(
                alignment: Alignment.center,
                transform: transform * Matrix4.translationValues(0, 0, thickness * i / _layers),
                child: DecoratedBox(
                  // The edge darker towards the back. Glass is a rim only: filled, the layers piled up behind a flat
                  // card into a grey sheet and nothing was seen through it.
                  decoration: clear
                      ? BoxDecoration(
                          border: Border.all(color: edge, width: 1.5),
                          borderRadius: BorderRadius.circular(30),
                        )
                      : BoxDecoration(
                          color: Color.lerp(edge, Colors.black, i / _layers * 0.35),
                          borderRadius: BorderRadius.circular(30),
                        ),
                ),
              ),
            ),
          ),
        face,
      ],
    );
  }
}

/// The photo behind [child] enlarged by [scale] about [child]'s middle and blurred by [blur]: a lens. Worked out where it
/// is painted, so the middle is its own (a plain backdrop filter scales about the screen's corner).
class _Lens extends SingleChildRenderObjectWidget {
  const _Lens({required this.scale, required this.blur, super.child});

  final double scale, blur;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderLens(scale, blur);

  @override
  void updateRenderObject(BuildContext context, _RenderLens lens) => lens
    ..scale = scale
    ..blur = blur;
}

class _RenderLens extends RenderProxyBox {
  _RenderLens(this._scale, this._blur);

  double _scale, _blur;
  set scale(double v) {
    if (v == _scale) return;
    _scale = v;
    markNeedsPaint();
  }

  set blur(double v) {
    if (v == _blur) return;
    _blur = v;
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  BackdropFilterLayer? get layer => super.layer as BackdropFilterLayer?;

  @override
  void paint(PaintingContext context, Offset offset) {
    final c = offset + size.center(Offset.zero);
    final zoom = Matrix4.translationValues(c.dx, c.dy, 0)
      ..scaleByDouble(_scale, _scale, 1, 1)
      ..translateByDouble(-c.dx, -c.dy, 0, 1);
    final matrix = ImageFilter.matrix(zoom.storage, filterQuality: FilterQuality.medium);
    layer ??= BackdropFilterLayer();
    layer!.filter = _blur <= 0
        ? matrix
        : ImageFilter.compose(
            outer: ImageFilter.blur(sigmaX: _blur, sigmaY: _blur),
            inner: matrix,
          );
    context.pushLayer(layer!, super.paint, offset);
  }
}

/// A rounded card's outer band, [inset] wide.
class _Ring extends CustomClipper<Path> {
  const _Ring(this.inset, this.radius);

  final double inset, radius;

  @override
  Path getClip(Size size) {
    final outer = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    return Path()
      ..fillType = PathFillType.evenOdd
      ..addRRect(outer)
      ..addRRect(outer.deflate(inset));
  }

  @override
  bool shouldReclip(_Ring old) => old.inset != inset || old.radius != radius;
}

/// Light caught by glass: bright on the rim at the top left and, fainter, the bottom right, and a soft sheen down
/// from the top.
class _Rim extends CustomPainter {
  const _Rim(this.radius);

  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    // A soft sheen down from the top.
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: const Alignment(0, -0.4),
          colors: [Colors.white.withValues(alpha: 0.14), Colors.white.withValues(alpha: 0)],
        ).createShader(rect),
    );
    // Shade just inside the edge, deepest at the foot: the glass has thickness.
    canvas.drawRRect(
      rrect.deflate(6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withValues(alpha: 0), Colors.black.withValues(alpha: 0.22)],
        ).createShader(rect),
    );
    // The rim catching the light: bright at the top left, again at the bottom right, faint between.
    canvas.drawRRect(
      rrect.deflate(3.25),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.95),
            Colors.white.withValues(alpha: 0.25),
            Colors.white.withValues(alpha: 0.1),
            Colors.white.withValues(alpha: 0.55),
          ],
          stops: const [0, 0.3, 0.65, 1],
        ).createShader(rect),
    );
    // A thin inner line of light just under the rim at the top, as the far side of the glass catches it too.
    canvas.drawRRect(
      rrect.deflate(5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.center,
          colors: [Colors.white.withValues(alpha: 0.35), Colors.white.withValues(alpha: 0)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_Rim old) => old.radius != radius;
}

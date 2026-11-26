import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../theme.dart';
import '../widgets/controls.dart' show AccentBuilder, Artwork;

/// How a poster's song cards look: a light or dark widget, clear glass over the photo, or the cover's own colour.
enum PosterCardStyle { light, dark, glass, cover }

/// A song as a phone's "now playing" widget, drawn for a poster: the cover, the song, a progress bar at [progress]
/// (0–1) with its times, the transport and a volume bar. Not a control: nothing on it can be pressed.
class PosterCard extends StatelessWidget {
  const PosterCard({super.key, required this.track, this.progress = 0.4, this.style = PosterCardStyle.light});

  final Track track;
  final double progress;
  final PosterCardStyle style;

  /// The width it is laid out at; a poster scales it.
  static const width = 260.0;

  @override
  Widget build(BuildContext context) => style == PosterCardStyle.cover
      ? AccentBuilder(track: track, builder: (context, accent) => _card(context, accent))
      : _card(context, null);

  Widget _card(BuildContext context, Color? accent) {
    final light = style == PosterCardStyle.light;
    final glass = style == PosterCardStyle.glass;
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
          PosterCardStyle.cover => AppColors.sink(accent ?? Colors.grey, 0.45).withValues(alpha: 0.92),
        },
        // Glass: light caught at the top edge fading down, as a pane of glass does.
        gradient: glass
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.white.withValues(alpha: 0.32), Colors.white.withValues(alpha: 0.06)],
              )
            : null,
        borderRadius: corners,
        border: Border.all(color: Colors.white.withValues(alpha: light || glass ? 0.6 : 0.18), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Artwork(track: track, size: width - 28, radius: 20),
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
      decoration: BoxDecoration(
        borderRadius: corners,
        boxShadow: const [BoxShadow(color: Color(0x59000000), blurRadius: 30, offset: Offset(0, 14))],
      ),
      child: body,
    );
    if (!glass) return shadow;
    // The photo behind seen through it, blurred: drawn by the poster itself, so it follows the card in 3D (the
    // app's liquid glass places its shapes unturned).
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: corners,
        boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 30, offset: Offset(0, 14))],
      ),
      child: ClipRRect(
        borderRadius: corners,
        child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18), child: body),
      ),
    );
  }
}

/// [child] (a card) with a body behind it: thin layers of its shape set back in depth, so a card turned in 3D shows an
/// edge, as a slab of glass or plastic does, instead of a flat sheet.
class PosterSlab extends StatelessWidget {
  const PosterSlab({super.key, required this.style, required this.child, this.thickness = 4});

  final PosterCardStyle style;
  final Widget child;

  /// How deep the card is, before it is scaled.
  final double thickness;

  static const _layers = 10;

  @override
  Widget build(BuildContext context) {
    if (thickness <= 0) return child;
    final edge = switch (style) {
      PosterCardStyle.light => const Color(0xFFAEB3BC),
      PosterCardStyle.dark => const Color(0xFF0B0B0D),
      PosterCardStyle.glass => Colors.white.withValues(alpha: 0.28),
      PosterCardStyle.cover => const Color(0xB3000000),
    };
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // The farthest first; the card's own face over them.
        for (var i = _layers; i >= 1; i--)
          Positioned.fill(
            child: Transform(
              transform: Matrix4.translationValues(0, 0, thickness * i / _layers),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  // The edge darker towards the back.
                  color: Color.lerp(edge, Colors.black, i / _layers * 0.35),
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
            ),
          ),
        child,
      ],
    );
  }
}

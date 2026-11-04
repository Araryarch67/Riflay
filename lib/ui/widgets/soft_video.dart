import 'package:flutter/material.dart';

import '../../models/track.dart';
import 'video_mode.dart';

/// The song's music video, soft as if blurred, filling its box.
///
/// Not a blur filter, which would run on every video frame: the video is drawn at 1/[shrink] of the box and
/// stretched back with smooth filtering, which reads as a blur and costs almost nothing. With [from], it fades in
/// from that height down (0 is the top, 1 the foot), so the sharp video above shows through: the soft part sits
/// under the title and the controls.
class SoftVideo extends StatelessWidget {
  const SoftVideo({super.key, required this.track, this.shrink = 10, this.from});

  final Track track;
  final double shrink;
  final double? from;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      Widget soft = ClipRect(
        child: OverflowBox(
          maxWidth: double.infinity,
          maxHeight: double.infinity,
          child: Transform.scale(
            scale: shrink,
            filterQuality: FilterQuality.medium,
            child: SizedBox(
              width: box.maxWidth / shrink,
              height: box.maxHeight / shrink,
              child: VideoBackground(track: track),
            ),
          ),
        ),
      );
      final start = from;
      if (start != null) {
        // One mask over the soft copy only, so the controls read over a smooth picture.
        soft = ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: const [Colors.transparent, Colors.white],
            stops: [start, (start + 0.15).clamp(0, 1).toDouble()],
          ).createShader(rect),
          child: soft,
        );
      }
      return IgnorePointer(child: soft);
    },
  );
}

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/video_mode.dart';

void main() {
  test('the video is drawn no bigger than the biggest view showing it, its shape kept', () {
    // A 1440p video in a 600 × 600 cover: as wide as the cover, the height in proportion.
    expect(VideoMode.outputSizeFor(width: 2560, height: 1440, views: const [VideoBox(Size(600, 600))]), (600, 338));
    // Two views: the biggest decides.
    expect(
      VideoMode.outputSizeFor(
        width: 2560,
        height: 1440,
        views: const [VideoBox(Size(300, 300)), VideoBox(Size(1280, 900))],
      ),
      (1280, 720),
    );
    // A view near (or over) the video's own size, no view, or no size yet: the video's own.
    expect(VideoMode.outputSizeFor(width: 1280, height: 720, views: const [VideoBox(Size(1200, 700))]), isNull);
    expect(VideoMode.outputSizeFor(width: 1280, height: 720, views: const [VideoBox(Size(4000, 3000))]), isNull);
    expect(VideoMode.outputSizeFor(width: 1280, height: 720, views: const []), isNull);
    expect(VideoMode.outputSizeFor(width: 0, height: 0, views: const [VideoBox(Size(300, 300))]), isNull);
    // A background fills its box (cropped): the side the video falls short on decides. A 420 x 1400 side panel needs
    // the 1440p video 1400 tall, near its own: its own size.
    expect(
      VideoMode.outputSizeFor(width: 2560, height: 1440, views: const [VideoBox(Size(420, 1400), cover: true)]),
      isNull,
    );
    expect(VideoMode.outputSizeFor(width: 2560, height: 1440, views: const [VideoBox(Size(800, 400), cover: true)]), (
      800,
      450,
    ));
    // Even sides, never a sliver.
    final (w, h) = VideoMode.outputSizeFor(width: 1920, height: 1080, views: const [VideoBox(Size(5, 5))])!;
    expect((w.isEven, h.isEven, w >= 16, h >= 16), (true, true, true, true));
  });
}

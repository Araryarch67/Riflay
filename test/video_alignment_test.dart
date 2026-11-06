import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/video_alignment.dart';
import 'package:riflay/services/ytmusic_web.dart';

/// 75 s at 8 kHz of drum-like hits at random times (from [seed]), each a decaying burst of noise.
Float64List beats(int seed, {double seconds = 75}) {
  final random = math.Random(seed);
  final out = Float64List((seconds * 8000).round());
  var t = 0.0;
  while (t < seconds - 1) {
    t += 0.15 + random.nextDouble() * 0.5;
    final at = (t * 8000).round();
    final loud = 2000 + random.nextDouble() * 8000;
    for (var i = 0; i < 1200 && at + i < out.length; i++) {
      out[at + i] += loud * math.exp(-i / 250) * (random.nextDouble() * 2 - 1);
    }
  }
  return out;
}

/// [song] as another edit would have it: [lead] seconds of something else first, played at [speed].
Float64List edit(Float64List song, {double lead = 0, double speed = 1}) {
  final out = Float64List(song.length);
  final noise = math.Random(99);
  for (var i = 0; i < out.length; i++) {
    final source = (i / 8000 - lead) * speed * 8000;
    final j = source.round();
    out[i] = j >= 0 && j < song.length ? song[j] : 200 * (noise.nextDouble() * 2 - 1);
  }
  return out;
}

void main() {
  final song = beats(1);
  final onsets = VideoAlignment.onsets(song);

  test('a video with a longer intro is played that much further in', () {
    final a = VideoAlignment.align(onsets, VideoAlignment.onsets(edit(song, lead: 1.1)))!;
    expect(a.offset.inMilliseconds, closeTo(1100, 20));
    expect(a.rate, closeTo(1, 0.0005));
    final video = const MusicVideo(videoId: 'v').shifted(a.offset, a.rate);
    expect(video.videoTimeAt(const Duration(seconds: 30))!.inMilliseconds, closeTo(31100, 30));
  });

  test('a video that starts later in the song has nothing for its first moments', () {
    final a = VideoAlignment.align(onsets, VideoAlignment.onsets(edit(song, lead: -0.8)))!;
    expect(a.offset.inMilliseconds, closeTo(-800, 20));
    final video = const MusicVideo(videoId: 'v').shifted(a.offset, a.rate);
    expect(video.videoTimeAt(const Duration(milliseconds: 500)), isNull);
    expect(video.videoTimeAt(const Duration(seconds: 10))!.inMilliseconds, closeTo(9200, 30));
  });

  test('a slower master is followed as it slips', () {
    final a = VideoAlignment.align(onsets, VideoAlignment.onsets(edit(song, lead: 0.5, speed: 0.997)))!;
    // Video time t holds song time (t - 0.5) × 0.997: song time s sits at s / 0.997 + 0.5.
    expect(a.rate, closeTo(1 / 0.997, 0.0008));
    expect(a.offset.inMilliseconds, closeTo(500, 40));
  });

  test('two different songs give no answer', () {
    expect(VideoAlignment.align(onsets, VideoAlignment.onsets(beats(2))), isNull);
    expect(VideoAlignment.align(onsets, VideoAlignment.onsets(beats(3))), isNull);
  });

  test('the same timeline is nothing to move', () {
    expect(VideoAlignment.align(onsets, onsets)!.none, isTrue);
    expect(const MusicVideo(videoId: 'v').videoTimeAt(const Duration(seconds: 7)), const Duration(seconds: 7));
  });
}

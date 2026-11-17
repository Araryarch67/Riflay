import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/video_timing.dart';
import 'package:riflay/services/ytmusic_web.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final song = Track.youtube(videoId: 'song', title: 'Song', artist: 'Artist');
  final local = Track.fromUri(Uri.file('/music/song.flac'));
  const mv = MusicVideo(videoId: 'mv', offset: Duration(seconds: 15));
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    VideoTiming.clearCache();
  });

  test('earlier advances only the picture; later delays it', () async {
    final timing = VideoTiming.of(song, local, 'mv');
    await timing.ready;
    await timing.setShift(const Duration(milliseconds: -1500));
    expect(timing.videoTimeAt(mv, const Duration(seconds: 30)), const Duration(milliseconds: 46500));
    await timing.setShift(const Duration(seconds: 2));
    expect(timing.videoTimeAt(mv, const Duration(seconds: 30)), const Duration(seconds: 43));
    expect(timing.videoTimeAt(const MusicVideo(videoId: 'mv'), const Duration(seconds: 1)), isNull);
  });

  test('manual correction composes with lyric timing and the MV segment map', () async {
    final timing = VideoTiming.of(song, local, 'mv');
    await timing.ready;
    const mapped = MusicVideo(
      videoId: 'mv',
      segments: [
        VideoSegment(songStart: Duration.zero, videoStart: Duration(seconds: 15), length: Duration(seconds: 60)),
      ],
    );
    await timing.setShift(const Duration(seconds: -1));
    expect(
      timing.videoTimeAt(mapped, const Duration(seconds: 30), lyricsOffset: const Duration(seconds: 2)),
      const Duration(seconds: 48),
    );
    expect(timing.videoTimeAt(mapped, const Duration(seconds: 59), lyricsOffset: const Duration(seconds: 2)), isNull);
    await timing.setShift(Duration.zero);
    expect(
      timing.videoTimeAt(mapped, const Duration(seconds: 30), lyricsOffset: const Duration(seconds: 2)),
      const Duration(seconds: 47),
    );
  });

  test('rapid taps persist in order and survive a new session; reset removes the saved correction', () async {
    var timing = VideoTiming.of(song, local, 'mv');
    await timing.ready;
    await Future.wait([for (var i = 1; i <= 4; i++) timing.setShift(Duration(milliseconds: i * 500))]);
    VideoTiming.clearCache();
    timing = VideoTiming.of(song, local, 'mv');
    await timing.ready;
    expect(timing.value, const Duration(seconds: 2));
    await timing.setShift(Duration.zero);
    expect((await SharedPreferences.getInstance()).containsKey(timing.key), isFalse);
    VideoTiming.clearCache();
    timing = VideoTiming.of(song, local, 'mv');
    await timing.ready;
    expect(timing.value, Duration.zero);
  });

  test('audio sources, songs and MVs keep separate corrections', () async {
    final timing = VideoTiming.of(song, local, 'mv');
    await timing.ready;
    await timing.setShift(const Duration(seconds: 2));
    final others = [
      VideoTiming.of(song, song, 'mv'),
      VideoTiming.of(song, local, 'another-mv'),
      VideoTiming.of(Track.youtube(videoId: 'another', title: 'Other', artist: 'Artist'), local, 'mv'),
    ];
    for (final other in others) {
      await other.ready;
      expect(other.value, Duration.zero);
    }
    expect(VideoTiming.of(song, local, 'mv'), same(timing));
  });

  test('a pending preference load cannot overwrite a manual adjustment', () async {
    final timing = VideoTiming.of(song, local, 'mv');
    final write = timing.setShift(const Duration(seconds: -1));
    await timing.ready;
    await write;
    expect(timing.value, const Duration(seconds: -1));
  });
}

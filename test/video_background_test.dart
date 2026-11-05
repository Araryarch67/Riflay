import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/appearance.dart';
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/services/video_mode.dart';
import 'package:riflay/services/ytmusic_web.dart';
import 'package:riflay/ui/widgets/video_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final look = Appearance.instance;
  final song = Track.youtube(videoId: 'bgvideo', title: 'S', artist: 'A');
  final plain = Track.youtube(videoId: 'bgnone', title: 'P', artist: 'A');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await look.reset();
    await LayoutPrefs.instance.reset();
    VideoMode.instance
      ..setOn(false)
      ..debugSetFound('bgvideo', const MusicVideo(videoId: 'bgvideo'))
      ..debugSetFound('bgnone', null);
  });
  tearDown(() async {
    VideoMode.instance.setOn(false);
    await look.reset();
    await LayoutPrefs.instance.reset();
  });

  test('Music video persists, and is a plain choice with a short description', () async {
    await look.setNowPlaying(NowPlayingBackground.video);
    await look.load();
    expect(look.nowPlaying, NowPlayingBackground.video);
    expect(NowPlayingBackground.video.label, 'Music video');
    expect(NowPlayingBackground.video.hint, 'The song\'s music video, when it has one');
    await look.reset();
    expect(look.nowPlaying, NowPlayingBackground.color);
  });

  test('what is painted under the page: the blurred cover, or the plain colour in Lightweight', () {
    expect(NowPlayingBackground.video.effective(lightweight: false), NowPlayingBackground.blurredCover);
    expect(NowPlayingBackground.video.effective(lightweight: true), NowPlayingBackground.color);
    expect(NowPlayingBackground.black.effective(lightweight: true), NowPlayingBackground.black);
  });

  test('the video shows behind the page only for a song that has one', () {
    final mode = VideoMode.instance..setOn(true);
    expect(mode.showsAsBackground(song), isTrue);
    expect(mode.showsAsBackground(plain), isFalse);
    expect(mode.showsAsBackground(null), isFalse);
  });

  test('Song shows no video anywhere; Video lets it play behind the page', () {
    final mode = VideoMode.instance..setOn(false);
    expect(mode.showsAsBackground(song), isFalse);
    mode.setOn(true);
    expect(mode.showsAsBackground(song), isTrue);
    expect(mode.showsAsBackground(plain), isFalse, reason: 'a song without a video');
  });

  test('Lightweight draws no video', () async {
    VideoMode.instance.setOn(true);
    await LayoutPrefs.instance.setPerformance(PerformanceMode.lightweight);
    expect(VideoMode.instance.showsAsBackground(song), isFalse);
    await LayoutPrefs.instance.setPerformance(PerformanceMode.balanced);
    expect(VideoMode.instance.showsAsBackground(song), isTrue);
  });

  testWidgets('the background draws nothing until a video is playing, and holds nothing back', (tester) async {
    final controller = PlayerController();
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScope(
          controller: controller,
          child: VideoBackground(track: song),
        ),
      ),
    );
    await tester.pump();
    // Nothing is playing here, so no video loads: the page's blurred cover stays.
    expect(VideoMode.instance.backgroundController(song), isNull);
    expect(find.byType(SizedBox), findsWidgets);
    expect(VideoMode.instance.debugVideoState, isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });
}

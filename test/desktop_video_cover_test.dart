import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/services/video_mode.dart';
import 'package:riflay/services/ytmusic_web.dart';
import 'package:riflay/ui/widgets/video_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The desktop side panel's classic card is a bare [TrackVisual]: no Song / Video switch and no video background
/// beside it. It has to ask for the song's video itself, or the cover never turns into the music video.
void main() {
  final song = Track.youtube(videoId: 'deskvideo', title: 'S', artist: 'A');
  final plain = Track.youtube(videoId: 'desknone', title: 'P', artist: 'A');
  final asked = <String>[];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    asked.clear();
    VideoMode.debugLookUp = (id) async {
      asked.add(id);
      return id == 'deskvideo' ? const MusicVideo(videoId: 'deskvideo') : null;
    };
    // Marks this device as one that decodes video, whatever the test host is; no song is looked up by it.
    VideoMode.instance
      ..debugSetFound('unrelated', null)
      ..setOn(true);
  });
  tearDown(() => VideoMode.debugLookUp = null);

  Finder videoView() => find.byWidgetPredicate((w) => w.runtimeType.toString() == '_VideoView');

  Future<void> show(WidgetTester tester, Track track) async {
    // Nothing is playing, so no video player starts: only the lookup and the cover / video choice run.
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScope(
          controller: PlayerController(),
          child: Scaffold(
            body: SizedBox.square(
              dimension: 300,
              child: TrackVisual(track: track, cover: const Text('cover')),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a song with a music video asks for it and shows it in the cover\'s place', (tester) async {
    await show(tester, song);
    expect(asked, ['deskvideo']);
    expect(VideoMode.instance.videoOf(song)?.videoId, 'deskvideo');
    expect(videoView(), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('a song without one keeps its cover', (tester) async {
    await show(tester, plain);
    expect(asked, ['desknone']);
    expect(VideoMode.instance.videoOf(plain), isNull);
    expect(videoView(), findsNothing);
    expect(find.text('cover'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('Song picked: the cover stays, even for a song with a video', (tester) async {
    VideoMode.instance.setOn(false);
    await show(tester, song);
    expect(videoView(), findsNothing);
    expect(find.text('cover'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });
}

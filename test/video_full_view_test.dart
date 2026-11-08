import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/appearance.dart';
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/services/video_mode.dart';
import 'package:riflay/services/ytmusic_web.dart';
import 'package:riflay/ui/debug_switches.dart';
import 'package:riflay/ui/pages/queue_page.dart';
import 'package:riflay/ui/player/full_screen_player.dart' show windowFullScreen;
import 'package:riflay/ui/player/now_playing_page.dart';
import 'package:riflay/ui/player/video_full_view.dart';
import 'package:riflay/ui/shell_scope.dart';
import 'package:riflay/ui/widgets/controls.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _song = Track.youtube(videoId: 'full-view-test', title: 'Full view', artist: 'Artist');

class _Player extends PlayerController {
  bool playing = false;
  int toggles = 0;

  @override
  Track get currentTrack => _song;
  @override
  bool get canPlay => true;
  @override
  bool get showsPlaying => playing;
  @override
  Duration? get duration => const Duration(minutes: 3);
  @override
  Future<void> togglePlay() async {
    toggles++;
    playing = !playing;
    notifyListeners();
  }
}

const _portrait = Size(412, 915);
const _landscape = Size(915, 412);

void main() {
  /// What the view asked of the system: orientations and the system bars.
  final calls = <MethodCall>[];
  var queueOpened = 0;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LayoutPrefs.instance.reset();
    await Appearance.instance.setNowPlaying(NowPlayingBackground.color);
    VideoMode.instance
      ..setOn(true)
      ..debugSetFound(_song.videoId!, const MusicVideo(videoId: 'full-view-test'));
    calls.clear();
    queueOpened = 0;
  });
  tearDown(() async {
    VideoMode.instance.debugSetFound(_song.videoId!, null);
    await LayoutPrefs.instance.reset();
  });

  Future<_Player> show(WidgetTester tester, {Size size = _portrait}) async {
    SharedPreferences.setMockInitialValues({'library.v1': jsonEncode(<Object>[])});
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method.startsWith('SystemChrome.')) calls.add(call);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final c = _Player();
    await tester.runAsync(c.load);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      PlayerScope(
        controller: c,
        child: MaterialApp(
          home: ShellScope(
            compact: true,
            width: size.width,
            open: (_, {location}) {},
            openCollection: (_) {},
            openQueue: () => queueOpened++,
            openNowPlaying: () {},
            openLyrics: () {},
            openDownloads: () {},
            importFromYoutube: ({url}) {},
            addFiles: () {},
            addFolder: null,
            child: const NowPlayingPage(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    return c;
  }

  Future<void> close(WidgetTester tester, _Player c) async {
    await tester.pumpWidget(const SizedBox());
    // VideoMode lets go of its views a moment after they close.
    await tester.pump(const Duration(seconds: 3));
    await tester.runAsync(() async => c.dispose());
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Iterable<List<Object?>> orientations() => [
    for (final call in calls)
      if (call.method == 'SystemChrome.setPreferredOrientations') call.arguments as List<Object?>,
  ];

  testWidgets('the cover shows a full-screen button over the video, which opens it sideways with the bars hidden', (
    tester,
  ) async {
    final c = await show(tester);
    expect(find.byTooltip('Watch full screen'), findsOneWidget);
    await tester.tap(find.byTooltip('Watch full screen'));
    await settle(tester);
    expect(find.byType(VideoFullView), findsOneWidget);
    expect(orientations().last, ['DeviceOrientation.landscapeLeft', 'DeviceOrientation.landscapeRight']);
    expect(
      calls.where((c) => c.method == 'SystemChrome.setEnabledSystemUIMode').last.arguments,
      'SystemUiMode.immersiveSticky',
    );
    // Title and artist over the video.
    expect(find.descendant(of: find.byType(VideoFullView), matching: find.text('Full view')), findsOneWidget);
    expect(find.descendant(of: find.byType(VideoFullView), matching: find.text('Artist')), findsOneWidget);
    await close(tester, c);
  });

  testWidgets('a song without a video has no full-screen button, and neither does Song', (tester) async {
    VideoMode.instance.setOn(false);
    final c = await show(tester);
    expect(find.byTooltip('Watch full screen'), findsNothing);
    await close(tester, c);
  });

  testWidgets('the controls play, open the queue, hide after a few seconds and come back on a tap', (tester) async {
    final c = await show(tester);
    await tester.tap(find.byTooltip('Watch full screen'));
    await settle(tester);
    final view = find.byType(VideoFullView);
    Finder inView(Finder f) => find.descendant(of: view, matching: f);
    expect(inView(find.byType(SeekBar)), findsOneWidget);
    expect(inView(find.byType(TransportControls)), findsOneWidget);

    await tester.tap(inView(find.byTooltip('Play')));
    await tester.pump();
    expect(c.toggles, 1, reason: 'play / pause works over the video');
    await tester.tap(inView(find.byTooltip('Queue')));
    await tester.pump();
    expect(queueOpened, 1);

    await tester.pump(VideoFullView.controlsFor + const Duration(seconds: 1));
    await settle(tester);
    expect(inView(find.byType(SeekBar)), findsNothing, reason: 'hidden, and out of the tree: nothing ticks');
    expect(inView(find.byTooltip('Exit full screen')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('video-full-surface')));
    await settle(tester);
    expect(inView(find.byType(SeekBar)), findsOneWidget, reason: 'a tap brings them back');
    await close(tester, c);
  });

  testWidgets('closing goes back to Now Playing upright, the bars and the orientation as they were', (tester) async {
    final c = await show(tester);
    await tester.tap(find.byTooltip('Watch full screen'));
    await settle(tester);
    await tester.tap(find.byTooltip('Exit full screen'));
    await settle(tester);
    expect(find.byType(VideoFullView), findsNothing);
    expect(find.byType(NowPlayingPage), findsOneWidget);
    expect(find.byTooltip('Watch full screen'), findsOneWidget, reason: 'the cover as it was');
    expect(orientations().last, isEmpty, reason: 'back to what the app declares');
    // Both bars back (a manual mode is sent as the overlays to show).
    expect(calls.last.method, 'SystemChrome.setEnabledSystemUIOverlays');
    expect(calls.last.arguments, ['SystemUiOverlay.top', 'SystemUiOverlay.bottom']);

    // Back closes it too.
    await tester.tap(find.byTooltip('Watch full screen'));
    await settle(tester);
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.byType(VideoFullView), findsNothing);
    expect(find.byType(NowPlayingPage), findsOneWidget);
    await close(tester, c);
  });

  testWidgets('turning the phone sideways opens it, and upright again closes it', (tester) async {
    final c = await show(tester);
    tester.view.physicalSize = _landscape;
    await settle(tester);
    expect(find.byType(VideoFullView), findsOneWidget);
    expect(orientations(), isEmpty, reason: 'not locked: turning back must reach it');
    tester.view.physicalSize = _portrait;
    await settle(tester);
    expect(find.byType(VideoFullView), findsNothing);
    expect(find.byType(NowPlayingPage), findsOneWidget);
    await close(tester, c);
  });

  testWidgets('RIFLAY_NO_VIDEO_ROTATE leaves a sideways phone on Now Playing', (tester) async {
    DebugSwitches.noVideoRotate = true;
    addTearDown(() => DebugSwitches.noVideoRotate = false);
    final c = await show(tester);
    tester.view.physicalSize = _landscape;
    await settle(tester);
    expect(find.byType(VideoFullView), findsNothing);
    await close(tester, c);
  });

  group('on a computer', () {
    tearDown(() => windowFullScreen.value = false);
    final linux = TargetPlatformVariant.only(TargetPlatform.linux);

    /// The view opened from a button in a computer's window (no phone layout, a page history).
    Future<_Player> openOnComputer(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({'library.v1': jsonEncode(<Object>[])});
      final c = _Player();
      await tester.runAsync(c.load);
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        PlayerScope(
          controller: c,
          child: MaterialApp(
            home: ShellScope(
              compact: false,
              width: 1280,
              open: (_, {location}) {},
              openCollection: (_) {},
              openQueue: () => queueOpened++,
              openNowPlaying: () {},
              openLyrics: () {},
              openDownloads: () {},
              importFromYoutube: ({url}) {},
              addFiles: () {},
              addFolder: null,
              child: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(onPressed: () => openVideoFullView(context), child: const Text('open')),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await settle(tester);
      return c;
    }

    testWidgets('it fills the window, keeps the phone untouched, and the controls go with the pointer', (tester) async {
      final c = await openOnComputer(tester);
      expect(find.byType(VideoFullView), findsOneWidget);
      expect(orientations(), isEmpty, reason: 'a computer has no orientation to lock');
      expect(find.byType(SeekBar), findsOneWidget);
      expect(find.byTooltip('Close'), findsOneWidget);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: const Offset(640, 400));
      await tester.pump(VideoFullView.controlsFor + const Duration(seconds: 1));
      expect(find.byType(SeekBar), findsNothing, reason: 'gone after a few seconds without a move');
      final region = tester
          .widgetList<MouseRegion>(find.byType(MouseRegion))
          .firstWhere((r) => r.cursor == SystemMouseCursors.none, orElse: () => const MouseRegion());
      expect(region.cursor, SystemMouseCursors.none, reason: 'the pointer hides with them');

      await mouse.moveTo(const Offset(600, 380));
      await tester.pump();
      expect(find.byType(SeekBar), findsOneWidget, reason: 'a move brings them back');
      await close(tester, c);
    }, variant: linux);

    testWidgets('Queue opens beside the picture, inside the view', (tester) async {
      final c = await openOnComputer(tester);
      await tester.tap(find.byTooltip('Queue'));
      await settle(tester);
      expect(find.byType(QueuePage), findsOneWidget);
      expect(find.byType(VideoFullView), findsOneWidget, reason: 'the video stays');
      expect(queueOpened, 0, reason: 'not the page history under the view');
      await tester.tap(find.byTooltip('Queue'));
      await settle(tester);
      expect(find.byType(QueuePage), findsNothing);
      await close(tester, c);
    }, variant: linux);

    testWidgets('F11 fills the screen, Esc leaves it and then the view', (tester) async {
      final c = await openOnComputer(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.f11);
      await settle(tester);
      expect(windowFullScreen.value, isTrue);
      expect(find.byTooltip('Exit full screen'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(windowFullScreen.value, isFalse);
      expect(find.byType(VideoFullView), findsOneWidget, reason: 'the first Esc only leaves full screen');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(find.byType(VideoFullView), findsNothing);

      // Closed while full screen: the window comes back too.
      await tester.tap(find.text('open'));
      await settle(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.f11);
      await settle(tester);
      await tester.tap(find.byTooltip('Close'));
      await settle(tester);
      expect(windowFullScreen.value, isFalse);
      await close(tester, c);
    }, variant: linux);
  });
}

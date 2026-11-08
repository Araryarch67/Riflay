// Run in headless Weston with throwaway XDG_DATA_HOME (see AGENT.md):
// flutter test integration_test/native_video_linux_test.dart -d linux
// Requires ffmpeg to generate a local clip. No network or audio output.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:riflay/platform/native_video.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/services/video_mode.dart';
import 'package:riflay/ui/widgets/native_video_surface.dart';
import 'package:riflay/ui/widgets/video_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channel = MethodChannel('riflay/video_window');

Future<Map<Object?, Object?>> _status() async => (await _channel.invokeMapMethod<Object?, Object?>('status'))!;

class _VideoController extends PlayerController {
  _VideoController(this.track);
  Track track;
  @override
  Track get currentTrack => track;
  @override
  bool get isPlaying => true;
  @override
  bool get isBuffering => false;
  @override
  Duration get position => const Duration(seconds: 1);
  void select(Track next) {
    track = next;
    notifyListeners();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Linux native video renders, clips, hides for dialogs, and reattaches', (tester) async {
    final dir = await Directory.systemTemp.createTemp('riflay-native-video-');
    NativeVideoPlayer? player;
    final scroll = ScrollController();
    Future<Map<Object?, Object?>> waitStatus(bool Function(Map<Object?, Object?>) ready) async {
      final until = DateTime.now().add(const Duration(seconds: 5));
      var status = await _status();
      while (!ready(status) && DateTime.now().isBefore(until)) {
        await tester.pump(const Duration(milliseconds: 50));
        status = await _status();
      }
      expect(ready(status), isTrue, reason: '$status');
      return status;
    }

    try {
      final clip = '${dir.path}/clip.mp4';
      final generated = await Process.run('ffmpeg', [
        '-hide_banner',
        '-loglevel',
        'error',
        '-y',
        '-f',
        'lavfi',
        '-i',
        'testsrc2=size=640x360:rate=30',
        '-t',
        '12',
        '-c:v',
        'libx264',
        '-pix_fmt',
        'yuv420p',
        clip,
      ]);
      expect(generated.exitCode, 0, reason: '${generated.stderr}');
      expect(NativeVideoPlayer.available, isTrue);
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));

      Future<NativeVideoPlayer> open() async {
        final own = NativeVideoPlayer(
          window: await NativeVideoWindow.ensure(),
          hwdec: 'no',
          maxFps: 15,
          foreground: true,
        );
        player = own;
        await own.attach();
        await own.open(clip);
        // Opening while the surface is hidden must still decode the first frame.
        expect(await own.firstFrame(const Duration(seconds: 10)), isTrue);
        expect(own.aspect, closeTo(16 / 9, 0.01));
        return own;
      }

      final own = await open();
      final rejected = NativeVideoPlayer(window: 1, hwdec: 'no', foreground: true);
      try {
        await expectLater(rejected.attach(), throwsA(isA<PlatformException>()));
      } finally {
        // A failed attachment must not detach the player already on screen.
        await rejected.dispose();
      }
      expect((await _status())['attached'], true);
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                height: 180,
                child: ListView(
                  controller: scroll,
                  padding: EdgeInsets.zero,
                  children: [
                    NativeVideoSurface(key: key, child: const SizedBox(width: 320, height: 180)),
                    const SizedBox(height: 400),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await own.play();
      await tester.pump(const Duration(milliseconds: 600));
      var status = await waitStatus((s) => s['visible'] == true && (s['frames'] as int) > 0);
      expect(status['attached'], true);
      expect(status['visible'], true);
      expect(status['frames'], greaterThan(0));
      final firstFrames = status['frames'] as int;
      await tester.pump(const Duration(milliseconds: 400));
      expect((await _status())['frames'], greaterThan(firstFrames));
      expect(own.position, greaterThan(Duration.zero));

      await own.pause();
      await tester.pump(const Duration(milliseconds: 100));
      final paused = own.position;
      await tester.pump(const Duration(milliseconds: 300));
      expect((own.position - paused).inMilliseconds.abs(), lessThan(100));
      await own.seek(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 300));
      expect(own.position.inMilliseconds, closeTo(3000, 100));

      scroll.jumpTo(90);
      await tester.pump(const Duration(milliseconds: 200));
      status = await _status();
      expect(status['visible'], true);
      // Cropping does not change mpv's full render size/aspect ratio.
      final ratio = tester.view.devicePixelRatio;
      expect(status['width'], closeTo(320 * ratio, 1));
      expect(status['height'], closeTo(180 * ratio, 1));

      final dialog = showDialog<void>(
        context: key.currentContext!,
        builder: (_) => const AlertDialog(content: Text('Video surface test')),
      );
      await tester.pumpAndSettle();
      expect((await _status())['visible'], false);
      Navigator.of(key.currentContext!).pop();
      await dialog;
      await tester.pumpAndSettle();
      expect((await _status())['visible'], true);

      // Detach and replace at the same coordinates: placement cache must reset.
      await own.dispose();
      expect((await _status())['attached'], false);
      expect((await _status())['visible'], false);
      final next = await open();
      await tester.pump();
      await next.play();
      await tester.pump(const Duration(milliseconds: 300));
      await waitStatus((s) => s['visible'] == true && (s['frames'] as int) > 0);
      await next.dispose();
      player = null;
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    } finally {
      await player?.dispose();
      scroll.dispose();
      await dir.delete(recursive: true);
    }
  }, skip: !Platform.isLinux);

  testWidgets('Video mode coalesces duplicate starts and rapid song changes', (tester) async {
    final dir = await Directory.systemTemp.createTemp('riflay-video-mode-race-');
    _VideoController? c;
    final mode = VideoMode.instance;
    try {
      final first = '${dir.path}/first.mp4';
      final second = '${dir.path}/second.mp4';
      final generated = await Process.run('ffmpeg', [
        '-hide_banner',
        '-loglevel',
        'error',
        '-y',
        '-f',
        'lavfi',
        '-i',
        'testsrc2=size=640x360:rate=30',
        '-t',
        '12',
        '-c:v',
        'libx264',
        '-pix_fmt',
        'yuv420p',
        first,
      ]);
      expect(generated.exitCode, 0, reason: '${generated.stderr}');
      await File(first).copy(second);
      final a = Track.fromUri(Uri.file(first)), b = Track.fromUri(Uri.file(second));
      SharedPreferences.setMockInitialValues({'videoMode.on': true});
      final controller = c = _VideoController(a);
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerScope(
            controller: controller,
            child: Scaffold(
              body: ListenableBuilder(
                listenable: controller,
                builder: (_, _) => Center(
                  child: SizedBox(
                    width: 320,
                    height: 180,
                    child: TrackVisual(track: controller.currentTrack, cover: const SizedBox()),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      mode.setOn(true);
      // All three notifications can arrive before ensure/attach returns.
      controller.select(a);
      controller.select(a);
      controller.select(a);

      Future<void> ready() async {
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while (!mode.nativeReady && DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(mode.nativeReady, isTrue, reason: 'native initialization must not fall back after duplicate requests');
        expect(VideoMode.native, isTrue);
        expect(mode.notice, isNull);
        expect((await _status())['attached'], isTrue);
      }

      await ready();
      for (var i = 0; i < 3; i++) {
        controller.select(b);
        await tester.pump(const Duration(milliseconds: 1));
        controller.select(a);
        controller.select(b);
        controller.select(a);
        await ready();
      }
    } finally {
      mode.setOn(false);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
      c?.dispose();
      await dir.delete(recursive: true);
    }
  }, skip: !Platform.isLinux);
}

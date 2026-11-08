// Compare native GTK and Flutter texture video in the same profile binary.
// Run only in headless Weston with throwaway XDG_DATA_HOME (see AGENT.md).
// flutter build linux --profile -t tool/native_video_probe.dart
// RIFLAY_VIDEO_PROBE_FILE=/path/to/clip.mp4 RIFLAY_VIDEO_PROBE_BACKEND=native|texture
// RIFLAY_VIDEO_PROBE_HWDEC=no|auto-safe build/linux/x64/profile/bundle/riflay
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:riflay/platform/native_video.dart';
import 'package:riflay/ui/widgets/native_video_surface.dart';

int cpuTicks() {
  final fields = File('/proc/self/stat').readAsStringSync().split(') ').last.split(' ');
  return int.parse(fields[11]) + int.parse(fields[12]);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final file = Platform.environment['RIFLAY_VIDEO_PROBE_FILE']!;
  final native = Platform.environment['RIFLAY_VIDEO_PROBE_BACKEND'] != 'texture';
  final hwdec = Platform.environment['RIFLAY_VIDEO_PROBE_HWDEC'] ?? 'no';
  void show(Widget video) => runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(child: SizedBox(width: 640, height: 360, child: video)),
      ),
    ),
  );
  show(const SizedBox());
  await Future<void>.delayed(const Duration(milliseconds: 500));
  NativeVideoPlayer? own;
  Player? kit;
  if (native) {
    own = NativeVideoPlayer(window: await NativeVideoWindow.ensure(), hwdec: hwdec, foreground: true);
    await own.attach();
    await own.setProperty('loop-file', 'inf');
    await own.open(file);
    if (!await own.firstFrame(const Duration(seconds: 10))) throw StateError('No native video frame');
    show(const NativeVideoSurface(child: SizedBox()));
    await own.play();
  } else {
    MediaKit.ensureInitialized();
    kit = Player(configuration: const PlayerConfiguration(muted: true, bufferSize: 4 << 20));
    final controller = VideoController(kit, configuration: VideoControllerConfiguration(hwdec: hwdec));
    show(Video(controller: controller, controls: NoVideoControls));
    await (kit.platform as NativePlayer).setProperty('aid', 'no');
    await (kit.platform as NativePlayer).setProperty('loop-file', 'inf');
    await kit.open(Media(file));
    await controller.waitUntilFirstFrameRendered.timeout(const Duration(seconds: 10));
  }
  int frames = 0;
  void count(List<FrameTiming> timings) => frames += timings.length;
  SchedulerBinding.instance.addTimingsCallback(count);
  Future<void> measure(String state) async {
    await Future<void>.delayed(const Duration(seconds: 2));
    frames = 0;
    final ticks = cpuTicks();
    final clock = Stopwatch()..start();
    await Future<void>.delayed(const Duration(seconds: 6));
    final seconds = clock.elapsedMicroseconds / 1e6;
    final status = native ? await const MethodChannel('riflay/video_window').invokeMapMethod('status') : null;
    // FrameTiming may omit texture-only raster work; a zero count does not
    // establish that Flutter's raster thread is idle. CPU is the comparison.
    final result = <String, Object?>{
      'backend': native ? 'native' : 'texture',
      'state': state,
      'hwdec': hwdec,
      'decoderInUse': native
          ? await own!.getProperty('hwdec-current')
          : await (kit!.platform as NativePlayer).getProperty('hwdec-current'),
      'cpuOneCorePercent': (cpuTicks() - ticks) / seconds,
      'reportedFlutterFramesPerSecond': frames / seconds,
      'surface': ?status,
    };
    stdout.writeln('VIDEO_PROBE ${jsonEncode(result)}');
  }

  await measure('playing');
  await own?.pause();
  await kit?.pause();
  await measure('paused');
  SchedulerBinding.instance.removeTimingsCallback(count);
  await own?.dispose();
  await kit?.dispose();
  await stdout.flush();
  exit(0);
}

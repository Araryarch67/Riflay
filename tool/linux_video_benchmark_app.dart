// Full Riflay application on the normal binding, driven by benchmark_linux_video.py.
// Use a profile build in headless Weston, with isolated data/config/cache folders.
// This is a test driver without the live test binding's continuous frame loop.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:media_kit/media_kit.dart' show NativePlayer;
import 'package:riflay/main.dart' as app;
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/services/ui_beat.dart';
import 'package:riflay/services/video_mode.dart';
import 'package:riflay/ui/debug_switches.dart';
import 'package:riflay/ui/player_scope.dart';
import 'package:riflay/ui/shell_scope.dart';
import 'package:riflay/ui/widgets/page_scaffold.dart';
import 'package:window_manager/window_manager.dart';

int _cpuTicks() {
  final fields = File('/proc/self/stat').readAsStringSync().split(') ').last.split(' ');
  // Include completed child processes, like metadata helpers, as cpu_app.dart does.
  return [11, 12, 13, 14].fold(0, (sum, index) => sum + int.parse(fields[index]));
}

Map<String, double> _memory() {
  final text = File('/proc/self/smaps_rollup').readAsStringSync();
  int kb(String key) => int.parse(RegExp('^$key:\\s+(\\d+) kB', multiLine: true).firstMatch(text)!.group(1)!);
  return {
    'privateMiB': (kb('Private_Clean') + kb('Private_Dirty')) / 1024,
    'pssMiB': kb('Pss') / 1024,
    'rssMiB': kb('Rss') / 1024,
    'peakRssMiB': ProcessInfo.maxRss / (1 << 20),
  };
}

Element? _page() {
  Element? result;
  void visit(Element element) {
    if (result != null) return;
    if (element.widget is PageScaffold) {
      result = element;
    } else {
      element.visitChildren(visit);
    }
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return result;
}

/// CPU ticks so far per thread name (mpv's "mpv/…", "vo", Flutter's "io.flutter.…"), to tell where a phase's time
/// went.
Map<String, int> _threadTicks() {
  final out = <String, int>{};
  for (final t in Directory('/proc/self/task').listSync()) {
    try {
      final stat = File('${t.path}/stat').readAsStringSync();
      final name = stat.substring(stat.indexOf('(') + 1, stat.lastIndexOf(')'));
      final f = stat.split(') ').last.split(' ');
      out.update(
        name,
        (v) => v + int.parse(f[11]) + int.parse(f[12]),
        ifAbsent: () => int.parse(f[11]) + int.parse(f[12]),
      );
    } on FileSystemException {
      // The thread ended meanwhile.
    }
  }
  return out;
}

Future<void> _until(bool Function() ready, String description, {int seconds = 40}) async {
  final deadline = DateTime.now().add(Duration(seconds: seconds));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) throw TimeoutException(description);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

Future<void> main() async {
  try {
    // Numbers only from a profile build; a debug one only to print frame stacks (RIFLAY_BENCH_STACKS).
    final stacksOnly = kDebugMode && Platform.environment.containsKey('RIFLAY_BENCH_STACKS');
    if (!(kProfileMode || stacksOnly) || !Platform.isLinux) throw StateError('Run a Linux profile build');
    final env = Platform.environment;
    final backend = env['RIFLAY_BENCH_BACKEND']!;
    final sampleSeconds = int.parse(env['RIFLAY_BENCH_SAMPLE_SECONDS'] ?? '10');
    final settleSeconds = int.parse(env['RIFLAY_BENCH_SETTLE_SECONDS'] ?? '4');
    DebugSwitches.noNativeVideo = backend == 'texture';
    await app.main(const []);
    await windowManager.setSize(const Size(1280, 800));
    await _until(() => _page() != null, 'The main application did not open');
    final c = PlayerScope.read(_page()!);
    await _until(() => !c.scanning, 'Library scan did not finish');
    await c.audio.setDevice('pipewire/${env['RIFLAY_BENCH_SINK']!}');
    await c.setVolume(0); // Remain muted until the actual output has been verified.
    WidgetsBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final mode = VideoMode.instance;
    var timings = 0;
    void count(List<FrameTiming> frames) => timings += frames.length;
    SchedulerBinding.instance.addTimingsCallback(count);

    Future<Map<Object?, Object?>?> surface() async => backend == 'native'
        ? await const MethodChannel('riflay/video_window').invokeMapMethod<Object?, Object?>('status')
        : null;

    Future<void> measure(String phase, {int? settle}) async {
      await Future<void>.delayed(Duration(seconds: settle ?? settleSeconds));
      final memoryBefore = _memory();
      final nativeBefore = await surface();
      final audioPositionBefore = c.position.inMilliseconds;
      final videoPositionBefore = mode.debugVideoState?.position.inMilliseconds;
      timings = 0;
      // A debug build with RIFLAY_BENCH_STACKS: who asks for frames in this phase (the first two seconds).
      if (env['RIFLAY_BENCH_STACKS'] == phase) {
        stdout.writeln('STACKS $phase');
        debugPrintScheduleFrameStacks = true;
        Timer(const Duration(seconds: 2), () => debugPrintScheduleFrameStacks = false);
      }
      final ticks = _cpuTicks();
      final threadsBefore = _threadTicks();
      final clock = Stopwatch()..start();
      await Future<void>.delayed(Duration(seconds: sampleSeconds));
      final used = _cpuTicks() - ticks;
      final seconds = clock.elapsedMicroseconds / 1e6;
      final cpu = used / seconds; // Linux USER_HZ = 100; this is percent of one core.
      final audioPlatform = JustAudioMediaKit.activePlayer?.platform;
      final result = <String, Object?>{
        'phase': phase,
        'mode': LayoutPrefs.instance.performance.name,
        'backend': backend,
        'run': int.parse(env['RIFLAY_BENCH_RUN']!),
        'sampleSeconds': seconds,
        'logicalProcessors': Platform.numberOfProcessors,
        'cpuOneCorePercent': cpu,
        'cpuTotalPercent': cpu / Platform.numberOfProcessors,
        'memoryBefore': memoryBefore,
        'memoryAfter': _memory(),
        // FrameTiming does not necessarily include texture-only raster work.
        'reportedFrameTimingsPerSecond': timings / seconds,
        'uiBeatListeners': UiBeat.listeners,
        'lifecycle': WidgetsBinding.instance.lifecycleState?.name,
        'audioPlaying': c.isPlaying,
        'audioPositionStartMs': audioPositionBefore,
        'audioPositionEndMs': c.position.inMilliseconds,
        'videoPositionStartMs': videoPositionBefore,
        'videoPositionEndMs': mode.debugVideoState?.position.inMilliseconds,
        'videoPlaying': mode.debugVideoState?.playing,
        'nativeReady': mode.nativeReady,
        'textureReady': mode.controller != null,
        'decoderInUse': mode.decoderInUse,
        'surfaceBefore': ?nativeBefore,
        'surfaceAfter': ?await surface(),
        'windowPhysicalSize': {
          'width': WidgetsBinding.instance.platformDispatcher.views.first.physicalSize.width,
          'height': WidgetsBinding.instance.platformDispatcher.views.first.physicalSize.height,
        },
        'devicePixelRatio': WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio,
        'audioOutput': audioPlatform is NativePlayer ? await audioPlatform.getProperty('current-ao') : null,
        'audioDevice': audioPlatform is NativePlayer ? await audioPlatform.getProperty('audio-device') : null,
        'visualizerActive': c.audio.visualizerActive,
        // The busiest threads, % of one core each.
        'threads': () {
          final after = _threadTicks();
          final busy = {for (final e in after.entries) e.key: (e.value - (threadsBefore[e.key] ?? 0)) / seconds};
          final top = busy.entries.where((e) => e.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
          return {for (final e in top.take(8)) e.key: double.parse(e.value.toStringAsFixed(2))};
        }(),
      };
      stdout.writeln('BENCH ${jsonEncode(result)}');
      await stdout.flush();
    }

    await measure('idle_home', settle: 12);
    final audioTrack = c.library.singleWhere((track) => track.path == env['RIFLAY_BENCH_AUDIO']);
    await c.playList([audioTrack], 0);
    ShellScope.of(_page()!).openNowPlaying();
    await _until(() => c.isPlaying && c.position > const Duration(milliseconds: 200), 'Audio did not play');
    final audio = JustAudioMediaKit.activePlayer!.platform as NativePlayer;
    if (await audio.getProperty('current-ao') != 'pipewire' ||
        await audio.getProperty('audio-device') != 'pipewire/${env['RIFLAY_BENCH_SINK']!}') {
      await c.pause();
      throw StateError('Audio did not open the requested silent PipeWire sink');
    }
    // The visualizer now receives unmuted samples; the temporary sink discards
    // them rather than sending sound to the user's speakers.
    await c.setVolume(1);
    await measure('audio_playing');

    final video = c.library.singleWhere((track) => track.path == env['RIFLAY_BENCH_VIDEO']);
    await c.playList([video], 0);
    mode.setOn(true);
    await _until(
      () => c.isPlaying && (backend == 'native' ? mode.nativeReady : mode.controller != null),
      'Requested video backend did not become ready',
    );
    await measure('video_playing');
    await c.pause();
    await measure('video_paused');

    await c.play();
    WidgetsBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    // Linux releases the unfocused video after 20 seconds; verify that state,
    // instead of comparing a still-allocated texture with a released renderer.
    await _until(() => mode.debugVideoState == null, 'Unfocused video was not released', seconds: 30);
    await measure('video_unfocused_released');
    SchedulerBinding.instance.removeTimingsCallback(count);
    await stdout.flush();
    exit(0);
  } catch (error, stack) {
    stderr.writeln('BENCH_ERROR $error\n$stack');
    exit(1);
  }
}

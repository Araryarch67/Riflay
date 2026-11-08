// Full-app controlled experiments. Driven by investigate_linux_cpu.py in an
// isolated profile checkout; the copied main.dart supplies a diagnostic UI gate.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:media_kit/media_kit.dart' show NativePlayer;
import 'package:riflay/main.dart' as app;
import 'package:riflay/services/appearance.dart';
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/services/ui_beat.dart';
import 'package:riflay/services/video_mode.dart';
import 'package:riflay/ui/shell_scope.dart';
import 'package:riflay/ui/widgets/page_scaffold.dart';
import 'package:window_manager/window_manager.dart';

class _Rpc {
  _Rpc(this.socket) {
    socket.listen((data) {
      final message = jsonDecode(data as String) as Map<String, dynamic>;
      final pending = _pending.remove(message['id']);
      if (pending == null) return;
      if (message.containsKey('error')) {
        pending.completeError(StateError('${message['error']}'));
      } else {
        pending.complete((message['result'] as Map).cast<String, dynamic>());
      }
    });
  }
  final WebSocket socket;
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  int _id = 0;
  Future<Map<String, dynamic>> call(String method, [Map<String, Object?> params = const {}]) {
    final id = ++_id;
    final response = Completer<Map<String, dynamic>>();
    _pending[id] = response;
    socket.add(jsonEncode({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params}));
    return response.future.timeout(const Duration(seconds: 20));
  }
}

Map<int, ({String name, int ticks, int user, int system})> _threads() {
  final out = <int, ({String name, int ticks, int user, int system})>{};
  for (final entry in Directory('/proc/self/task').listSync()) {
    try {
      final text = File('${entry.path}/stat').readAsStringSync();
      final fields = text.split(') ').last.split(' ');
      out[int.parse(entry.path.split('/').last)] = (
        name: text.substring(text.indexOf('(') + 1, text.lastIndexOf(')')),
        ticks: int.parse(fields[11]) + int.parse(fields[12]),
        user: int.parse(fields[11]),
        system: int.parse(fields[12]),
      );
    } on FileSystemException {
      // A short-lived worker exited during the snapshot.
    }
  }
  return out;
}

int _cpuTicks() {
  final fields = File('/proc/self/stat').readAsStringSync().split(') ').last.split(' ');
  return [11, 12, 13, 14].fold(0, (sum, i) => sum + int.parse(fields[i]));
}

Element? _page() {
  Element? result;
  void visit(Element e) {
    if (result != null) return;
    if (e.widget is PageScaffold) {
      result = e;
    } else {
      e.visitChildren(visit);
    }
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return result;
}

Future<void> _until(bool Function() ready, String message) async {
  final deadline = DateTime.now().add(const Duration(seconds: 40));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) throw TimeoutException(message);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

Future<void> main() async {
  try {
    if (!kProfileMode) throw StateError('Profile mode required');
    final env = Platform.environment;
    final out = Directory(env['RIFLAY_PROFILE_OUTPUT']!)..createSync(recursive: true);
    await app.main(const []);
    await windowManager.setSize(const Size(1280, 800));
    await _until(() => _page() != null, 'Application did not open');
    final c = PlayerScope.read(_page()!);
    await _until(() => !c.scanning, 'Scan did not finish');
    await c.audio.setDevice('pipewire/${env['RIFLAY_BENCH_SINK']}');
    await c.setVolume(0);
    WidgetsBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final track = c.library.singleWhere((t) => t.path == env['RIFLAY_PROFILE_MEDIA']);
    await c.playList([track], 0);
    ShellScope.of(_page()!).openNowPlaying();
    await _until(() => c.isPlaying && c.position.inMilliseconds > 200, 'Audio did not start');
    final mpv = JustAudioMediaKit.activePlayer!.platform as NativePlayer;
    if (await mpv.getProperty('audio-device') != 'pipewire/${env['RIFLAY_BENCH_SINK']}') {
      await c.pause();
      throw StateError('Incorrect audio output');
    }
    await c.setVolume(1);
    final service = (await developer.Service.getInfo()).serverUri!;
    final rpc = _Rpc(await WebSocket.connect(service.replace(scheme: 'ws', path: '${service.path}ws').toString()));
    final vm = await rpc.call('getVM');
    final isolate = (vm['isolates'] as List).cast<Map>().firstWhere((i) => i['name'] == 'main')['id'] as String;
    final video = VideoMode.instance;
    final prefs = LayoutPrefs.instance;
    final look = Appearance.instance;
    final originalBlur = look.blur;
    var frames = 0;
    var buildUs = 0, rasterUs = 0;
    void count(List<FrameTiming> timings) {
      frames += timings.length;
      for (final timing in timings) {
        buildUs += timing.buildDuration.inMicroseconds;
        rasterUs += timing.rasterDuration.inMicroseconds;
      }
    }

    SchedulerBinding.instance.addTimingsCallback(count);
    const controls = [
      'audio_full',
      'audio_no_visualizer',
      'audio_no_visualizer_no_motion',
      'audio_ticker_off_meter_on',
      'audio_ticker_off_meter_off',
      'video_native_full',
      'video_native_no_visualizer',
      'video_native_no_motion',
      'video_native_no_motion_no_blur',
    ];
    final cases = [
      for (var run = 1; run <= 2; run++)
        for (final name in run == 1 ? controls : controls.reversed) (name: name, run: run, profile: false),
      (name: 'audio_full', run: 3, profile: true),
      (name: 'video_native_full', run: 3, profile: true),
    ];
    await Future<void>.delayed(const Duration(seconds: 10));
    for (final experiment in cases) {
      final name = experiment.name;
      await c.pause();
      video.setOn(false);
      await _until(() => video.debugVideoState == null, 'Previous video did not stop');
      final tickerOff = name.contains('ticker_off');
      final noMotion = name.contains('no_motion');
      final noVisualizer = name.contains('no_visualizer');
      await prefs.setMotion(noMotion ? Motion.off : Motion.full);
      await prefs.setVisualizer(!noVisualizer);
      await look.setBlur(name.contains('no_blur') ? 0 : originalBlur);
      await rpc.call('ext.riflay.profile.ui', {'isolateId': isolate, 'enabled': !tickerOff ? 'true' : 'false'});
      await c.seek(const Duration(seconds: 5));
      await c.play();
      final release = name == 'audio_ticker_off_meter_on' ? c.audio.watchVisualizer() : null;
      if (name.startsWith('video_')) {
        video.setOn(true);
        await _until(() => video.nativeReady, 'Native backend did not start');
      }
      await Future<void>.delayed(const Duration(seconds: 6));
      if (experiment.profile) await rpc.call('setFlag', {'name': 'profiler', 'value': 'true'});
      await rpc.call('clearCpuSamples', {'isolateId': isolate});
      final origin = (await rpc.call('getVMTimelineMicros'))['timestamp'] as int;
      final ready = {'case': name, 'run': experiment.run, 'profile': experiment.profile, 'pid': pid};
      stdout.writeln('PROFILE_READY ${jsonEncode(ready)}');
      await stdout.flush();
      // The native sampling pass is separate from the comparative CPU runs.
      if (experiment.profile) await Future<void>.delayed(const Duration(seconds: 1));
      frames = buildUs = rasterUs = 0;
      final before = _threads();
      final cpu = _cpuTicks();
      final clock = Stopwatch()..start();
      await Future<void>.delayed(const Duration(seconds: 12));
      final delta = _cpuTicks() - cpu;
      final seconds = clock.elapsedMicroseconds / 1e6;
      final after = _threads();
      final threads = <Map<String, Object?>>[
        for (final entry in after.entries)
          {
            'tid': entry.key,
            'name': entry.value.name,
            'cpuOneCorePercent': (entry.value.ticks - (before[entry.key]?.ticks ?? 0)) / seconds,
            'userOneCorePercent': (entry.value.user - (before[entry.key]?.user ?? 0)) / seconds,
            'systemOneCorePercent': (entry.value.system - (before[entry.key]?.system ?? 0)) / seconds,
          },
      ]..sort((a, b) => (b['cpuOneCorePercent'] as double).compareTo(a['cpuOneCorePercent'] as double));
      final result = <String, Object?>{
        ...ready,
        'seconds': seconds,
        'cpuOneCorePercent': delta / seconds,
        'cpuTotalPercent': delta / seconds / Platform.numberOfProcessors,
        'threads': threads,
        'reportedFrameTimingsPerSecond': frames / seconds,
        'averageBuildMs': frames == 0 ? 0 : buildUs / frames / 1000,
        'averageRasterMs': frames == 0 ? 0 : rasterUs / frames / 1000,
        'uiBeatListeners': UiBeat.listeners,
        'visualizerActive': c.audio.visualizerActive,
        'nativeReady': video.nativeReady,
        'decoder': video.decoderInUse,
        'positionMs': c.position.inMilliseconds,
      };
      stdout.writeln('PROFILE_RESULT ${jsonEncode(result)}');
      await stdout.flush();
      if (experiment.profile)
        try {
          final cpuSamples = await rpc.call('getCpuSamples', {
            'isolateId': isolate,
            'timeOriginMicros': origin,
            'timeExtentMicros': clock.elapsedMicroseconds + 2000000,
          });
          File('${out.path}/dart-$name-${experiment.run}.json').writeAsStringSync(jsonEncode(cpuSamples));
        } catch (error) {
          stderr.writeln('PROFILE_DART_ERROR $error');
        }
      release?.call();
    }
    await c.pause();
    SchedulerBinding.instance.removeTimingsCallback(count);
    await rpc.socket.close();
    await stdout.flush();
    exit(0);
  } catch (error, stack) {
    stderr.writeln('PROFILE_ERROR $error\n$stack');
    exit(1);
  }
}

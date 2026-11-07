// The real app, started as it always is (WidgetsFlutterBinding, no test
// binding), then made to play a song from the library tool/cpu.sh seeded, and
// measured: CPU time of the whole process (UI, raster, mpv, every thread) and
// the frames it drew, on Home, Now Playing, playing and paused.
//
// integration_test/cpu_test.dart can't see a view that keeps redrawing an idle
// window: the live test binding asks for a frame after every frame. This can.
// Run it through tool/cpu.sh (profile build, headless Weston, a throwaway data
// folder). Prints "CPU ..." lines and exits.
import 'dart:async';
import 'dart:io';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:riflay/main.dart' as app;
import 'package:riflay/services/ui_beat.dart';
import 'package:riflay/ui/player_scope.dart';
import 'package:riflay/ui/shell_scope.dart';
import 'package:riflay/ui/widgets/page_scaffold.dart';

/// User + system CPU time of this process and its waited-for children so far, from /proc.
Duration _cpuTime() {
  final fields = File('/proc/self/stat').readAsStringSync().split(') ').last.split(' ');
  // utime, stime, cutime, cstime: fields 14-17 of the whole line; 12-15 after "pid (comm) ".
  var ticks = 0;
  for (var i = 11; i <= 14; i++) {
    ticks += int.parse(fields[i]);
  }
  return Duration(microseconds: ticks * 1000000 ~/ 100); // USER_HZ is 100 on Linux
}

/// Each thread's name and CPU ticks so far (1 tick = 10 ms), by thread id.
Map<String, (String, int)> _threadTicks() {
  final out = <String, (String, int)>{};
  for (final t in Directory('/proc/self/task').listSync()) {
    try {
      final stat = File('${t.path}/stat').readAsStringSync();
      final name = stat.substring(stat.indexOf('(') + 1, stat.lastIndexOf(')'));
      final f = stat.split(') ').last.split(' ');
      out[t.path] = (name, int.parse(f[11]) + int.parse(f[12]));
    } on FileSystemException {
      // The thread ended meanwhile.
    }
  }
  return out;
}

/// A debug build only: prints what asks for frames for a moment, and every running ticker with where it sits.
Future<void> _whoDraws({bool long = false}) async {
  await Future<void>.delayed(const Duration(seconds: 3));
  stdout.writeln('STACKS from here');
  debugPrintScheduleFrameStacks = true;
  await Future<void>.delayed(Duration(milliseconds: long ? 3000 : 300));
  debugPrintScheduleFrameStacks = false;
  void visit(Element e) {
    if (e is StatefulElement) {
      final d = e.state.toString();
      if (d.contains('tick') && !d.contains('ticker inactive') && !d.contains('tracking 0 ticker')) {
        final chain = <String>[];
        e.visitAncestorElements((a) {
          if (chain.length < 10) chain.add('${a.widget.runtimeType}');
          return true;
        });
        stdout.writeln('TICKER $d <- ${chain.join(' < ')}');
      }
    }
    e.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
}

/// CPU ticks so far of the system's audio server (PipeWire, or PulseAudio), which plays what the app sends: its
/// cost is the app's doing too, so it is measured alongside. Null when none runs.
int? _audioServerTicks() {
  var total = 0;
  var found = false;
  for (final d in Directory('/proc').listSync()) {
    final pid = d.path.split('/').last;
    if (int.tryParse(pid) == null) continue;
    try {
      final comm = File('${d.path}/comm').readAsStringSync().trim();
      if (comm != 'pipewire' && comm != 'pipewire-pulse' && comm != 'pulseaudio') continue;
      final f = File('${d.path}/stat').readAsStringSync().split(') ').last.split(' ');
      total += int.parse(f[11]) + int.parse(f[12]);
      found = true;
    } on FileSystemException {
      // Gone, or not ours to read.
    }
  }
  return found ? total : null;
}

Element? _find(bool Function(Element) test) {
  Element? found;
  void visit(Element e) {
    if (found != null) return;
    if (test(e)) {
      found = e;
      return;
    }
    e.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return found;
}

Future<void> main() async {
  final songs = Platform.environment['RIFLAY_CPU_SONGS'] ?? '';
  final settle = Duration(seconds: int.parse(Platform.environment['RIFLAY_CPU_SETTLE'] ?? '4'));
  final window = Duration(seconds: int.parse(Platform.environment['RIFLAY_CPU_WINDOW'] ?? '15'));
  await app.main(const []);

  var frames = 0;
  var build = Duration.zero, raster = Duration.zero;
  SchedulerBinding.instance.addTimingsCallback((timings) {
    frames += timings.length;
    for (final t in timings) {
      build += t.buildDuration;
      raster += t.rasterDuration;
    }
  });
  Element? page;
  while ((page = _find((e) => e.widget is PageScaffold)) == null) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  final c = PlayerScope.read(page!);
  while (c.scanning) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  Future<void> measure(String label) async {
    await Future<void>.delayed(settle);
    frames = 0;
    build = raster = Duration.zero;
    final cpu = _cpuTime();
    final threads = _threadTicks();
    final server = _audioServerTicks();
    final clock = Stopwatch()..start();
    await Future<void>.delayed(window);
    final used = _cpuTime() - cpu;
    final pct = used.inMicroseconds / clock.elapsedMicroseconds * 100;
    final fps = frames / (clock.elapsedMilliseconds / 1000);
    String per(Duration d) => frames == 0 ? '-' : (d.inMicroseconds / frames / 1000).toStringAsFixed(2);
    stdout.writeln(
      'CPU $label: ${pct.toStringAsFixed(2)}% of one core, ${fps.toStringAsFixed(1)} frames/s '
      '(build ${per(build)} ms, raster ${per(raster)} ms a frame), ${UiBeat.listeners} on the beat',
    );
    // The busiest threads (by name: mpv's are "mpv/…", "ao/…", Flutter's "io.flutter.…").
    final after = _threadTicks();
    final busy = <String, int>{};
    for (final MapEntry(key: id, value: (name, ticks)) in after.entries) {
      busy.update(name, (v) => v + ticks - (threads[id]?.$2 ?? 0), ifAbsent: () => ticks - (threads[id]?.$2 ?? 0));
    }
    final top = busy.entries.where((e) => e.value > 0).toList()..sort((a, b) => b.value - a.value);
    final seconds = clock.elapsedMilliseconds / 1000;
    final serverNow = _audioServerTicks();
    if (server != null && serverNow != null) {
      stdout.writeln('CPU   audio server (outside the app) ${((serverNow - server) / seconds).toStringAsFixed(2)}%');
    }
    stdout.writeln(
      'CPU   ${[for (final e in top.take(6)) '${e.key} ${(e.value / seconds).toStringAsFixed(2)}%'].join(', ')}',
    );
  }

  // Headless Weston has no keyboard, so the window never gets the focus: say it has, as on a desktop where someone
  // is looking at it. "unfocused" below is another window having the focus.
  stdout.writeln('CPU (the embedder reported ${WidgetsBinding.instance.lifecycleState}; measured as resumed)');
  WidgetsBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await measure('idle, Home');
  final queue = [
    for (final t in c.library)
      if (t.path?.startsWith(songs) ?? false) t,
  ];
  await c.playList(queue, 0);
  if (Platform.environment['RIFLAY_CPU_STACKS'] == 'true') await _whoDraws();
  await measure('playing, Home');
  final stacks = Platform.environment['RIFLAY_CPU_STACKS'] == 'true';
  // From the pause on, so what starts a ticker then shows in its stack.
  if (stacks) {
    stdout.writeln('STACKS from here');
    debugPrintScheduleFrameStacks = true;
  }
  await c.pause();
  if (stacks) await _whoDraws(long: true);
  await measure('paused, Home');
  await c.play();
  ShellScope.of(_find((e) => e.widget is PageScaffold)!).openNowPlaying();
  await measure('playing, Now Playing');
  WidgetsBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  await measure('playing, Now Playing, unfocused');
  WidgetsBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await c.pause();
  await measure('paused, Now Playing');
  exit(0);
}

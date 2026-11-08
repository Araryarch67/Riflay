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
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';

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
Future<void> _whoDraws({bool long = false, Duration wait = const Duration(seconds: 3)}) async {
  await Future<void>.delayed(wait);
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

/// The UI isolate's CPU samples between [from] and [to] (the VM clock, µs), from its VM service: the functions that
/// were running most (self) and the ones most often on the stack (total), in % of the samples.
/// Turns the VM's sampling profiler on (a profile build starts with it off), so [_dartProfile] has samples.
Future<void> _startProfiler() async {
  final uri = (await developer.Service.getInfo()).serverWebSocketUri;
  if (uri == null) return;
  final socket = await WebSocket.connect(uri.toString());
  socket.add(
    jsonEncode({
      'jsonrpc': '2.0',
      'id': 'p',
      'method': 'setFlag',
      'params': {'name': 'profiler', 'value': 'true'},
    }),
  );
  stdout.writeln('CPU profiler: ${(await socket.map((m) => jsonDecode(m as String)).first)}');
  await socket.close();
}

Future<String> _dartProfile(int from, int to) async {
  final uri = (await developer.Service.getInfo()).serverWebSocketUri;
  if (uri == null) return 'no VM service (a profile build has it)';
  final socket = await WebSocket.connect(uri.toString());
  final replies = socket.map((m) => jsonDecode(m as String) as Map<String, dynamic>).asBroadcastStream();
  try {
    socket.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': '1',
        'method': 'getCpuSamples',
        'params': {
          'isolateId': developer.Service.getIsolateId(Isolate.current),
          'timeOriginMicros': from,
          'timeExtentMicros': to - from,
        },
      }),
    );
    final reply = await replies.firstWhere((m) => m['id'] == '1');
    final r = reply['result'] as Map<String, dynamic>?;
    if (r == null) return 'VM service: ${reply['error']}';
    final functions = [
      for (final f in (r['functions'] as List).cast<Map<String, dynamic>>())
        () {
          final fn = f['function'] as Map<String, dynamic>;
          final owner = (fn['owner'] as Map?)?['name'];
          return owner == null ? '${fn['name']}' : '$owner.${fn['name']}';
        }(),
    ];
    final samples = (r['samples'] as List).cast<Map<String, dynamic>>();
    final self = <String, int>{}, total = <String, int>{};
    for (final s in samples) {
      final stack = (s['stack'] as List).cast<int>();
      if (stack.isEmpty) continue;
      self.update(functions[stack.first], (v) => v + 1, ifAbsent: () => 1);
      for (final name in {for (final i in stack) functions[i]}) {
        total.update(name, (v) => v + 1, ifAbsent: () => 1);
      }
    }
    String top(Map<String, int> m, int n) {
      final e = m.entries.toList()..sort((a, b) => b.value - a.value);
      return [for (final x in e.take(n)) '${x.key} ${(x.value * 100 / samples.length).round()}%'].join(', ');
    }

    return '${samples.length} samples\nCPU   self: ${top(self, 15)}\nCPU   total: ${top(total, 40)}';
  } finally {
    await socket.close();
  }
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

  /// CPU (share of one core) and frames in each 100 ms for [length], from [start] on: how a moment like opening a
  /// page spikes, which a 15 s average hides.
  Future<void> slices(String label, Duration length, void Function() start) async {
    final out = <String>[];
    var peak = 0.0;
    var frameCount = 0;
    final from = developer.Timeline.now;
    final threads = _threadTicks();
    int switches() {
      final status = File('/proc/self/status').readAsStringSync();
      int field(String n) => int.parse(RegExp('^$n:\\s+(\\d+)', multiLine: true).firstMatch(status)![1]!);
      return field('voluntary_ctxt_switches') + field('nonvoluntary_ctxt_switches');
    }

    final wakes = switches();
    start();
    final clock = Stopwatch()..start();
    var cpu = _cpuTime();
    var last = Duration.zero;
    frames = 0;
    build = raster = Duration.zero;
    while (clock.elapsed < length) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final now = _cpuTime(), at = clock.elapsed;
      final pct = (now - cpu).inMicroseconds / (at - last).inMicroseconds * 100;
      peak = pct > peak ? pct : peak;
      out.add('${pct.round()}${frames > 0 ? '/$frames' : ''}');
      frameCount += frames;
      cpu = now;
      last = at;
      frames = 0;
    }
    stdout.writeln('CPU $label: peak ${peak.round()}% of one core; every 100 ms (% / frames): ${out.join(' ')}');
    stdout.writeln(
      'CPU   frames: $frameCount (build ${(build.inMicroseconds / 1000).toStringAsFixed(0)} ms, '
      'raster ${(raster.inMicroseconds / 1000).toStringAsFixed(0)} ms in all)',
    );
    final busy = <String, int>{};
    stdout.writeln(
      'CPU   main thread woke ${((switches() - wakes) / clock.elapsedMilliseconds * 1000).round()} times a second',
    );
    final self = '/proc/self/task/$pid';
    for (final MapEntry(key: id, value: (name, ticks)) in _threadTicks().entries) {
      final d = ticks - (threads[id]?.$2 ?? 0);
      // The main thread (Flutter's UI and GTK) apart from the threads that share its name.
      final key = name == 'riflay' && id != self ? 'riflay#${id.split('/').last}' : name;
      if (d > 0) busy.update(key, (v) => v + d, ifAbsent: () => d);
    }
    final top = busy.entries.toList()..sort((a, b) => b.value - a.value);
    stdout.writeln('CPU   threads (ms): ${[for (final e in top.take(8)) '${e.key} ${e.value * 10}'].join(', ')}');
    if (Platform.environment['RIFLAY_CPU_PROFILE'] == 'true') {
      try {
        // RIFLAY_CPU_PROFILE_WINDOW=600-1300: only those ms after the start.
        final window = (Platform.environment['RIFLAY_CPU_PROFILE_WINDOW'] ?? '').split('-').map(int.tryParse).toList();
        final (a, b) = window.length == 2 && window[0] != null && window[1] != null
            ? (from + window[0]! * 1000, from + window[1]! * 1000)
            : (from, developer.Timeline.now);
        stdout.writeln('CPU   dart: ${await _dartProfile(a, b)}');
      } catch (e) {
        stdout.writeln('CPU   dart: profile failed: $e');
      }
    }
  }

  // Headless Weston has no keyboard, so the window never gets the focus: say it has, as on a desktop where someone
  // is looking at it. "unfocused" below is another window having the focus.
  stdout.writeln('CPU (the embedder reported ${WidgetsBinding.instance.lifecycleState}; measured as resumed)');
  WidgetsBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  if (Platform.environment['RIFLAY_CPU_PROFILE'] == 'true') await _startProfiler();
  if (Platform.environment['RIFLAY_CPU_SPIKE'] == 'unfocus') {
    // Another window takes the focus while a song plays: the memory trim pages the app out ~8 s later.
    await c.playList([
      for (final t in c.library)
        if (t.path?.startsWith(songs) ?? false) t,
    ], 0);
    await Future<void>.delayed(settle);
    await slices(
      'another window in front',
      const Duration(seconds: 14),
      () => WidgetsBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.inactive),
    );
    exit(0);
  }
  if (Platform.environment['RIFLAY_CPU_SPIKE'] == 'lyrics') {
    final queue = [
      for (final t in c.library)
        if (t.path?.startsWith(songs) ?? false) t,
    ];
    await c.playList(queue, 0);
    await Future<void>.delayed(settle);
    ShellScope shell() => ShellScope.of(_find((e) => e.widget is PageScaffold)!);
    if (Platform.environment['RIFLAY_CPU_STACKS'] == 'true') {
      // A debug build: who asks for frames in the second burst after the page opens, and what ticks then.
      shell().openLyrics();
      await Future<void>.delayed(const Duration(milliseconds: 750));
      stdout.writeln('STACKS from here');
      debugPrintScheduleFrameStacks = true;
      await Future<void>.delayed(const Duration(milliseconds: 150));
      debugPrintScheduleFrameStacks = false;
      await _whoDraws(long: false, wait: Duration.zero);
      exit(0);
    }
    await slices('opening lyrics', const Duration(seconds: 4), () => shell().openLyrics());
    await slices('back to Home', const Duration(seconds: 2), () => shell().history?.back());
    await Future<void>.delayed(const Duration(seconds: 2));
    await slices('opening lyrics again (loaded)', const Duration(seconds: 4), () => shell().openLyrics());
    // For comparison: Home, the same song playing, nothing else moving there.
    shell().history?.back();
    await Future<void>.delayed(const Duration(seconds: 2));
    await slices('Home, playing', const Duration(seconds: 12), () {});
    shell().openLyrics();
    await Future<void>.delayed(const Duration(seconds: 2));
    // The page left open: a line changes every 4 s in the seeded lyrics.
    await slices('lyrics open, lines changing', const Duration(seconds: 12), () {});
    exit(0);
  }
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

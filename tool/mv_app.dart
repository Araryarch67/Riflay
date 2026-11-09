// The real app playing a YouTube Music song with its music video, measured the way a listener uses it: the song
// on Now Playing with the video, then the video full screen (VideoFullView) with its lyrics line on. CPU (whole
// process, per thread, every 100 ms) and memory (private / PSS / RSS every 250 ms) per phase. Run through
// tool/mv_app.sh. Prints "MV ..." lines.
import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:riflay/main.dart' as app;
import 'package:riflay/services/language.dart';
import 'package:riflay/services/lyrics_translation.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/services/video_mode.dart';
import 'package:riflay/ui/player/video_full_view.dart';
import 'package:riflay/ui/shell_scope.dart';
import 'package:riflay/ui/widgets/page_scaffold.dart';

int _ticks() {
  final f = File('/proc/self/stat').readAsStringSync().split(') ').last.split(' ');
  return int.parse(f[11]) + int.parse(f[12]);
}

Map<String, (String, int)> _threads() {
  final out = <String, (String, int)>{};
  for (final t in Directory('/proc/self/task').listSync()) {
    try {
      final stat = File('${t.path}/stat').readAsStringSync();
      final name = stat.substring(stat.indexOf('(') + 1, stat.lastIndexOf(')'));
      final f = stat.split(') ').last.split(' ');
      out[t.path] = (name, int.parse(f[11]) + int.parse(f[12]));
    } on FileSystemException {
      // ended meanwhile
    }
  }
  return out;
}

(double, double, double) _memory() {
  final text = File('/proc/self/smaps_rollup').readAsStringSync();
  int field(String name) => int.parse(RegExp('^$name:\\s+(\\d+) kB', multiLine: true).firstMatch(text)![1]!);
  return ((field('Private_Clean') + field('Private_Dirty')) / 1024, field('Pss') / 1024, field('Rss') / 1024);
}

/// Private memory by mapping (C heap, anonymous, Dart heap, each library), the biggest, in MiB.
String _parts() {
  final groups = <String, int>{};
  var name = '';
  for (final line in File('/proc/self/smaps').readAsLinesSync()) {
    final head = RegExp(r'^[0-9a-f]+-[0-9a-f]+ \S+ \S+ \S+ \S+\s*(.*)$').firstMatch(line);
    if (head != null) {
      final path = head[1]!.trim();
      name = path.isEmpty
          ? 'anonymous'
          : path.startsWith('/dev/')
          ? 'device ${path.split('/').last.replaceAll(RegExp(r'\d+$'), '')}'
          : path.startsWith('[') || path.startsWith('/memfd:')
          ? path.split(' ').first
          : path.split('/').last.split('.so').first;
      continue;
    }
    final m = RegExp(r'^Private_(?:Clean|Dirty):\s+(\d+) kB').firstMatch(line);
    if (m != null) groups.update(name, (v) => v + int.parse(m[1]!), ifAbsent: () => int.parse(m[1]!));
  }
  final top = groups.entries.toList()..sort((a, b) => b.value - a.value);
  return [for (final e in top.take(12)) '${e.key} ${(e.value / 1024).toStringAsFixed(0)}'].join(', ');
}

/// Flutter frames drawn so far.
var frames = 0;

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
  final query = Platform.environment['RIFLAY_MV_QUERY'] ?? 'Houshou Marine Kyapi';
  final seconds = int.parse(Platform.environment['RIFLAY_MV_SECONDS'] ?? '40');
  await app.main(const []);
  SchedulerBinding.instance.addTimingsCallback((t) => frames += t.length);
  Element? page;
  while ((page = _find((e) => e.widget is PageScaffold)) == null) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  final c = PlayerScope.read(page!);
  WidgetsBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

  if (Platform.environment['RIFLAY_MV_FLOW'] == 'btop') return _btopFlow(c, query);
  if (Platform.environment['RIFLAY_MV_FLOW'] == 'steady') return _steadyFlow(c, query);
  final found = await c.searchYoutube(query);
  stdout.writeln('MV search "$query": ${[for (final t in found.take(3)) '${t.title} · ${t.artist}'].join(' | ')}');
  final song = found.firstWhere((t) => t.videoId != null);
  await c.playList([song], 0, from: 'MV benchmark');
  final clock = Stopwatch()..start();
  while (!(c.player.playing && c.player.position > const Duration(seconds: 2)) && clock.elapsed.inSeconds < 60) {
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  stdout.writeln('MV playing "${song.title} · ${song.artist}" after ${clock.elapsed.inMilliseconds} ms');
  ShellScope shell() => ShellScope.of(_find((e) => e.widget is PageScaffold)!);
  shell().openNowPlaying();
  clock.reset();
  while (VideoMode.instance.videoOf(song) == null && clock.elapsed.inSeconds < 30) {
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  stdout.writeln('MV video ${VideoMode.instance.videoOf(song)?.videoId ?? 'not found'} (native ${VideoMode.native})');

  Future<void> phase(String label, Duration length) async {
    await Future<void>.delayed(const Duration(seconds: 3)); // settle
    final ticks0 = _ticks(), threads0 = _threads();
    frames = 0;
    final cpu = <int>[];
    final perSecond = <int>[];
    var framesBefore = 0;
    final private = <double>[], pss = <double>[], rss = <double>[];
    var last = _ticks();
    final sw = Stopwatch()..start();
    var sampled = Duration.zero;
    while (sw.elapsed < length) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final now = _ticks(), at = sw.elapsed;
      cpu.add(((now - last) * 10 * 1000 / (at - sampled).inMicroseconds * 100).round());
      last = now;
      sampled = at;
      if (cpu.length % 4 == 0) {
        perSecond.add(frames - framesBefore);
        framesBefore = frames;
      }
      final (pr, ps, rs) = _memory();
      private.add(pr);
      pss.add(ps);
      rss.add(rs);
    }
    final secs = sw.elapsedMilliseconds / 1000;
    final total = (_ticks() - ticks0) * 10 / (secs * 1000) * 100;
    final busy = <String, int>{};
    for (final MapEntry(key: id, value: (name, t)) in _threads().entries) {
      final d = t - (threads0[id]?.$2 ?? 0);
      if (d > 0) busy.update(name, (v) => v + d, ifAbsent: () => d);
    }
    final top = busy.entries.toList()..sort((a, b) => b.value - a.value);
    String range(List<double> v) {
      final s = [...v]..sort();
      return '${s.first.round()} / ${s[s.length ~/ 2].round()} / ${s.last.round()}';
    }

    final sorted = [...cpu]..sort();
    stdout.writeln(
      'MV $label: CPU ${total.toStringAsFixed(1)}% of one core '
      '(${(total / Platform.numberOfProcessors).toStringAsFixed(2)}% of all ${Platform.numberOfProcessors} threads), '
      'highest 250 ms ${sorted.last}%, ${(frames / secs).toStringAsFixed(1)} frames/s',
    );
    stdout.writeln('MV   frames each second: ${perSecond.join(' ')}');
    stdout.writeln(
      'MV   threads: ${[for (final e in top.take(7)) '${e.key} ${(e.value / secs).toStringAsFixed(1)}%'].join(', ')}',
    );
    stdout.writeln(
      'MV   memory MiB (low / median / high): private ${range(private)}, pss ${range(pss)}, rss ${range(rss)}',
    );
    if (Platform.environment['RIFLAY_MV_PARTS'] == 'true') stdout.writeln('MV   parts: ${_parts()}');
    stdout.writeln(
      'MV   state: playing ${c.player.playing}, at ${c.player.position.inSeconds} s, '
      'video ${VideoMode.instance.videoOf(c.currentTrack)?.videoId}, native ready ${VideoMode.instance.nativeReady}',
    );
  }

  if (Platform.environment['RIFLAY_MV_STACKS'] == 'nowplaying') {
    // A debug build: who asks for frames while Now Playing shows the video.
    await Future<void>.delayed(const Duration(seconds: 6));
    stdout.writeln('STACKS from here');
    debugPrintScheduleFrameStacks = true;
    await Future<void>.delayed(const Duration(milliseconds: 500));
    debugPrintScheduleFrameStacks = false;
    exit(0);
  }
  await phase('Now Playing with the video', Duration(seconds: seconds ~/ 2));
  unawaited(openVideoFullView(_find((e) => e.widget is PageScaffold)!));
  await Future<void>.delayed(const Duration(seconds: 2));
  final lyrics = _find((e) => e.widget is IconButton && (e.widget as IconButton).tooltip == tr.showLyrics);
  (lyrics?.widget as IconButton?)?.onPressed?.call();
  stdout.writeln('MV full screen video, lyrics line ${lyrics == null ? 'not found' : 'on'}');
  if (Platform.environment['RIFLAY_MV_STACKS'] == 'full') {
    await Future<void>.delayed(const Duration(seconds: 8));
    stdout.writeln('STACKS from here');
    debugPrintScheduleFrameStacks = true;
    await Future<void>.delayed(const Duration(milliseconds: 800));
    debugPrintScheduleFrameStacks = false;
    exit(0);
  }
  await phase('full screen video with lyrics', Duration(seconds: seconds));
  WidgetsBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  await phase('full screen video with lyrics, another window in front', Duration(seconds: seconds ~/ 2));
  exit(0);
}

/// RIFLAY_MV_FLOW=btop: what a listener does, each step marked with the time since start ("MV at"), for a sampler
/// outside the app that reads its CPU the way btop does (tool/btop_watch.py): the song with its video on Home, the
/// lyrics page, Now Playing, the full screen video with its lyrics line, then back.
Future<void> _btopFlow(PlayerController c, String query) async {
  final clock = Stopwatch()..start();
  void at(String step) => stdout.writeln('MV at ${(clock.elapsedMilliseconds / 1000).toStringAsFixed(1)} s: $step');
  ShellScope shell() => ShellScope.of(_find((e) => e.widget is PageScaffold)!);
  Future<void> rest(int s) => Future<void>.delayed(Duration(seconds: s));
  at('searching');
  final song = (await c.searchYoutube(query)).firstWhere((t) => t.videoId != null);
  at('play ${song.title}');
  await c.playList([song], 0, from: 'MV benchmark');
  await rest(10);
  at('open lyrics');
  shell().openLyrics();
  await rest(10);
  at('back to Home');
  shell().history?.back();
  await rest(8);
  at('open Now Playing (video)');
  shell().openNowPlaying();
  await rest(10);
  at('open the full screen video');
  unawaited(openVideoFullView(_find((e) => e.widget is PageScaffold)!));
  await rest(2);
  final lyrics = _find((e) => e.widget is IconButton && (e.widget as IconButton).tooltip == tr.showLyrics);
  (lyrics?.widget as IconButton?)?.onPressed?.call();
  at('lyrics line on');
  await rest(12);
  at('done');
  exit(0);
}

/// RIFLAY_MV_FLOW=steady: each state a song spends minutes in, held 20 s, with another window in front after each
/// (as most listening is), for tool/btop_watch.py's per-step averages. Lyrics show their pronunciation, as the
/// reference listener reads them. RIFLAY_MV_TRIM=true: halfway through each step, private memory by part before
/// and after a `malloc_trim(0)` (what glibc held freed).
Future<void> _steadyFlow(PlayerController c, String query) async {
  final clock = Stopwatch()..start();
  var framesAt = 0;
  void at(String step) {
    stdout.writeln('MV at ${(clock.elapsedMilliseconds / 1000).toStringAsFixed(1)} s: $step (${frames - framesAt} frames before)');
    framesAt = frames;
  }

  ShellScope shell() => ShellScope.of(_find((e) => e.widget is PageScaffold)!);
  final binding = WidgetsBinding.instance;
  Future<void> hold(String step) async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    at(step);
    if (Platform.environment['RIFLAY_MV_TRIM'] == 'true') {
      await Future<void>.delayed(const Duration(seconds: 10));
      stdout.writeln('MV   before trim: ${_parts()}');
      DynamicLibrary.process().lookupFunction<Int32 Function(IntPtr), int Function(int)>('malloc_trim')(0);
      stdout.writeln('MV   after trim:  ${_parts()}');
      await Future<void>.delayed(const Duration(seconds: 10));
    } else {
      await Future<void>.delayed(const Duration(seconds: 20));
    }
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    at('$step, another window in front');
    // A debug build: who asks for frames on the lyrics page behind another window.
    if (Platform.environment['RIFLAY_MV_STACKS'] == 'lyrics-behind' && step == 'lyrics page') {
      await Future<void>.delayed(const Duration(seconds: 8));
      stdout.writeln('STACKS from here');
      debugPrintScheduleFrameStacks = true;
      await Future<void>.delayed(const Duration(seconds: 10));
      debugPrintScheduleFrameStacks = false;
      exit(0);
    }
    await Future<void>.delayed(const Duration(seconds: 20));
  }

  LyricsTranslation.romanize.value = true;
  stdout.writeln('MV semantics enabled: ${WidgetsBinding.instance.semanticsEnabled}');
  final song = (await c.searchYoutube(query)).firstWhere((t) => t.videoId != null);
  await c.playList([song], 0, from: 'MV benchmark');
  await Future<void>.delayed(const Duration(seconds: 4));
  await hold('Home');
  shell().openLyrics();
  await hold('lyrics page');
  shell().history?.back();
  shell().openNowPlaying();
  await hold('Now Playing with the video');
  unawaited(openVideoFullView(_find((e) => e.widget is PageScaffold)!));
  await Future<void>.delayed(const Duration(seconds: 2));
  final lyrics = _find((e) => e.widget is IconButton && (e.widget as IconButton).tooltip == tr.showLyrics);
  (lyrics?.widget as IconButton?)?.onPressed?.call();
  await hold('full screen video with its lyrics line');
  binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await c.pause();
  at('paused');
  await Future<void>.delayed(const Duration(seconds: 15));
  at('done');
  exit(0);
}

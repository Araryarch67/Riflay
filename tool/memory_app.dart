// The real app, started as it always is (WidgetsFlutterBinding, no test binding), taken through what a listening
// session does: idle, a hi-res song, Now Playing, scrolling a library of covers, a music video, then idle again.
// Its own memory is read every 250 ms throughout, so a jump between two fixed points shows too.
//
// Run it through tool/memory_app.sh (profile build, headless Weston, a throwaway data folder). Prints "MEM ..."
// lines: each phase's private (what is this process's alone, like Windows' private working set), PSS and RSS, as
// low / median / high, then what the private memory is made of at the highest point.
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/widgets.dart';
import 'package:riflay/main.dart' as app;
import 'package:riflay/ui/player/now_playing_page.dart';
import 'package:riflay/ui/player_scope.dart';
import 'package:riflay/ui/shell_scope.dart';
import 'package:riflay/ui/widgets/page_scaffold.dart';

/// private, pss and rss of this process in MiB.
(double, double, double) _memory() {
  final text = File('/proc/self/smaps_rollup').readAsStringSync();
  int field(String name) => int.parse(RegExp('^$name:\\s+(\\d+) kB', multiLine: true).firstMatch(text)![1]!);
  return ((field('Private_Clean') + field('Private_Dirty')) / 1024, field('Pss') / 1024, field('Rss') / 1024);
}

/// Private memory by mapping: the C heap, anonymous memory (the Dart heap, mpv's and the GPU driver's own
/// allocations), the GPU device, and each library's own pages. The biggest ones, in MiB.
String _breakdown() {
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
          : path.startsWith('[')
          ? path
          : path.startsWith('/memfd:')
          ? 'memfd ${path.substring(7).split(' ').first}'
          : path.split('/').last.split('.so').first;
      continue;
    }
    final m = RegExp(r'^Private_(?:Clean|Dirty):\s+(\d+) kB').firstMatch(line);
    if (m != null) groups.update(name, (v) => v + int.parse(m[1]!), ifAbsent: () => int.parse(m[1]!));
  }
  final top = groups.entries.toList()..sort((a, b) => b.value - a.value);
  return [for (final e in top.take(10)) '${e.key} ${(e.value / 1024).toStringAsFixed(1)}'].join(', ');
}

/// The Dart heap from the VM service (profile builds have it): used and reserved, memory held outside it (typed
/// data, images), and the classes holding the most, after a full collection.
Future<String> _dartHeap() async {
  final uri = (await developer.Service.getInfo()).serverWebSocketUri;
  if (uri == null) return 'no VM service';
  final socket = await WebSocket.connect(uri.toString());
  final replies = socket.map((m) => jsonDecode(m as String) as Map<String, dynamic>).asBroadcastStream();
  var id = 0;
  Future<Map<String, dynamic>> call(String method, [Map<String, Object?> params = const {}]) async {
    final mine = '${id++}';
    socket.add(jsonEncode({'jsonrpc': '2.0', 'id': mine, 'method': method, 'params': params}));
    return (await replies.firstWhere((r) => r['id'] == mine))['result'] as Map<String, dynamic>;
  }

  try {
    final isolate = developer.Service.getIsolateId(Isolate.current)!;
    final profile = await call('getAllocationProfile', {'isolateId': isolate, 'gc': true});
    final usage = await call('getMemoryUsage', {'isolateId': isolate});
    String mib(num b) => (b / (1 << 20)).toStringAsFixed(1);
    final classes = [
      for (final m in (profile['members'] as List).cast<Map<String, dynamic>>())
        (m['class']['name'] as String, (m['bytesCurrent'] as num?) ?? 0),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return 'heap used ${mib(usage['heapUsage'] as num)} of ${mib(usage['heapCapacity'] as num)}, '
        'external ${mib(usage['externalUsage'] as num)} MiB; '
        '${[for (final (name, bytes) in classes.take(12)) '$name ${mib(bytes)}'].join(', ')}';
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

/// The longest vertical scroll view on screen: the page's own.
ScrollPosition? _pageScroll() {
  ScrollPosition? best;
  void visit(Element e) {
    if (e is StatefulElement && e.state is ScrollableState) {
      final p = (e.state as ScrollableState).position;
      if (p.axis == Axis.vertical &&
          p.hasContentDimensions &&
          (best == null || p.maxScrollExtent > best!.maxScrollExtent)) {
        best = p;
      }
    }
    e.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return best;
}

Future<void> main() async {
  final songs = Platform.environment['RIFLAY_MEM_SONGS'] ?? '';
  final scale = double.parse(Platform.environment['RIFLAY_MEM_SCALE'] ?? '1');
  await app.main(const []);

  Element? page;
  while ((page = _find((e) => e.widget is PageScaffold)) == null) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  final c = PlayerScope.read(page!);
  while (c.scanning) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  WidgetsBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

  var peak = 0.0;
  var peakAt = '';
  var peakBreakdown = '';
  Future<void> phase(String label, Duration length, [Future<void> Function()? during]) async {
    final private = <double>[], pss = <double>[], rss = <double>[];
    var done = false;
    final work = (during?.call() ?? Future<void>.value()).whenComplete(() => done = true);
    final clock = Stopwatch()..start();
    while (clock.elapsed < length * scale || !done) {
      final (pr, ps, rs) = _memory();
      private.add(pr);
      pss.add(ps);
      rss.add(rs);
      if (pr > peak) {
        peak = pr;
        peakAt = label;
        peakBreakdown = _breakdown();
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    await work;
    String range(List<double> v) {
      final s = [...v]..sort();
      return '${s.first.round()} / ${s[s.length ~/ 2].round()} / ${s.last.round()}';
    }

    final images = PaintingBinding.instance.imageCache;
    if (Platform.environment['RIFLAY_MEM_DART'] == 'true') stdout.writeln('MEM   dart: ${await _dartHeap()}');
    if (Platform.environment['RIFLAY_MEM_PARTS'] == 'true') stdout.writeln('MEM   parts: ${_breakdown()}');
    stdout.writeln(
      'MEM $label: private ${range(private)}, pss ${range(pss)}, rss ${range(rss)} MiB '
      '(decoded images ${(images.currentSizeBytes / (1 << 20)).toStringAsFixed(1)} MiB, ${images.currentSize})',
    );
  }

  ShellScope shell() => ShellScope.of(_find((e) => e.widget is PageScaffold)!);
  Future<void> scroll() async {
    for (var round = 0; round < 2; round++) {
      final p = _pageScroll();
      if (p == null) return;
      for (var y = 0.0; y <= p.maxScrollExtent; y += 400) {
        p.jumpTo(y);
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
      for (var y = p.maxScrollExtent; y >= 0; y -= 400) {
        p.jumpTo(y);
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
    }
  }

  List<T> mine<T>(Iterable<T> tracks, bool Function(T) test) => [
    for (final t in tracks)
      if (test(t)) t,
  ];
  final library = c.library.where((t) => t.path?.startsWith(songs) ?? false).toList();
  final hires = mine(library, (t) => t.path!.contains('hires'));
  final video = mine(library, (t) => t.path!.endsWith('.mp4'));

  await phase('idle, Home', const Duration(seconds: 10));
  await c.playList(hires, 0);
  await phase('playing hi-res, Home', const Duration(seconds: 10));
  shell().openNowPlaying();
  await phase('playing, Now Playing', const Duration(seconds: 10));
  Navigator.of(_find((e) => e.widget is NowPlayingPage)!).pop();
  shell().openCollection(c.allSongs);
  await phase('scrolling All Songs (covers)', const Duration(seconds: 5), scroll);
  if (video.isNotEmpty) {
    await c.playList(video, 0);
    shell().openNowPlaying();
    await phase('music video, Now Playing', const Duration(seconds: 20));
    Navigator.of(_find((e) => e.widget is NowPlayingPage)!).pop();
    await phase('music video, side panel', const Duration(seconds: 15));
  }
  await c.playList(hires, 0);
  await phase('playing hi-res again', const Duration(seconds: 10));
  // Another window in front (btop, a browser) while the song plays on.
  WidgetsBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  await phase('playing, another window in front', const Duration(seconds: 30));
  WidgetsBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await c.pause();
  await phase('paused, settled', const Duration(seconds: 70));
  stdout.writeln('MEM peak ${peak.round()} MiB private, while $peakAt: $peakBreakdown');
  exit(0);
}

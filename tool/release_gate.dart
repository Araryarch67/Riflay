// Walks a running profile build through the release gate's phases: Home while a song plays, the expanded
// player, its lyrics, the Lyrics page, an album scrolled with the mouse wheel, Home again. It drives the app
// through `ext.riflay.gate` (lib/services/gate_hooks.dart), so it needs no mouse or focus; the window must
// stay visible.
//
// It writes the phase it is in to `<temp>/riflay_gate.phase` ("done" at the end) for a script that measures
// the app's CPU and memory as Task Manager shows them, and prints the frames drawn per second in each phase.
//
//   flutter run --profile -d windows        (note the VM service URL it prints)
//   dart tool/release_gate.dart ws://127.0.0.1:PORT/TOKEN=/ws [seconds per phase] [part of a song title]
import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final ws = await WebSocket.connect(args.first);
  final seconds = args.length > 1 ? int.parse(args[1]) : 25;
  final song = args.length > 2 ? args[2] : 'official';
  final phaseFile = File('${Directory.systemTemp.path}${Platform.pathSeparator}riflay_gate.phase');

  var id = 0;
  final pending = <String, Completer<Map>>{};
  ws.listen((m) {
    final j = jsonDecode(m as String) as Map;
    final c = pending.remove('${j['id']}');
    if (j['error'] != null) {
      c?.completeError(j['error'] as Object);
    } else {
      c?.complete(j['result'] as Map);
    }
  });
  Future<Map> call(String method, [Map<String, Object?> params = const {}]) {
    final i = '${++id}';
    final c = pending[i] = Completer<Map>();
    ws.add(jsonEncode({'jsonrpc': '2.0', 'id': i, 'method': method, 'params': params}));
    return c.future;
  }

  final vm = await call('getVM');
  final isolates = vm['isolates'] as List;
  final isolate = isolates.firstWhere((i) => '${i['name']}'.contains('main'), orElse: () => isolates.first)['id'];
  Future<Object?> gate(String command, [Map<String, String> more = const {}]) async =>
      (await call('ext.riflay.gate', {'isolateId': isolate, 'command': command, ...more}))['result'];
  Future<void> wait(Duration d) => Future<void>.delayed(d);

  phaseFile.writeAsStringSync('setup');
  stdout.writeln('GATE playing ${await gate('play', {'song': song})}');
  for (var i = 0; i < 200 && await gate('playing') != 'true'; i++) {
    await wait(const Duration(milliseconds: 100));
  }
  // Streams start, the video is looked up and the caches fill.
  await wait(const Duration(seconds: 8));

  Future<void> phase(String name, [Future<void> Function()? during]) async {
    phaseFile.writeAsStringSync(name);
    await gate('frames');
    final clock = Stopwatch()..start();
    if (during != null) await during();
    final left = Duration(seconds: seconds) - clock.elapsed;
    if (!left.isNegative) await wait(left);
    final frames = await gate('frames') as int;
    stdout.writeln('GATE $name: ${(frames / clock.elapsedMilliseconds * 1000).toStringAsFixed(1)} frames/s');
  }

  await phase('home_playing');
  await gate('expanded', {'on': 'true'});
  await wait(const Duration(seconds: 2));
  await phase('now_playing');
  await gate('panel', {'name': 'lyrics'});
  await phase('lyrics_expanded');
  await gate('expanded', {'on': 'false'});
  await wait(const Duration(seconds: 1));
  await gate('lyrics');
  await phase('lyrics_page');
  await gate('collection');
  await phase('album_scroll', () async {
    await wait(const Duration(seconds: 2));
    for (var i = 0; i < 8; i++) {
      // A few wheel notches down, then back up.
      for (var n = 0; n < 4; n++) {
        await gate('wheel', {'dy': i.isEven ? '120' : '-120'});
        await wait(const Duration(milliseconds: 120));
      }
      await wait(const Duration(seconds: 2));
    }
  });
  await gate('home');
  await phase('home_again');
  phaseFile.writeAsStringSync('done');
  await gate('pause');
  await ws.close();
}

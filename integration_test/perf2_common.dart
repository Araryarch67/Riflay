// Shared helpers of the perf2_*_test.dart files (extra measurements: start-up,
// Dynamic theme, big library interaction, tag-scan churn, video size lookup).
// Not a test itself. Results: "PERF2 <label>: ..." lines and
// build/perf/<date>-extra.json (one list of runs per scenario).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:media_kit/media_kit.dart' show NativePlayer;
import 'package:riflay/models/track.dart';
import 'package:riflay/services/library_store.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Budgets, generous on purpose. They are only reported (see [Perf2.report]), never enforced yet.
const budgetFirstFrameMs = 3000;
const budgetInteractiveMs = 6000;
const budgetThemeBuildTotalMs = 150;
const budgetSearchResultsMs = 800;
const budgetBuildP90Ms = 8.0;
const budgetBuildMaxMs = 40.0;
const budgetScanNotifies = 100;
const budgetVideoSizesMs = 5000;

Future<void> ffmpeg(List<String> args) async {
  final r = await Process.run('ffmpeg', ['-loglevel', 'error', '-y', ...args]);
  if (r.exitCode != 0) throw StateError('ffmpeg: ${r.stderr}');
}

/// Milliseconds since this process started (from /proc), or -1 where unknown.
int processAgeMs() {
  try {
    final stat = File('/proc/self/stat').readAsStringSync();
    final fields = stat.substring(stat.lastIndexOf(')') + 2).split(' ');
    final startTicks = int.parse(fields[19]); // field 22 overall; the first two are pid and (comm)
    final up = double.parse(File('/proc/uptime').readAsStringSync().split(' ').first);
    return ((up - startTicks / 100) * 1000).round(); // CLK_TCK is 100 on Linux
  } catch (_) {
    return -1;
  }
}

/// VmRSS and VmHWM (peak) of this process in MiB.
Map<String, double> rssMiB() {
  final out = <String, double>{};
  try {
    final text = File('/proc/self/status').readAsStringSync();
    for (final k in ['VmRSS', 'VmHWM']) {
      final m = RegExp('^$k:\\s+(\\d+) kB', multiLine: true).firstMatch(text);
      if (m != null) {
        out[k == 'VmRSS' ? 'rssMiB' : 'peakRssMiB'] = double.parse((int.parse(m[1]!) / 1024).toStringAsFixed(1));
      }
    }
  } catch (_) {}
  return out;
}

/// 8000-style tagged tracks whose files don't exist: only the UI sees them.
List<Track> fakeTracks(int n, {String word = 'Blue'}) => [
  for (var i = 0; i < n; i++)
    Track(
      id: Uri.file('/nonexistent/album${i ~/ 10}/${i % 10 + 1} Perf $i.flac').toString(),
      uri: Uri.file('/nonexistent/album${i ~/ 10}/${i % 10 + 1} Perf $i.flac'),
      title: 'Perf Song $i ${[word, 'Night', 'Rain', 'Light', 'Fire'][i % 5]}${i % 7 == 0 ? ' Xylo' : ''}',
      artist: 'Artist ${(i ~/ 10) % 400}',
      album: 'Album ${i ~/ 10}',
      duration: Duration(seconds: 150 + i % 120),
      trackNumber: i % 10 + 1,
      addedAt: i,
      tagged: true,
    ),
];

/// Writes the library the way the app does (its own file via LibraryStore) so the load path is the real one.
Future<void> saveLibrary(List<Track> tracks) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
  await LibraryStore.save(prefs, tracks);
}

/// A controller whose every mpv player starts on the null audio output.
PlayerController silentController() {
  final c = PlayerController();
  final apply = JustAudioMediaKit.onPlayerCreated!;
  JustAudioMediaKit.onPlayerCreated = (p) async {
    await (p.platform as NativePlayer).setProperty('ao', 'null');
    apply(p);
  };
  return c;
}

class Stats {
  Stats(List<FrameTiming> t, {this.windowMs = 0})
    : build = [for (final f in t) f.buildDuration.inMicroseconds / 1000]..sort(),
      raster = [for (final f in t) f.rasterDuration.inMicroseconds / 1000]..sort();

  final List<double> build, raster;
  final int windowMs;

  double pct(List<double> l, double p) => l.isEmpty ? 0 : l[((l.length - 1) * p).round()];
  double get total => build.fold(0.0, (a, b) => a + b);

  Map<String, num> toJson() => {
    'frames': build.length,
    'buildTotalMs': double.parse(total.toStringAsFixed(1)),
    'buildP50': double.parse(pct(build, .5).toStringAsFixed(2)),
    'buildP90': double.parse(pct(build, .9).toStringAsFixed(2)),
    'buildMax': double.parse(pct(build, 1).toStringAsFixed(2)),
    'rasterP90': double.parse(pct(raster, .9).toStringAsFixed(2)),
    'rasterMax': double.parse(pct(raster, 1).toStringAsFixed(2)),
    'jankyBuilds': build.where((b) => b > 16.7).length,
  };
}

/// The longest the event loop went without running a 2 ms timer.
class StallMeter {
  Timer? _timer;
  final _clock = Stopwatch();
  int _last = 0;
  int worst = 0;

  void start() {
    worst = 0;
    _clock
      ..reset()
      ..start();
    _last = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 2), (_) {
      final now = _clock.elapsedMicroseconds;
      if (now - _last > worst) worst = now - _last;
      _last = now;
    });
  }

  double stop() {
    _timer?.cancel();
    final now = _clock.elapsedMicroseconds;
    if (now - _last > worst) worst = now - _last;
    return double.parse((worst / 1000).toStringAsFixed(1));
  }
}

class FrameLog {
  final timings = <FrameTiming>[];
  FrameLog() {
    SchedulerBinding.instance.addTimingsCallback(timings.addAll);
  }
}

/// Collects one scenario's numbers, prints "PERF2" lines and appends to `build/perf/<date>-extra.json`.
class Perf2 {
  Perf2(this.scenario);
  final String scenario;
  final results = <String, Object>{'mode': kProfileMode ? 'profile' : 'debug'};

  void report(String label, Object value) {
    results[label] = value;
    debugPrint('PERF2 $scenario/$label: ${jsonEncode(value)}');
  }

  /// Budgets are reported as "over" flags, never failures.
  void budget(String label, num value, num limit) {
    if (value > limit) {
      debugPrint('PERF2 $scenario/$label: OVER BUDGET ($value > $limit)');
    }
  }

  void save() {
    final now = DateTime.now();
    final day = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final file = File('build/perf/$day-extra.json');
    file.parent.createSync(recursive: true);
    Map<String, dynamic> all = {};
    try {
      all = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {}
    (all[scenario] as List? ?? (all[scenario] = <dynamic>[])).add(results);
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(all));
  }
}

/// Pumps frames for [d] with the 16 ms cadence the other perf tests use.
Future<void> runFor(WidgetTester tester, Duration d) async {
  final sw = Stopwatch()..start();
  while (sw.elapsed < d) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> wheel(WidgetTester tester, {Offset at = const Offset(860, 450), int ticks = 40}) async {
  final pointer = TestPointer(1, PointerDeviceKind.mouse);
  await tester.sendEventToBinding(pointer.hover(at));
  for (var i = 0; i < ticks; i++) {
    await tester.sendEventToBinding(pointer.scroll(Offset(0, i < ticks / 2 ? 120 : -120)));
    await runFor(tester, const Duration(milliseconds: 48));
  }
}

void laptopPanel(WidgetTester tester) {
  tester.view.physicalSize = const Size(2560, 1600);
  tester.view.devicePixelRatio = 1.6;
  addTearDown(tester.view.reset);
}

/// [n] real FLAC files (2 s, tagged, 500 px cover) into [dir]: [templates] distinct ones, copied under new names.
Future<List<String>> makeRealFiles(Directory dir, int n, {int templates = 4, bool tagged = true}) async {
  final base = <String>[];
  for (var t = 0; t < templates; t++) {
    final cover = '${dir.path}/cover$t.jpg';
    await ffmpeg([
      '-f',
      'lavfi',
      '-i',
      'color=c=0x${(t * 60 + 20).toRadixString(16).padLeft(2, '0')}4080:s=500x500',
      '-frames:v',
      '1',
      cover,
    ]);
    final f = '${dir.path}/template$t.flac';
    await ffmpeg([
      '-f',
      'lavfi',
      '-i',
      'sine=f=${220 + t * 40}:d=2',
      '-i',
      cover,
      '-map',
      '0',
      '-map',
      '1', //
      '-c:v', 'mjpeg', '-disposition:v', 'attached_pic',
      '-metadata',
      'title=Template $t',
      '-metadata',
      'artist=Scan artist $t',
      '-metadata',
      'album=Scan album $t',
      f,
    ]);
    base.add(f);
  }
  final out = <String>[];
  final songs = Directory('${dir.path}/music')..createSync();
  for (var i = 0; i < n; i++) {
    final f = '${songs.path}/Scan file ${i.toString().padLeft(4, '0')}.flac';
    await File(base[i % templates]).copy(f);
    out.add(f);
  }
  return out;
}

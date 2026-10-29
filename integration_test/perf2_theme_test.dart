// Extra perf 2: Dynamic theme, a song change between two different covers.
// Counts app-wide rebuild notifies (Appearance and PlayerController) and the
// build time of the frames in and after the 600 ms fade.
// Run: tool/perf_extra.sh theme
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:riflay/main.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/appearance.dart';

import 'perf2_common.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Dynamic theme song change', (tester) async {
    JustAudioMediaKit.ensureInitialized(linux: true, windows: true);
    final perf = Perf2('theme');
    final dir = Directory.systemTemp.createTempSync('om-perf2');
    addTearDown(() => dir.deleteSync(recursive: true));
    // Two songs with very different covers (red, then green) among a 2000-song library.
    final files = <String>[];
    for (final (i, colour) in ['0xd02020', '0x20c040'].indexed) {
      final cover = '${dir.path}/c$i.jpg';
      await ffmpeg(['-f', 'lavfi', '-i', 'color=c=$colour:s=1000x1000', '-frames:v', '1', cover]);
      final f = '${dir.path}/song$i.flac';
      await ffmpeg([
        '-f',
        'lavfi',
        '-i',
        'sine=f=${300 + i * 100}:d=30',
        '-i',
        cover,
        '-map',
        '0',
        '-map',
        '1', //
        '-c:v', 'mjpeg', '-disposition:v', 'attached_pic',
        '-metadata',
        'title=Cover song ${'AB'[i]}',
        '-metadata',
        'artist=Cover artist',
        '-metadata',
        'album=Cover album $i',
        f,
      ]);
      files.add(f);
    }
    await saveLibrary([...fakeTracks(2000), for (final f in files) Track.fromUri(Uri.file(f))]);
    laptopPanel(tester);
    await Appearance.instance.load();
    final c = silentController();
    await c.load();
    while (c.scanning) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await Appearance.instance.setTheme(ThemeChoice.dynamic);
    await tester.pumpWidget(RiflayApp(controller: c));
    final log = FrameLog();
    final real = [
      for (final t in c.library)
        if (t.path?.startsWith(dir.path) ?? false) t,
    ]..sort((a, b) => a.title.compareTo(b.title));
    expect(real.length, 2);
    await c.playList(real, 0, from: 'Cover songs');
    await runFor(tester, const Duration(seconds: 4)); // song A on, its colours settled

    var appearance = 0, player = 0;
    void onA() => appearance++;
    void onP() => player++;
    Appearance.instance.addListener(onA);
    c.addListener(onP);
    log.timings.clear();
    final sw = Stopwatch()..start();
    final stall = StallMeter()..start();
    await c.next();
    // The fade is 600 ms; watch it and the song change around it.
    await runFor(tester, const Duration(milliseconds: 1500));
    final stallMs = stall.stop();
    Appearance.instance.removeListener(onA);
    c.removeListener(onP);
    final s = Stats(log.timings);
    perf.report('song change', {
      'windowMs': sw.elapsedMilliseconds,
      'appearanceNotifies': appearance,
      'playerNotifies': player,
      'buildTotalMs': s.toJson()['buildTotalMs'],
      'worstFrameBuildMs': s.toJson()['buildMax'],
      'frames': s.build.length,
      'buildP90': s.toJson()['buildP90'],
      'stallMaxMs': stallMs,
      'rasterMax': s.toJson()['rasterMax'],
    });
    perf.report('memory', rssMiB());
    perf.budget('buildTotalMs', s.total, budgetThemeBuildTotalMs);
    perf.budget('worstFrameBuildMs', s.pct(s.build, 1), budgetBuildMaxMs);
    perf.save();
    await c.player.stop();
    if (!kProfileMode) {
      markTestSkipped('numbers only mean something in profile mode');
    }
  });
}

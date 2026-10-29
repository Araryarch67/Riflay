// Extra perf 4: tag-scan churn. 500 untagged files in a watched folder; frames
// and app-wide rebuilds in the first 10 s after launch.
// Run: tool/perf_extra.sh tagscan
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:riflay/main.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/appearance.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'perf2_common.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('tag scan churn', (tester) async {
    JustAudioMediaKit.ensureInitialized(linux: true, windows: true);
    final perf = Perf2('tagscan');
    final dir = Directory.systemTemp.createTempSync('om-perf2');
    addTearDown(() => dir.deleteSync(recursive: true));
    final files = await makeRealFiles(dir, 500);
    await saveLibrary([for (final f in files) Track.fromUri(Uri.file(f))]);
    await (await SharedPreferences.getInstance()).setStringList('library.folders.v1', ['${dir.path}/music']);
    laptopPanel(tester);

    await Appearance.instance.load();
    final log = FrameLog();
    final stall = StallMeter();
    final clock = Stopwatch()..start();
    stall.start();
    final c = silentController();
    var player = 0, appearance = 0;
    c.addListener(() => player++);
    Appearance.instance.addListener(() => appearance++);
    var revisions = 0;
    c.libraryRevision.addListener(() => revisions++);
    await c.load(); // starts the tag scan and the folder watch, as at launch
    await tester.pumpWidget(RiflayApp(controller: c));
    int? scanDoneMs;
    while (clock.elapsedMilliseconds < 10000) {
      await tester.pump(const Duration(milliseconds: 16));
      if (scanDoneMs == null && !c.scanning) {
        scanDoneMs = clock.elapsedMilliseconds;
      }
    }
    final stallMs = stall.stop();
    perf.report('first 10 s', {
      ...Stats(log.timings).toJson(),
      'playerNotifies': player,
      'appearanceNotifies': appearance,
      'libraryRevisionBumps': revisions,
      'stallMaxMs': stallMs,
      'scanDoneMs': scanDoneMs ?? -1,
      'taggedAfter': c.library.where((t) => t.tagged).length,
    });
    perf.report('memory', rssMiB());
    perf.budget('playerNotifies', player, budgetScanNotifies);
    perf.save();
    if (!kProfileMode) {
      markTestSkipped('numbers only mean something in profile mode');
    }
  });
}

// Extra perf 1: time to first frame and to interactive with an 8000-song library
// already saved in the library file. Run: tool/perf_extra.sh startup

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:riflay/main.dart';
import 'package:riflay/services/appearance.dart';
import 'package:riflay/services/layout_prefs.dart';

import 'perf2_common.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('start-up with 8000 songs', (tester) async {
    final bootMs = processAgeMs(); // engine + Dart boot, before anything below
    JustAudioMediaKit.ensureInitialized(linux: true, windows: true);
    final perf = Perf2('startup');
    perf.report('processAgeAtTestStartMs', bootMs);

    var sw = Stopwatch()..start();
    await saveLibrary(fakeTracks(8000));
    perf.report('dataSetupMs (not counted)', sw.elapsedMilliseconds);
    laptopPanel(tester);

    final log = FrameLog();
    final total = Stopwatch()..start();
    // What main() does before runApp, minus the window and media-session plumbing.
    await Appearance.instance.load();
    await LayoutPrefs.instance.load();
    final controller = silentController();
    sw = Stopwatch()..start();
    final loading = controller.load();
    warmUpText(); // as main() does, while the library loads in its isolate
    await loading;
    perf.report('controllerLoadMs', sw.elapsedMilliseconds);
    expect(controller.library.length, 8000);

    await tester.pumpWidget(RiflayApp(controller: controller));
    var sinceStartup = total.elapsedMilliseconds;
    // First rasterized frame: wait for the engine's timing report.
    while (log.timings.isEmpty && total.elapsedMilliseconds < 15000) {
      await tester.pump(const Duration(milliseconds: 4));
    }
    final firstFrame = total.elapsedMilliseconds;
    perf.report('firstWidgetFrameMs', sinceStartup);
    perf.report('firstFrameRasterizedMs', firstFrame);
    perf.report('firstFrameBuildMs', log.timings.isEmpty ? -1 : log.timings.first.buildDuration.inMicroseconds / 1000);

    // Interactive: Home shows the library ("8000 songs" on its All Songs card).
    while (find.textContaining('8000 songs').evaluate().isEmpty && total.elapsedMilliseconds < 20000) {
      await tester.pump(const Duration(milliseconds: 4));
    }
    final interactive = total.elapsedMilliseconds;
    perf.report('interactiveMs', interactive);
    // From process start, leaving the data setup out: boot + the app's own part.
    perf.report('firstFrameSinceProcessStartMs', bootMs + firstFrame);
    perf.report('interactiveSinceProcessStartMs', bootMs + interactive);
    await runFor(tester, const Duration(seconds: 2));
    perf.report('memory', rssMiB());
    perf.report('allFrames', Stats(log.timings).toJson());
    perf.budget('firstFrameRasterizedMs', firstFrame, budgetFirstFrameMs);
    perf.budget('interactiveMs', interactive, budgetInteractiveMs);
    perf.save();
    await controller.player.stop();
    if (!kProfileMode) {
      markTestSkipped('numbers only mean something in profile mode');
    }
  });
}

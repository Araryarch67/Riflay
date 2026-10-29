// Extra perf 3: interaction with an 8000-song library: open All Songs and
// wheel-scroll it, type a 3-letter search in the title-bar field, scroll the
// sidebar's Library list. Run: tool/perf_extra.sh biglib
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:riflay/main.dart';
import 'package:riflay/ui/shell_scope.dart';
import 'package:riflay/ui/widgets/page_scaffold.dart';

import 'perf2_common.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('big library interaction', (tester) async {
    JustAudioMediaKit.ensureInitialized(linux: true, windows: true);
    final perf = Perf2('biglib');
    await saveLibrary(fakeTracks(8000));
    laptopPanel(tester);
    final c = silentController();
    await c.load();
    await tester.pumpWidget(RiflayApp(controller: c));
    final log = FrameLog();
    await runFor(tester, const Duration(seconds: 3));

    final stalls = StallMeter();
    final lastKeyDone = <int, bool>{};
    Future<void> measure(String label, Future<Map<String, Object>?> Function() body) async {
      await runFor(tester, const Duration(milliseconds: 400));
      log.timings.clear();
      stalls.start();
      final sw = Stopwatch()..start();
      final extra = await body();
      final ms = sw.elapsedMilliseconds;
      await runFor(tester, const Duration(milliseconds: 300));
      perf.report(label, {...Stats(log.timings).toJson(), 'bodyMs': ms, 'stallMaxMs': stalls.stop(), ...?extra});
    }

    // Search: the field is in the title bar; type three letters one at a time, as a person does.
    expect(find.textContaining('Xylo'), findsNothing, reason: 'the marker word is only in search results');
    // Without this the live binding has no text input and enterText types nothing (the older perf test's
    // "search results" scroll never had results for that reason).
    tester.testTextInput.register();
    await tester.tap(find.byType(TextField).first, warnIfMissed: false);
    await runFor(tester, const Duration(milliseconds: 500));
    await measure('search typing "xyl"', () async {
      final field = find.byType(TextField).first;
      final clock = Stopwatch()..start();
      int? firstResult, lastKey, settled;
      var matches = 0, changedAt = 0;
      // Keys at 0, 120 and 240 ms; frames every 4 ms until the results stop changing for 300 ms.
      final keys = {0: 'x', 120: 'xy', 240: 'xyl'};
      while (clock.elapsedMilliseconds < 6000) {
        final at = clock.elapsedMilliseconds;
        final key = keys.entries.where((e) => at >= e.key && !(lastKeyDone[e.key] ?? false)).firstOrNull;
        if (key != null) {
          lastKeyDone[key.key] = true;
          await tester.enterText(field, key.value);
          if (key.key == 240) lastKey = clock.elapsedMilliseconds;
        }
        await tester.pump(const Duration(milliseconds: 4));
        final now = find.textContaining('Xylo').evaluate().length;
        if (now > 0) firstResult ??= clock.elapsedMilliseconds;
        if (now != matches) {
          matches = now;
          changedAt = clock.elapsedMilliseconds;
        }
        if (lastKey != null && firstResult != null && clock.elapsedMilliseconds - changedAt > 300) {
          settled = changedAt;
          break;
        }
      }
      final afterLast = settled == null || lastKey == null ? -1 : (settled - lastKey).clamp(0, 99999);
      perf.budget('search results settled after last key ms', afterLast, budgetSearchResultsMs);
      return {
        'firstResultFromFirstKeyMs': firstResult ?? -1,
        'settledAfterLastKeyMs': afterLast,
        'resultRowsBuilt': matches,
      };
    });
    FocusManager.instance.primaryFocus?.unfocus();
    await runFor(tester, const Duration(milliseconds: 500));

    await measure('open All Songs', () async {
      ShellScope.of(tester.element(find.byType(PageScaffold).first)).openCollection(c.allSongs);
      await runFor(tester, const Duration(milliseconds: 1200));
      return null;
    });
    await measure('wheel scroll All Songs', () async {
      await wheel(tester, ticks: 60);
      return null;
    });
    await measure('wheel scroll sidebar library', () async {
      await wheel(tester, at: const Offset(150, 650));
      return null;
    });
    perf.report('memory', rssMiB());
    perf.save();
    if (!kProfileMode) {
      markTestSkipped('numbers only mean something in profile mode');
    }
  });
}

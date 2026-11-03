import 'package:flutter/material.dart';
import 'package:riflay/services/beta_features.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/services/visualizer_levels.dart';
import 'package:riflay/ui/widgets/audio_reactive_view.dart';
import 'package:riflay/ui/widgets/audio_visualizer.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _PlayingController extends PlayerController {
  @override
  bool get showsPlaying => true;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'features.audioVisualizer': true});
    await BetaFeatures.instance.reload();
    await LayoutPrefs.instance.reset();
  });

  testWidgets('switching controllers clears the previous audio and releases its meter', (tester) async {
    final first = _PlayingController();
    final second = _PlayingController();
    final releaseOtherView = first.audio.watchVisualizer();
    late VisualizerLevels display;
    final meter = AudioReactiveView(
      builder: (_, levels) {
        display = levels;
        return const SizedBox.shrink();
      },
    );
    Widget view(PlayerController controller) => PlayerScope(
      controller: controller,
      child: MaterialApp(home: meter),
    );

    await tester.pumpWidget(view(first));
    first.audio.visualizerLevels.add('-12');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 17)); // one 60 fps step
    expect(display.value.last, greaterThan(0));
    // Another visible decoration may already be metering the new controller.
    second.audio.visualizerLevels.add('-45');
    await tester.pumpWidget(view(second));
    expect(first.audio.visualizerActive, isTrue, reason: 'the other view keeps its meter');
    releaseOtherView();
    expect(first.audio.visualizerActive, isFalse);
    expect(second.audio.visualizerActive, isTrue);
    expect(display.value, everyElement(0));
    expect(display.backgroundEnergy, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    first.dispose();
    second.dispose();
  });

  testWidgets('bit-perfect off then expand and close keeps metering safe', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final c = _PlayingController();
    c.audio.bitPerfect = true;
    final navigator = GlobalKey<NavigatorState>();
    Widget meter() => AudioReactiveView(
      builder: (_, levels) => SizedBox.square(
        dimension: 200,
        child: VisualizerCanvas(levels: levels, color: Colors.blue, style: VisualizerStyle.wave),
      ),
    );
    await tester.pumpWidget(
      PlayerScope(
        controller: c,
        child: MaterialApp(
          navigatorKey: navigator,
          home: Scaffold(body: meter()),
        ),
      ),
    );
    expect(c.audio.visualizerActive, isFalse);
    final changed = c.audio.setBitPerfect(false);
    await tester.pump(const Duration(milliseconds: 100));
    await changed;
    expect(c.audio.visualizerActive, isTrue);
    navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => Scaffold(body: meter())));
    await tester.pumpAndSettle();
    c.audio.visualizerLevels.add('-12');
    await tester.pump();
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });

  testWidgets('hidden, disabled and reduced-motion views stop and can resume', (tester) async {
    final c = _PlayingController();
    late VisualizerLevels display;
    Widget view({bool visible = true, bool enabled = true, bool reduceMotion = false}) => PlayerScope(
      controller: c,
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: TickerMode(
            enabled: visible,
            child: AudioReactiveView(
              enabled: enabled,
              builder: (_, levels) {
                display = levels;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(view());
    for (final inactive in [view(visible: false), view(enabled: false), view(reduceMotion: true)]) {
      expect(c.audio.visualizerActive, isTrue);
      c.audio.visualizerLevels.add('-12');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 17)); // one 60 fps step
      expect(display.value.last, greaterThan(0));
      expect(display.value.last, lessThan(c.audio.visualizerLevels.value.last));

      await tester.pumpWidget(inactive);
      expect(c.audio.visualizerActive, isFalse);
      expect(display.value, everyElement(0));
      expect(display.backgroundEnergy, 0);
      await tester.pumpAndSettle();
      await tester.pumpWidget(view());
    }
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(c.audio.visualizerActive, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(c.audio.visualizerActive, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(c.audio.visualizerActive, isFalse);
    c.dispose();
    expect(tester.takeException(), isNull);
  });
}

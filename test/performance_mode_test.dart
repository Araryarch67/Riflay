import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/appearance.dart';
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/ui/widgets/audio_reactive_view.dart';
import 'package:riflay/ui/widgets/controls.dart';
import 'package:riflay/ui/widgets/marquee_text.dart';
import 'package:riflay/ui/widgets/player_backdrop.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _PlayingController extends PlayerController {
  @override
  bool get showsPlaying => true;
}

void main() {
  final prefs = LayoutPrefs.instance;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Appearance.instance.reset();
    await prefs.setPerformance(PerformanceMode.balanced);
    await prefs.reset();
  });
  tearDown(() async {
    await prefs.setPerformance(PerformanceMode.balanced);
    await Appearance.instance.reset();
  });

  test('balanced is the default and the choice is saved and restored', () async {
    expect(prefs.performance, PerformanceMode.balanced);
    expect(LayoutPrefs.lightweight, isFalse);
    await prefs.setPerformance(PerformanceMode.heavy);
    expect(LayoutPrefs.heavy, isTrue);
    final saved = jsonDecode(jsonEncode(prefs.toJson())) as Map<String, dynamic>;
    expect(saved['performance'], 'heavy');
    prefs.restore(const {});
    expect(prefs.performance, PerformanceMode.balanced);
    prefs.restore(saved);
    expect(prefs.performance, PerformanceMode.heavy);
    prefs.restore({'performance': 'nonsense'});
    expect(prefs.performance, PerformanceMode.balanced);
  });

  test('lightweight caps motion without touching the saved choices', () async {
    await prefs.setMotion(Motion.full);
    await prefs.setPerformance(PerformanceMode.lightweight);
    expect(LayoutPrefs.effectiveMotion, Motion.off);
    expect(LayoutPrefs.moves, isFalse);
    expect(prefs.motion, Motion.full);
    await prefs.setPerformance(PerformanceMode.balanced);
    expect(LayoutPrefs.effectiveMotion, Motion.full);
  });

  test('Reset layout keeps the performance choice and does not count as a change', () async {
    await prefs.setPerformance(PerformanceMode.lightweight);
    expect(prefs.isCustomised, isFalse);
    await prefs.reset();
    expect(prefs.performance, PerformanceMode.lightweight);
  });

  testWidgets('lightweight keeps the audio analysis in standby', (tester) async {
    await prefs.setVisualizer(true);
    final c = _PlayingController();
    Widget view() => PlayerScope(
      controller: c,
      child: MaterialApp(home: AudioReactiveView(builder: (_, _) => const SizedBox.shrink())),
    );
    await tester.pumpWidget(view());
    expect(c.audio.visualizerActive, isTrue);
    await prefs.setPerformance(PerformanceMode.lightweight);
    await tester.pumpWidget(view());
    expect(c.audio.visualizerActive, isFalse);
    await prefs.setPerformance(PerformanceMode.balanced);
    await tester.pumpWidget(view());
    expect(c.audio.visualizerActive, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });

  testWidgets('lightweight draws no abstract backdrop', (tester) async {
    await Appearance.instance.setNowPlaying(NowPlayingBackground.values.firstWhere((v) => v.isAbstract));
    Widget host() => const MaterialApp(home: PlayerBackdrop(coverColor: Colors.pink));
    await tester.pumpWidget(host());
    expect(find.descendant(of: find.byType(PlayerBackdrop), matching: find.byType(CustomPaint)), findsWidgets);
    await prefs.setPerformance(PerformanceMode.lightweight);
    await tester.pumpWidget(host());
    expect(find.descendant(of: find.byType(PlayerBackdrop), matching: find.byType(CustomPaint)), findsNothing);
  });

  testWidgets('lightweight stops the marquee and the equalizer icon', (tester) async {
    await prefs.setPerformance(PerformanceMode.lightweight);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SizedBox(width: 100, child: MarqueeText('A very long song title that cannot possibly fit in here')),
              EqualizerIcon(playing: true),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}

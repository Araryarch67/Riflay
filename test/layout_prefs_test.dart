import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/ui/pages/layout_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final p = LayoutPrefs.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await p.reset();
  });

  test('defaults use capsule navigation and standard player appearance', () {
    expect(p.visualizer, isFalse);
    expect(p.visualizerStyle, VisualizerStyle.pulse);
    expect(p.visualizerCoverShape, VisualizerCoverShape.flower);
    expect(p.tabBar, TabBarStyle.capsule);
    expect(p.corners, CornerStyle.rounded);
    expect(p.density, Density.comfortable);
    expect(p.coverSize, CoverSize.medium);
    expect(p.homeOrder, HomeSection.values);
    expect(p.homeHidden, isEmpty);
    expect(p.progressBar, ProgressBarStyle.thin);
    expect(p.playButton, PlayButtonShape.circle);
    expect(p.showQualityBadge, isTrue);
    expect(p.dimUnsungLyrics, isTrue);
    expect(p.motion, Motion.full);
    expect(p.pageMotion, PageMotionStyle.diamondReveal);
    expect(p.pageSpeed, PageMotionSpeed.relaxed);
    expect(p.progressShape, ProgressBarShape.wavy);
    expect(p.isCustomised, isFalse);
    expect(LayoutPrefs.radius(8), 8);
    expect(LayoutPrefs.dur(const Duration(milliseconds: 200)), const Duration(milliseconds: 200));
  });

  test('flower play button and straight seek override persist independently', () async {
    await p.setPlayButton(PlayButtonShape.flower);
    await p.setProgressShape(ProgressBarShape.straight);
    await p.load();
    expect(p.playButton, PlayButtonShape.flower);
    expect(p.progressShape, ProgressBarShape.straight);
    await p.reset();
    expect(p.playButton, PlayButtonShape.circle);
    expect(p.progressShape, ProgressBarShape.wavy);
  });

  test('visualizer choice persists and reset returns to the original player', () async {
    await p.setDesktopBar(DesktopBarStyle.compact);
    await p.setVisualizer(true);
    await p.setVisualizerStyle(VisualizerStyle.dots);
    await p.load();
    expect(p.desktopBar, DesktopBarStyle.compact);
    expect(p.visualizer, isTrue);
    expect(p.visualizerStyle, VisualizerStyle.dots);
    await p.reset();
    expect(p.visualizer, isFalse);
    p.restore({'visualizerStyle': 'future-style'});
    expect(p.visualizerStyle, VisualizerStyle.pulse);
  });

  test('cover shape persists independently of visualizer enablement and defaults safely', () async {
    await p.setVisualizerCoverShape(VisualizerCoverShape.square);
    await p.load();
    expect(p.visualizerCoverShape, VisualizerCoverShape.square);
    expect(p.visualizer, isFalse);
    p.restore({'visualizerCoverShape': 'future-shape'});
    expect(p.visualizerCoverShape, VisualizerCoverShape.flower);
    await p.reset();
    expect(p.pageMotion, PageMotionStyle.diamondReveal);
    expect(p.pageSpeed, PageMotionSpeed.relaxed);
    expect(p.progressShape, ProgressBarShape.wavy);
  });

  test('old visualizer layouts migrate to Pulse; new choices still persist', () async {
    p.restore({'visualizer': true, 'visualizerStyle': 'wave'});
    expect(p.visualizerStyle, VisualizerStyle.pulse);
    await p.setVisualizerStyle(VisualizerStyle.wave);
    await p.load();
    expect(p.visualizerStyle, VisualizerStyle.wave);
  });

  test('visualizer radius and thickness persist, clamp and reset', () async {
    await p.setVisualizerRadius(2.1);
    await p.setVisualizerThickness(5.5);
    await p.load();
    expect(p.visualizerRadius, 2.1);
    expect(p.visualizerThickness, 5.5);
    await p.setVisualizerRadius(99);
    await p.setVisualizerThickness(-1);
    expect(p.visualizerRadius, 2.5);
    expect(p.visualizerThickness, 1);
    await p.reset();
    expect(p.visualizerRadius, 1.6);
    expect(p.visualizerThickness, 3);
  });

  test('corners scale one radius token', () async {
    await p.setCorners(CornerStyle.square);
    expect(LayoutPrefs.radius(8), 0);
    await p.setCorners(CornerStyle.extraRound);
    expect(LayoutPrefs.radius(8), 16);
  });

  test('motion: reduced shortens, off removes', () async {
    const d = Duration(milliseconds: 300);
    await p.setMotion(Motion.reduced);
    expect(LayoutPrefs.dur(d), lessThan(d));
    expect(LayoutPrefs.moves, isFalse);
    await p.setMotion(Motion.off);
    expect(LayoutPrefs.dur(d), Duration.zero);
  });

  test('saved settings come back, and reset clears them', () async {
    await p.setCorners(CornerStyle.square);
    await p.setHomeSectionShown(HomeSection.artists, false);
    await p.moveHomeSection(6, 0);
    final saved = p.toJson();
    await p.reset();
    expect(p.isCustomised, isFalse);
    p.restore(saved);
    expect(p.corners, CornerStyle.square);
    expect(p.homeShown.first, HomeSection.recentlyAdded);
    expect(p.homeShown, isNot(contains(HomeSection.artists)));
    expect(p.isCustomised, isTrue);
  });

  test('unknown or missing values fall back; new sections join in', () {
    p.restore({
      'corners': 'pointy',
      'homeOrder': ['albums', 'nonsense', 'albums', 'quickPicks'],
      'homeHidden': ['nonsense', 'discover'],
    });
    expect(p.corners, CornerStyle.rounded);
    expect(p.homeOrder.toSet(), HomeSection.values.toSet());
    expect(p.homeOrder.length, HomeSection.values.length);
    expect(p.homeHidden, {HomeSection.discover});
  });

  test('classic balanced preserves theme fast path, while corners still apply', () async {
    final base = ThemeData();
    await p.setPageMotion(PageMotionStyle.classic);
    await p.setPageSpeed(PageMotionSpeed.balanced);
    expect(identical(p.themed(base), base), isTrue);
    await p.setCorners(CornerStyle.square);
    final shape = p.themed(base).dialogTheme.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.zero);
  });

  testWidgets('Layout settings: change a choice and reset', (tester) async {
    tester.view.physicalSize = const Size(900, 3400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: LayoutSettings())),
      ),
    );
    expect(find.text('Corners'), findsOneWidget);
    expect(find.text('Rounded'), findsOneWidget);
    await tester.runAsync(() => p.setCorners(CornerStyle.square));
    await tester.pump();
    expect(find.text('Square'), findsOneWidget);
    await tester.tap(find.text('Reset layout to default'));
    await tester.pump();
    expect(p.corners, CornerStyle.rounded);
    // Hiding a section is a switch on its row.
    await tester.tap(find.widgetWithText(SwitchListTile, 'Artists'));
    await tester.pump();
    expect(p.homeHidden, {HomeSection.artists});
  });
}

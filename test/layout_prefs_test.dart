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

  test('defaults are how the app has always looked', () {
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
    expect(p.isCustomised, isFalse);
    expect(LayoutPrefs.radius(8), 8);
    expect(LayoutPrefs.dur(const Duration(milliseconds: 200)), const Duration(milliseconds: 200));
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

  test('themed theme is unchanged by the defaults, and follows square corners', () async {
    final base = ThemeData();
    expect(identical(p.themed(base), base), isTrue);
    await p.setCorners(CornerStyle.square);
    final shape = p.themed(base).dialogTheme.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.zero);
  });

  testWidgets('Layout settings: change a choice and reset', (tester) async {
    tester.view.physicalSize = const Size(900, 2200);
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

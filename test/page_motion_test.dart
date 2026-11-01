import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/services/page_motion.dart';
import 'package:riflay/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final prefs = LayoutPrefs.instance;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await prefs.reset();
  });
  tearDown(prefs.reset);

  test('circular reveal starts at the center and fully covers every aspect ratio', () {
    for (final size in [const Size(390, 844), const Size(1920, 1080), const Size(500, 300)]) {
      Path path(double progress) => PageRevealClipper(
        progress: AlwaysStoppedAnimation(progress),
        style: PageMotionStyle.circularReveal,
      ).getClip(size);
      final center = (Offset.zero & size).center;
      expect(path(0).getBounds().isEmpty, isTrue);
      expect(path(0.15).contains(center), isTrue);
      expect(path(0.15).contains(const Offset(1, 1)), isFalse);
      final bounds = path(0.3).getBounds();
      expect(bounds.width, closeTo(bounds.height, 0.001), reason: 'a circle, not an aspect-ratio-dependent oval');
      for (final point in [
        const Offset(0.1, 0.1),
        Offset(size.width - 0.1, 0.1),
        Offset(0.1, size.height - 0.1),
        Offset(size.width - 0.1, size.height - 0.1),
      ]) {
        expect(path(1).contains(point), isTrue);
      }
    }
  });

  test('every reveal is empty at zero and shows the whole page at completion', () {
    for (final style in [
      PageMotionStyle.circularReveal,
      PageMotionStyle.reveal,
      PageMotionStyle.wipe,
      PageMotionStyle.diamondReveal,
    ]) {
      const size = Size(700, 400);
      final closed = PageRevealClipper(progress: const AlwaysStoppedAnimation(0), style: style).getClip(size);
      final open = PageRevealClipper(progress: const AlwaysStoppedAnimation(1), style: style).getClip(size);
      expect(closed.getBounds().isEmpty, isTrue);
      expect(open.getBounds(), Offset.zero & size);
    }
  });

  test('saved motion style and speed restore; Reduced and Off always win', () async {
    await prefs.setPageMotion(PageMotionStyle.circularReveal);
    await prefs.setPageSpeed(PageMotionSpeed.relaxed);
    await prefs.load();
    expect(prefs.pageMotion, PageMotionStyle.circularReveal);
    expect(prefs.pageSpeed, PageMotionSpeed.relaxed);
    final full = LayoutPrefs.pageDuration();
    await prefs.setMotion(Motion.reduced);
    expect(LayoutPrefs.pageDuration(), lessThan(full));
    await prefs.setMotion(Motion.off);
    expect(LayoutPrefs.pageDuration(), Duration.zero);
    const child = SizedBox();
    expect(
      PageMotion.build(
        const AlwaysStoppedAnimation(0.5),
        const AlwaysStoppedAnimation(0),
        child,
        style: PageMotionStyle.circularReveal,
        disabled: true,
      ),
      same(child),
    );
    final reduced = PageMotion.build(
      const AlwaysStoppedAnimation(0.5),
      const AlwaysStoppedAnimation(0),
      child,
      style: PageMotionStyle.circularReveal,
      reduced: true,
    );
    expect(reduced, isA<FadeTransition>());
  });

  for (final style in PageMotionStyle.values) {
    testWidgets('${style.label} navigates forward and back without clipping the finished page', (tester) async {
      await prefs.setPageMotion(style);
      await tester.pumpWidget(
        MaterialApp(
          theme: appThemeNow(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const Scaffold(appBar: null, body: Center(child: BackButton())),
                    ),
                  ),
                  child: const Text('Open page'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open page'));
      await tester.pump();
      await tester.pump(LayoutPrefs.pageDuration() ~/ 2);
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(find.byType(BackButton), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Open page'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

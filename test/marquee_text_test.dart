import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/ui/widgets/marquee_text.dart';

const _short = 'Short';
const _long = 'A very long song title that cannot possibly fit in this narrow space at all';

Widget _host(String text, {bool disableAnimations = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: Scaffold(
      body: Center(
        child: SizedBox(width: 200, child: MarqueeText(text, key: const ValueKey('m'))),
      ),
    ),
  ),
);

final _strip = find.descendant(of: find.byType(MarqueeText), matching: find.byType(Transform));

/// How far the scrolling copy has moved left; 0 while still.
double _shift(WidgetTester tester) {
  if (_strip.evaluate().isEmpty) return 0;
  return -tester.widget<Transform>(_strip.first).transform.getTranslation().x;
}

bool _animating(WidgetTester tester) => tester.binding.hasScheduledFrame;

void main() {
  setUp(() => LayoutPrefs.instance.motion = Motion.full);
  tearDown(() => LayoutPrefs.instance.motion = Motion.full);

  testWidgets('text that fits stays still', (tester) async {
    await tester.pumpWidget(_host(_short));
    await tester.pump(const Duration(seconds: 5));
    expect(_shift(tester), 0);
    expect(_strip, findsNothing);
    expect(_animating(tester), isFalse);
    expect(find.text(_short), findsOneWidget);
  });

  testWidgets('long text rests, then scrolls; one label for screen readers', (tester) async {
    await tester.pumpWidget(_host(_long));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(_shift(tester), 0);
    await tester.pump(const Duration(seconds: 2));
    expect(_shift(tester), greaterThan(10));
    expect(find.bySemanticsLabel(_long), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('less motion cuts it off with an ellipsis', (tester) async {
    LayoutPrefs.instance.motion = Motion.reduced;
    await tester.pumpWidget(_host(_long));
    await tester.pump(const Duration(seconds: 5));
    expect(_strip, findsNothing);
    expect(tester.widget<Text>(find.text(_long)).overflow, TextOverflow.ellipsis);
    expect(_animating(tester), isFalse);

    LayoutPrefs.instance.motion = Motion.full;
    await tester.pumpWidget(_host(_long, disableAnimations: true));
    await tester.pump(const Duration(seconds: 5));
    expect(_strip, findsNothing);
    expect(tester.widget<Text>(find.text(_long)).overflow, TextOverflow.ellipsis);
  });

  testWidgets('a new title starts again from the beginning', (tester) async {
    await tester.pumpWidget(_host(_long));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(_shift(tester), greaterThan(10));

    await tester.pumpWidget(_host('$_long, the sequel'));
    await tester.pump();
    expect(_shift(tester), 0);
    await tester.pump(const Duration(seconds: 1));
    expect(_shift(tester), 0);
    await tester.pump(const Duration(seconds: 2));
    expect(_shift(tester), greaterThan(10));

    // And a short one stops it.
    await tester.pumpWidget(_host(_short));
    await tester.pump(const Duration(seconds: 3));
    expect(_strip, findsNothing);
    expect(_animating(tester), isFalse);
  });

  testWidgets('the width of a title is measured once, not on every tick', (tester) async {
    MarqueeText.clearMeasurements();
    final before = MarqueeText.measurements;
    await tester.pumpWidget(_host(_long));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_shift(tester), greaterThan(0));
    expect(MarqueeText.measurements - before, 1);
    // The same title elsewhere (another bar, another page) reuses the width.
    await tester.pumpWidget(_host(_long));
    expect(MarqueeText.measurements - before, 1);
    // A new title is a new measurement.
    await tester.pumpWidget(_host('$_long!'));
    expect(MarqueeText.measurements - before, 2);
  });
}

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/ui/widgets/auto_hide_bar.dart';

void main() {
  var taps = 0;

  Widget app({required bool enabled}) => MaterialApp(
    home: Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: Colors.black)),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AutoHideBar(
              edge: AxisDirection.up,
              enabled: enabled,
              child: SizedBox(
                height: 48,
                child: TextButton(onPressed: () => taps++, child: const Text('bar')),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  double opacity(WidgetTester tester) =>
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;
  Offset slide(WidgetTester tester) => tester.widget<AnimatedSlide>(find.byType(AnimatedSlide)).offset;

  testWidgets('off: always shown', (tester) async {
    await tester.pumpWidget(app(enabled: false));
    await tester.pump(const Duration(seconds: 5));
    expect(opacity(tester), 1);
    expect(slide(tester), Offset.zero);
  });

  testWidgets('on: shows a moment, hides, comes back on hover and goes after the pointer leaves', (tester) async {
    taps = 0;
    await tester.pumpWidget(app(enabled: true));
    expect(opacity(tester), 1, reason: 'seen at first');
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(opacity(tester), 0);
    expect(slide(tester), const Offset(0, -1));

    // Hidden, it takes no clicks.
    await tester.tapAt(const Offset(400, 24));
    expect(taps, 0);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(400, 300));
    await mouse.moveTo(const Offset(400, 24));
    await tester.pumpAndSettle();
    expect(opacity(tester), 1);
    expect(slide(tester), Offset.zero);
    await tester.tap(find.text('bar'));
    expect(taps, 1);

    await mouse.moveTo(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 500));
    expect(opacity(tester), 1, reason: 'lingers a little');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(opacity(tester), 0);
    await mouse.removePointer();
  });

  testWidgets('turning it on later shows it first, and the child keeps its state', (tester) async {
    await tester.pumpWidget(app(enabled: false));
    final element = tester.element(find.byType(TextButton));
    await tester.pumpWidget(app(enabled: true));
    expect(tester.element(find.byType(TextButton)), same(element));
    expect(opacity(tester), 1);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(opacity(tester), 0);
  });
}

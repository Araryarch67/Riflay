import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/ui/widgets/smooth_scroll.dart';

void main() {
  Future<SmoothScrollController> list(WidgetTester tester) async {
    final controller = SmoothScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 600,
          child: ListView.builder(
            controller: controller,
            itemCount: 500,
            itemBuilder: (_, i) => SizedBox(height: 50, child: Text('$i')),
          ),
        ),
      ),
    );
    return controller;
  }

  Future<void> wheel(WidgetTester tester, double dy, {int times = 1}) async {
    final at = tester.getCenter(find.byType(ListView));
    for (var i = 0; i < times; i++) {
      await tester.sendEventToBinding(PointerScrollEvent(position: at, scrollDelta: Offset(0, dy)));
    }
  }

  testWidgets('one huge wheel event moves a notch, not a page', (tester) async {
    final controller = await list(tester);
    await wheel(tester, 5000);
    await tester.pumpAndSettle();
    expect(controller.offset, 160);
  });

  testWidgets('a burst of ticks cannot pile up into a jump past the screen', (tester) async {
    final controller = await list(tester);
    await wheel(tester, 120, times: 40);
    await tester.pumpAndSettle();
    expect(controller.offset, lessThanOrEqualTo(360 + 1), reason: 'at most 0.6 of the 600 px viewport ahead');
    expect(controller.offset, greaterThan(0));
  });

  testWidgets('turning the wheel back starts from where the list is', (tester) async {
    final controller = await list(tester);
    controller.jumpTo(1000);
    await wheel(tester, 120, times: 3);
    await tester.pump(const Duration(milliseconds: 16));
    await wheel(tester, -120);
    await tester.pumpAndSettle();
    expect(controller.offset, lessThan(1000), reason: 'back up from where it was, not from where it was headed');
  });
}

import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/ui/pages/search/search_box.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('desktop mouse click on recent search submits it immediately', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      SharedPreferences.setMockInitialValues({
        'search.recent.v1': ['One More Time'],
      });
      final controller = TextEditingController();
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      final submitted = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchBox(
              controller: controller,
              focusNode: focus,
              onBar: true,
              onChanged: (_) {},
              onSubmitted: submitted.add,
            ),
          ),
        ),
      );
      focus.requestFocus();
      await tester.pumpAndSettle();
      expect(find.text('One More Time'), findsOneWidget);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer();
      await mouse.down(tester.getCenter(find.text('One More Time')));
      await tester.pump();
      await mouse.up();
      await tester.pumpAndSettle();
      expect(submitted, ['One More Time']);
      expect(controller.text, 'One More Time');
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

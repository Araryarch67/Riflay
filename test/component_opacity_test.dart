import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/main.dart';
import 'package:riflay/services/appearance.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/ui/widgets/title_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('component opacity includes artwork, text, controls and route overlays', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final look = Appearance.instance;
    await look.reset();
    await look.setComponentOpacity(0.6);
    final c = PlayerController();
    final capture = GlobalKey();
    debugCustomTitleBar = false;
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(() async {
      debugCustomTitleBar = null;
      tester.view.reset();
      await look.reset();
      c.dispose();
    });
    await tester.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: RiflayApp(controller: c),
      ),
    );
    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    navigator.push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          body: Center(
            child: Column(
              children: [
                const SizedBox.square(dimension: 100, child: ColoredBox(color: Colors.white)),
                const Text('Opaque text'),
                const Icon(Icons.music_note),
                FilledButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) =>
                        const AlertDialog(title: Text('Overlay'), content: Text('Dialogs share component opacity')),
                  ),
                  child: const Text('Open dialog'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open dialog'));
    await tester.pumpAndSettle();
    final root = find.byKey(const ValueKey('desktop-component-opacity'));
    expect(find.descendant(of: root, matching: find.byType(AlertDialog)), findsOneWidget);
    expect(tester.widget<Opacity>(root).opacity, 0.6);
    await tester.runAsync(() async {
      final boundary = capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
      var maxAlpha = 0;
      for (var i = 3; i < bytes.length; i += 4) {
        if (bytes[i] > maxAlpha) maxAlpha = bytes[i];
      }
      image.dispose();
      expect(maxAlpha, inInclusiveRange(152, 154), reason: 'even opaque text, cards and overlays must be translucent');
    });
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('component opacity persists independently of background opacity', () async {
    SharedPreferences.setMockInitialValues({});
    final look = Appearance.instance;
    await look.reset();
    await look.setWindowOpacity(0.8);
    await look.setComponentOpacity(0.55);
    await look.load();
    expect(look.componentOpacity, 0.55);
    expect(look.windowOpacity, 0.8);
    await look.reset();
    expect(look.componentOpacity, 1);
    expect(look.windowOpacity, 1);
  });
}

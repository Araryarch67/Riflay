import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/main.dart';
import 'package:riflay/services/appearance.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/ui/theme.dart';
import 'package:riflay/ui/widgets/title_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('component opacity fades window, panel, card and menu fills, never artwork, text or controls', (
    tester,
  ) async {
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
        builder: (context) => const Scaffold(
          body: Center(
            child: SizedBox.square(dimension: 100, child: ColoredBox(color: Colors.white)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // No whole-app layer: that faded every picture and line of text, and cost an offscreen pass each frame.
    expect(find.byKey(const ValueKey('desktop-component-opacity')), findsNothing);
    final colors = AppColorsScope.current();
    expect(colors.background.a, closeTo(look.palette.background.a * look.windowOpacity * 0.6, 0.01));
    expect(colors.panel.a, closeTo(look.palette.panel.a * look.windowOpacity * 0.6, 0.01));
    expect(colors.elevated.a, closeTo(look.palette.elevated.a * 0.6, 0.01));
    expect(colors.menu.a, closeTo(look.palette.menu.a * 0.6, 0.01));
    expect(colors.textPrimary.a, look.palette.textPrimary.a);
    expect(colors.accent.a, look.palette.accent.a);
    await tester.runAsync(() async {
      final boundary = capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
      // The middle of the white square, standing in for artwork.
      final i = (350 * image.width + 500) * 4;
      expect(bytes.sublist(i, i + 4), [255, 255, 255, 255], reason: 'artwork stays fully opaque');
      image.dispose();
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

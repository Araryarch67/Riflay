import 'dart:typed_data';

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/appearance.dart';
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/ui/widgets/player_backdrop.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final look = Appearance.instance;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await look.reset();
    await LayoutPrefs.instance.reset();
  });
  tearDown(() async {
    debugBackdropFallback = false;
    await look.reset();
  });

  test('the backdrop fragment program compiles and loads from the asset bundle', () async {
    final program = await ui.FragmentProgram.fromAsset('shaders/backdrop.frag');
    program.fragmentShader().dispose();
  });

  testWidgets('the shader paints the same look as the CPU painter', (tester) async {
    await tester.runAsync(() => ui.FragmentProgram.fromAsset('shaders/backdrop.frag'));
    Future<Uint8List> render(NowPlayingBackground style, {required bool fallback}) async {
      debugBackdropFallback = fallback;
      await look.setNowPlaying(style);
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: RepaintBoundary(
              key: key,
              child: const SizedBox(width: 320, height: 480, child: PlayerBackdrop(coverColor: Color(0xffb64d7b))),
            ),
          ),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        image.dispose();
        return data!.buffer.asUint8List();
      });
      return bytes!;
    }

    for (final style in NowPlayingBackground.values.where((v) => v.isAbstract)) {
      final cpu = await render(style, fallback: true);
      final gpu = await render(style, fallback: false);
      var total = 0, worst = 0;
      for (var i = 0; i < cpu.length; i++) {
        if (i % 4 == 3) continue;
        final d = (cpu[i] - gpu[i]).abs();
        total += d;
        if (d > worst) worst = d;
      }
      final mean = total / (cpu.length * 0.75);
      // ignore: avoid_print
      print('${style.name}: mean diff ${mean.toStringAsFixed(3)} / 255, worst $worst');
      expect(mean, lessThan(1.5), reason: style.name);
      expect(worst, lessThan(12), reason: style.name);
    }
  });
}

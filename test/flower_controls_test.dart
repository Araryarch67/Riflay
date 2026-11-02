import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/ui/widgets/controls.dart';
import 'package:riflay/ui/widgets/wavy_seek_track.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LayoutPrefs.instance.reset();
  });
  tearDown(LayoutPrefs.instance.reset);

  testWidgets('Flower is an extra play shape and retains its hit target and loading state', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: PlayButton(
            playing: false,
            size: 80,
            onPressed: () => taps++,
            color: Colors.white,
            iconColor: Colors.black,
          ),
        ),
      ),
    );
    await LayoutPrefs.instance.setPlayButton(PlayButtonShape.flower);
    await tester.pump();
    expect(tester.getSize(find.byType(PlayButton)), const Size(80, 80));
    await tester.tap(find.byType(PlayButton));
    await tester.pump();
    expect(taps, 1);
    for (final shape in PlayButtonShape.values) {
      await LayoutPrefs.instance.setPlayButton(shape);
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: PlayButton(
              playing: true,
              loading: true,
              size: 80,
              onPressed: null,
              color: Colors.white,
              iconColor: Colors.black,
            ),
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.getSize(find.byType(PlayButton)), const Size(80, 80));
    }
    expect(PlayButtonShape.values.map((s) => s.label), containsAll(['Circle', 'Rounded square', 'Flower']));
    expect(tester.takeException(), isNull);
  });

  for (final direction in [TextDirection.ltr, TextDirection.rtl]) {
    testWidgets('wavy seek track bends only elapsed audio in ${direction.name}', (tester) async {
      final capture = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: direction,
            child: Center(
              child: RepaintBoundary(
                key: capture,
                child: Material(
                  color: Colors.black,
                  child: SizedBox(
                    width: 320,
                    height: 48,
                    child: SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 2,
                        trackShape: const WavySeekTrack(),
                        overlayShape: SliderComponentShape.noOverlay,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                      ),
                      child: Slider(
                        value: .5,
                        onChanged: (_) {},
                        padding: EdgeInsets.zero,
                        activeColor: Colors.white,
                        inactiveColor: const Color(0xff777777),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final pixels = (await tester.runAsync(() async {
        final boundary = capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List().toList();
        const shots = String.fromEnvironment('SHOTS');
        if (shots.isNotEmpty) {
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(shots).create(recursive: true);
          await File('$shots/wavy-${direction.name}.png').writeAsBytes(png!.buffer.asUint8List());
        }
        image.dispose();
        return bytes;
      }))!;
      int above(int from, int to) {
        var found = 0;
        for (var x = from; x < to; x++) {
          for (var y = 17; y <= 20; y++) {
            if (pixels[(y * 320 + x) * 4] > 90) found++;
          }
        }
        return found;
      }

      final left = above(20, 130), right = above(190, 300);
      expect(direction == TextDirection.ltr ? left : right, greaterThan(20), reason: 'elapsed audio has waves');
      expect(direction == TextDirection.ltr ? right : left, 0, reason: 'unplayed audio stays straight');
      expect(tester.takeException(), isNull);
    });
  }
}

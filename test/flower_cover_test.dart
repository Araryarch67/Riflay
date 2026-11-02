import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/visualizer_levels.dart';
import 'package:riflay/ui/widgets/flower_cover.dart';

void main() {
  testWidgets('shared audio repaints the flower and glow, then silence restores its resting shape', (tester) async {
    final levels = VisualizerLevels();
    final capture = GlobalKey();
    addTearDown(levels.dispose);
    var builds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: RepaintBoundary(
            key: capture,
            child: SizedBox.square(
              dimension: 280,
              child: FlowerCover(
                levels: levels,
                color: const Color(0xffa4acab),
                child: Builder(
                  builder: (_) {
                    builds++;
                    return const ColoredBox(color: Colors.white);
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    Future<List<int>> shot(String name) async => (await tester.runAsync(() async {
      final boundary = capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List().toList();
      const folder = String.fromEnvironment('SHOTS');
      if (folder.isNotEmpty) {
        await Directory(folder).create(recursive: true);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$folder/$name.png').writeAsBytes(png!.buffer.asUint8List());
      }
      image.dispose();
      return bytes;
    }))!;
    final resting = await shot('flower-glow-resting');
    levels.addBands(List.filled(VisualizerLevels.samples, 0.85));
    await tester.pump();
    final active = await shot('flower-glow-active');
    expect(active, isNot(resting));
    var outwardPixels = 0;
    for (var i = 0; i < resting.length; i += 4) {
      if (resting[i + 3] < 245 && active[i] > 245 && active[i + 3] > 245) outwardPixels++;
    }
    expect(outwardPixels, greaterThan(100), reason: 'the artwork itself grows gently with measured audio');
    expect(builds, 1, reason: 'the static artwork must not rebuild for audio frames');
    levels.clear();
    await tester.pump();
    expect(await shot('flower-glow-silence'), resting);
    expect(builds, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

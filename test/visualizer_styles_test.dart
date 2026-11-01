import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/services/visualizer_levels.dart';
import 'package:riflay/ui/widgets/audio_visualizer.dart';

void main() {
  for (final cover in [false, true]) {
    testWidgets('ten styles paint distinct ${cover ? 'cover borders' : 'desktop forms'}', (tester) async {
      final levels = VisualizerLevels();
      addTearDown(levels.dispose);
      levels.addBands(List.generate(VisualizerLevels.samples, (i) => 0.3 + 0.25 * math.sin(i * 0.55)));
      final hashes = <String>{};
      for (final style in VisualizerStyle.values) {
        final key = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: RepaintBoundary(
                key: key,
                child: SizedBox(
                  width: cover ? 240 : 360,
                  height: cover ? 240 : 100,
                  child: VisualizerCanvas(
                    levels: levels,
                    color: const Color(0xff27dfbc),
                    style: style,
                    child: cover ? const ColoredBox(color: Color(0xff243942)) : null,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final hash = await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
          final hash = sha256.convert(bytes!.buffer.asUint8List()).toString();
          const shots = String.fromEnvironment('SHOTS');
          if (shots.isNotEmpty) {
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            final folder = Directory(shots)..createSync(recursive: true);
            await File('${folder.path}/${cover ? 'cover' : 'desktop'}-${style.name}.png')
                .writeAsBytes(png!.buffer.asUint8List());
          }
          image.dispose();
          return hash;
        });
        expect(hashes.add(hash!), isTrue, reason: '${style.label} needs its own visual composition');
        expect(tester.takeException(), isNull);
      }
      expect(hashes.length, 10);
    });
  }
}

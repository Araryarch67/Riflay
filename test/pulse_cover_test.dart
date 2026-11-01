import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/services/visualizer_levels.dart';
import 'package:riflay/ui/widgets/audio_visualizer.dart';

void main() {
  testWidgets('Pulse hugs the cover and Orbit adds radial bars on a flower contour', (tester) async {
    final levels = VisualizerLevels();
    addTearDown(levels.dispose);
    final capture = GlobalKey();
    const side = 280;
    Future<List<int>> render({
      double movement = 1.6,
      VisualizerStyle style = VisualizerStyle.pulse,
      String? name,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: const Color(0xff303433),
            body: Center(
              child: RepaintBoundary(
                key: capture,
                child: SizedBox.square(
                  dimension: side.toDouble(),
                  child: VisualizerCanvas(
                    levels: levels,
                    color: style == VisualizerStyle.orbit ? const Color(0xff6be1f5) : const Color(0xffa4acab),
                    style: style,
                    radialMotion: movement,
                    child: const ColoredBox(
                      color: Colors.white,
                      child: Center(child: Icon(Icons.music_note_rounded, color: Color(0xff273734), size: 72)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return (await tester.runAsync(() async {
        final boundary = capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List().toList();
        const shots = String.fromEnvironment('SHOTS');
        if (shots.isNotEmpty && name != null) {
          await Directory(shots).create(recursive: true);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$shots/$name.png').writeAsBytes(png!.buffer.asUint8List());
        }
        image.dispose();
        return rgba;
      }))!;
    }

    int edge(List<int> rgba, double angle) {
      var last = 0;
      for (var r = 40; r < side ~/ 2; r++) {
        final x = (side / 2 + math.cos(angle) * r).round().clamp(0, side - 1);
        final y = (side / 2 + math.sin(angle) * r).round().clamp(0, side - 1);
        final at = (y * side + x) * 4;
        if (rgba[at] > 245 && rgba[at + 1] > 245 && rgba[at + 2] > 245 && rgba[at + 3] > 245) last = r;
      }
      return last;
    }

    final resting = await render(name: 'pulse-resting');
    levels.addBands(List.filled(VisualizerLevels.samples, 0.8));
    levels.beat = 0.6;
    final active = await render(name: 'pulse-cover');
    final peak = edge(active, 0);
    final valley = edge(active, math.pi / 24);
    expect(peak - valley, greaterThan(5), reason: 'the artwork itself must have visible rounded scallops');
    expect(peak, greaterThan(edge(resting, 0) + 5));
    for (var r = 55; r < peak; r++) {
      final at = ((side ~/ 2) * side + side ~/ 2 + r) * 4;
      expect(active[at], greaterThan(245), reason: 'the cover must continue into the wave, without an empty ring');
    }
    final small = await render(movement: 0.5);
    final large = await render(movement: 2.5, name: 'pulse-cover-large');
    expect(edge(large, 0), greaterThan(edge(small, 0) + 8));
    final orbit = await render(style: VisualizerStyle.orbit, name: 'orbit-cover');
    expect(
      edge(orbit, 0) - edge(orbit, math.pi / 24),
      greaterThan(3),
      reason: 'Orbit must clip the artwork to its flower contour too',
    );
    var longestRay = 0;
    var currentRay = 0;
    for (var r = 90; r < side ~/ 2; r++) {
      final at = ((side ~/ 2) * side + side ~/ 2 + r) * 4;
      if (orbit[at + 1] > orbit[at] + 40 && orbit[at + 2] > orbit[at] + 40 && orbit[at + 3] > 200) {
        longestRay = math.max(longestRay, ++currentRay);
      } else {
        currentRay = 0;
      }
    }
    expect(longestRay, greaterThan(12), reason: 'Orbit must draw radial bars, not isolated dots');
    levels.clear();
    final quietOrbit = await render(style: VisualizerStyle.orbit, name: 'orbit-resting');
    expect(quietOrbit, isNot(orbit));
    expect(
      edge(quietOrbit, 0) - edge(quietOrbit, math.pi / 24),
      greaterThanOrEqualTo(2),
      reason: 'The resting Orbit canvas should retain its flower shape',
    );
    expect(find.byType(ClipPath), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

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
  testWidgets('Pulse draws an audio wave around a stable flower cover; Orbit retains radial bars', (tester) async {
    final levels = VisualizerLevels();
    addTearDown(levels.dispose);
    final capture = GlobalKey();
    const side = 280;
    Future<List<int>> render({
      double movement = 1.6,
      VisualizerStyle style = VisualizerStyle.pulse,
      String? name,
      VisualizerCoverShape coverShape = VisualizerCoverShape.flower,
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
                    coverShape: coverShape,
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
    int waveEdge(List<int> rgba, double angle) {
      var last = 0;
      for (var r = 90; r < side ~/ 2; r++) {
        final x = (side / 2 + math.cos(angle) * r).round().clamp(0, side - 1);
        final y = (side / 2 + math.sin(angle) * r).round().clamp(0, side - 1);
        final at = (y * side + x) * 4;
        if (rgba[at] > 130 && rgba[at] < 220 && rgba[at + 1] > 140 && rgba[at + 3] > 220) last = r;
      }
      return last;
    }

    expect(
      edge(active, -math.pi / 2),
      greaterThan(edge(resting, -math.pi / 2)),
      reason: 'the flower cover itself breathes with the music',
    );
    expect(
      edge(active, -math.pi / 2),
      lessThanOrEqualTo(edge(resting, -math.pi / 2) + 5),
      reason: 'cover motion stays subtle inside the filled waveform',
    );
    var filledPixels = 0;
    for (var i = 0; i < 180; i++) {
      final angle = i * math.pi / 90;
      for (var r = edge(active, angle) + 5; r < waveEdge(active, angle) - 3; r++) {
        final x = (side / 2 + math.cos(angle) * r).round();
        final y = (side / 2 + math.sin(angle) * r).round();
        final at = (y * side + x) * 4;
        expect(active.sublist(at, at + 4), [164, 172, 171, 255], reason: 'Pulse fills the space from cover to wave');
        filledPixels++;
      }
    }
    expect(filledPixels, greaterThan(500), reason: 'Pulse is a filled band rather than an outline');
    final radii = List.generate(180, (i) => waveEdge(active, i * math.pi / 90));
    expect(radii.reduce(math.max) - radii.reduce(math.min), greaterThan(8));
    double averageNear(double angle) =>
        List.generate(21, (i) => waveEdge(active, angle + (i - 10) * math.pi / 90)).reduce((a, b) => a + b) / 21;
    expect(averageNear(0), greaterThan(averageNear(-math.pi / 2) + 3), reason: 'right-side waves grow larger');
    expect(averageNear(math.pi), greaterThan(averageNear(math.pi / 2) + 3), reason: 'left-side waves grow larger');
    final crests = <int>[];
    for (var i = 1; i < radii.length - 1; i++) {
      if (radii[i] > radii[i - 1] && radii[i] >= radii[i + 1]) crests.add(i);
    }
    final spacing = List.generate(crests.length - 1, (i) => crests[i + 1] - crests[i]);
    expect(spacing.toSet().length, greaterThan(3), reason: 'crests must not be uniformly spaced');
    final small = await render(movement: 0.5);
    final large = await render(movement: 2.5, name: 'pulse-cover-large');
    final widestGrowth = List.generate(180, (i) {
      final angle = i * math.pi / 90;
      return waveEdge(large, angle) - waveEdge(small, angle);
    }).reduce(math.max);
    expect(widestGrowth, greaterThan(8));
    levels.clear();
    levels.addBands(List.generate(VisualizerLevels.samples, (i) => i < 12 ? 0.9 : 0.05));
    levels.beat = 0;
    final bass = await render(name: 'pulse-bass');
    levels.clear();
    levels.addBands(List.generate(VisualizerLevels.samples, (i) => i < 12 ? 0.05 : 0.9));
    levels.beat = 0;
    final treble = await render(name: 'pulse-treble');
    int bandResponse(List<int> louder, List<int> quieter, double start) => List.generate(30, (i) {
      final angle = start + i * math.pi / 90;
      return waveEdge(louder, angle) - waveEdge(quieter, angle);
    }).reduce(math.max);
    expect(bandResponse(bass, treble, -math.pi / 2), greaterThan(5));
    expect(bandResponse(treble, bass, 0), greaterThan(5));
    levels.clear();
    levels.addBands(List.filled(VisualizerLevels.samples, 0.8));
    levels.beat = 0.6;
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
    final petals = await render(style: VisualizerStyle.petals, name: 'petals-cover');
    expect(edge(petals, 0), edge(orbit, 0), reason: 'Petals and Orbit share the same cover contour');
    expect(petals, isNot(orbit), reason: 'Petals uses fewer, wider radial bars');
    for (final style in [VisualizerStyle.pulse, VisualizerStyle.orbit, VisualizerStyle.petals]) {
      final square = await render(style: style, coverShape: VisualizerCoverShape.square, name: 'square-${style.name}');
      final corner = (225 * side + 225) * 4;
      expect(square.sublist(corner, corner + 4), [
        255,
        255,
        255,
        255,
      ], reason: 'Square artwork keeps its corners in every radial style');
      expect(active[corner], lessThan(245), reason: 'Flower and Square have different cover silhouettes');
    }
    levels.clear();
    final quietOrbit = await render(style: VisualizerStyle.orbit, name: 'orbit-resting');
    expect(quietOrbit, isNot(orbit));
    expect(quietOrbit, resting, reason: 'The resting cover must not change shape across styles');
    expect(await render(style: VisualizerStyle.petals, name: 'petals-resting'), resting);
    expect(
      edge(quietOrbit, 0) - edge(quietOrbit, math.pi / 24),
      greaterThanOrEqualTo(2),
      reason: 'The resting Orbit canvas should retain its flower shape',
    );
    expect(find.byType(ClipPath), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

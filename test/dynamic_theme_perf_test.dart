import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:riflay/main.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/appearance.dart';
import 'package:riflay/services/cover_palette.dart';
import 'package:riflay/services/metadata.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/ui/home_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A 1000 x 1000 JPEG of a diagonal gradient with some noise (so it does not compress to nothing).
Uint8List bigCover() {
  final rnd = math.Random(7);
  final i = img.Image(width: 1000, height: 1000);
  for (final p in i) {
    final t = (p.x + p.y) / 2000;
    p.setRgb(
      (30 + 200 * t + rnd.nextInt(20)).round().clamp(0, 255),
      (120 - 60 * t + rnd.nextInt(20)).round().clamp(0, 255),
      (220 - 180 * t + rnd.nextInt(20)).round().clamp(0, 255),
    );
  }
  return Uint8List.fromList(img.encodeJpg(i, quality: 90));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('colours of a 1000 x 1000 cover: read once, quickly, and remembered', () async {
    final dir = Directory.systemTemp.createTempSync('riflay-dyn');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('test/fixtures/sine.mp3').copySync('${dir.path}/Band - Song.mp3');
    final jpeg = bigCover();
    File('${dir.path}/cover.jpg').writeAsBytesSync(jpeg);
    final track = Track.fromUri(Uri.file('${dir.path}/Band - Song.mp3'));

    await TestWidgetsFlutterBinding.instance.runAsync(() async {
      final sw = Stopwatch()..start();
      final first = await Metadata.coverColors(track);
      final cold = sw.elapsedMilliseconds;
      expect(first, isNotNull, reason: 'the cover should have been found and read');
      sw.reset();
      final again = await Metadata.coverColors(track);
      final warm = sw.elapsedMicroseconds;
      expect(again, same(first), reason: 'the second ask is answered from the cache');
      expect(Metadata.cachedCoverColors(track), same(first));

      // The extraction alone, on the 32 x 32 pixels it is given, inline and in a fresh isolate.
      final px = Uint8List(32 * 32 * 4);
      for (var k = 0; k < px.length; k += 4) {
        px[k] = k % 251;
        px[k + 1] = (k * 7) % 241;
        px[k + 2] = 90;
        px[k + 3] = 255;
      }
      sw.reset();
      for (var n = 0; n < 100; n++) {
        extractCoverColors(px);
      }
      final inline = sw.elapsedMicroseconds / 100;
      sw.reset();
      await Isolate.run(() => extractCoverColors(px));
      final isolate = sw.elapsedMicroseconds;
      debugPrint(
        'PERF 1000x1000 JPEG (${jpeg.length ~/ 1024} KiB): cover colours cold $cold ms, warm $warm us; '
        'extraction alone ${inline.toStringAsFixed(0)} us inline, $isolate us in Isolate.run',
      );
      // Generous: this is a debug-mode VM on a busy machine. It catches decoding at full size or a loop per pixel
      // of the original, which would cost seconds.
      expect(cold, lessThan(1500));
      expect(warm, lessThan(5000));
    });
  });

  testWidgets('one theme transition restyles the app a dozen times, not once per frame', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final a = Appearance.instance;
    await a.reset();
    await a.setTheme(ThemeChoice.dynamic);
    final c = PlayerController();
    var shellBuilds = 0;
    var total = 0;
    final old = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      total++;
      if (element.widget is HomeShell) shellBuilds++;
    };
    addTearDown(() {
      debugOnRebuildDirtyWidget = old;
      tester.view.reset();
    });
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(RiflayApp(controller: c));
    await tester.pump(const Duration(milliseconds: 100));

    a.setCoverColors(const CoverColors(Color(0xFF203080), Color(0xFF40C0FF)));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 700));

    // The transition to a second cover, in 60 fps frames.
    final before = a.palette;
    shellBuilds = 0;
    total = 0;
    var notified = 0;
    a.addListener(() => notified++);
    a.setCoverColors(const CoverColors(Color(0xFFD08020), Color(0xFFE04060)));
    var frames = 0;
    for (var t = 0; t < 800; t += 16) {
      await tester.pump(const Duration(milliseconds: 16));
      frames++;
    }
    debugPrint(
      'PERF transition: $frames frames, $notified restyles, HomeShell built $shellBuilds times, $total widgets',
    );
    expect(a.palette, isNot(before));
    expect(notified, inInclusiveRange(2, 14), reason: 'about a dozen steps, whatever the frame rate');
    expect(shellBuilds, lessThanOrEqualTo(notified));

    // Settled: a second cover with the same look, and nothing changing, rebuild nothing.
    shellBuilds = 0;
    await tester.pump(const Duration(milliseconds: 500));
    expect(shellBuilds, 0, reason: 'no rebuilds once the transition is over');
    await a.reset();
  });
}

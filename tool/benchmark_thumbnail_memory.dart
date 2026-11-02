// Run on the revisions being compared, in separate processes:
// flutter test --no-pub tool/benchmark_thumbnail_memory.dart --reporter expanded
// Optional: --dart-define=COVERS=12 --dart-define=SIDE=2048
// Measures the test process RSS, not release app or GPU memory. Image generation
// happens before sampling; starting RSS and elapsed time help contextualize peak.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:riflay/models/track.dart';
import 'package:riflay/services/metadata.dart';

void main() {
  test('thumbnail peak memory', () async {
    const count = int.fromEnvironment('COVERS', defaultValue: 12);
    const side = int.fromEnvironment('SIDE', defaultValue: 2048);
    final dir = Directory.systemTemp.createTempSync('riflay-thumbnail-benchmark-');
    try {
      final cover = img.encodeJpg(img.Image(width: side, height: side));
      final tracks = <Track>[];
      for (var i = 0; i < count; i++) {
        final file = File('${dir.path}/$i.mp3')..writeAsBytesSync([0, 1, 2, 3]);
        File('${dir.path}/$i.jpg').writeAsBytesSync(cover);
        tracks.add(Track.fromUri(Uri.file(file.path)));
      }
      final start = ProcessInfo.currentRss;
      var peak = start;
      final timer = Timer.periodic(const Duration(milliseconds: 5), (_) {
        peak = math.max(peak, ProcessInfo.currentRss);
      });
      final clock = Stopwatch()..start();
      try {
        final results = await Future.wait(tracks.map(Metadata.thumbnail));
        peak = math.max(peak, ProcessInfo.currentRss);
        expect(results.where((r) => r != null), hasLength(count));
        // ignore: avoid_print
        print(
          'THUMBNAIL_MEMORY covers=$count side=$side '
          'startMiB=${(start / (1 << 20)).toStringAsFixed(1)} '
          'peakMiB=${(peak / (1 << 20)).toStringAsFixed(1)} '
          'elapsedMs=${clock.elapsedMilliseconds}',
        );
      } finally {
        timer.cancel();
      }
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}

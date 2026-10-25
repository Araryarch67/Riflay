import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/flac_stream.dart';

bool _hasFfmpeg() {
  try {
    return Process.runSync('ffmpeg', ['-version']).exitCode == 0;
  } catch (_) {
    return false;
  }
}

void main() {
  final ffmpeg = _hasFfmpeg();
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('riflay-flac'));
  tearDown(() => dir.deleteSync(recursive: true));

  /// Random interleaved PCM of [frames] frames; 24-bit is s32le with a zero low byte, as a decoder gives it.
  Uint8List pcm(int frames, int channels, int bits, int seed) {
    final rng = math.Random(seed);
    final out = ByteData(frames * channels * (bits == 16 ? 2 : 4));
    for (var i = 0; i < frames * channels; i++) {
      if (bits == 16) {
        out.setInt16(i * 2, rng.nextInt(65536) - 32768, Endian.little);
      } else {
        out.setInt32(i * 4, (rng.nextInt(1 << 24) - (1 << 23)) << 8, Endian.little);
      }
    }
    return out.buffer.asUint8List();
  }

  for (final (rate, bits, channels, frames) in [
    (44100, 16, 2, 4096 * 5 + 1000), // odd last block
    (44100, 16, 2, 4096 * 2), // exact blocks
    (48000, 24, 2, 4096 * 3 + 1),
    (176400, 24, 2, 4096 * 4 + 77),
    (192000, 24, 2, 5000),
    (96000, 16, 1, 300), // shorter than one block
    (88200, 24, 2, 9000),
    (11025, 16, 2, 4097), // not in the table: 16-bit Hz code
    (352800, 24, 2, 5000), // not in the table: tens of Hz code
  ]) {
    test('$rate Hz, $bits-bit, $channels ch, $frames frames decodes sample for sample', () async {
      if (!ffmpeg) return markTestSkipped('ffmpeg not available');
      final raw = pcm(frames, channels, bits, rate);
      // Feed it in awkward chunk sizes.
      Stream<List<int>> chunks() async* {
        for (var o = 0; o < raw.length; o += 7001) {
          yield Uint8List.sublistView(raw, o, math.min(o + 7001, raw.length));
        }
      }

      final flac = BytesBuilder();
      await for (final b in FlacStream.encode(chunks(), rate: rate, channels: channels, bits: bits)) {
        flac.add(b);
      }
      final file = File('${dir.path}/t.flac')..writeAsBytesSync(flac.takeBytes());
      final r = await Process.run('ffmpeg', [
        '-v', 'error', '-i', file.path, '-f', bits == 16 ? 's16le' : 's32le', '-', //
      ], stdoutEncoding: null);
      expect(r.stderr.toString().trim(), isEmpty);
      final got = Uint8List.fromList(r.stdout as List<int>);
      expect(got.length, raw.length);
      expect(md5.convert(got), md5.convert(raw));
      final probe = await Process.run('ffprobe', [
        '-v', 'error', '-show_entries', 'stream=sample_rate,channels', '-of', 'csv=p=0', file.path, //
      ]);
      expect((probe.stdout as String).trim(), '$rate,$channels');
    });
  }
}

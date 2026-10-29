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
  compressionTests();
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

/// A minimal FLAC reader for the encoder's output (CONSTANT, VERBATIM, FIXED, both Rice codings, all stereo modes):
/// returns each channel's samples and checks every frame's CRC-8 and CRC-16.
List<List<int>> _decode(Uint8List f, {required int bits, required int channels}) {
  expect(String.fromCharCodes(f.sublist(0, 4)), 'fLaC');
  var pos = 42; // marker + block header + STREAMINFO
  final out = [for (var c = 0; c < channels; c++) <int>[]];
  var bp = 0; // bit position
  int rd(int n) {
    var v = 0;
    for (var i = 0; i < n; i++) {
      v = (v << 1) | ((f[bp >> 3] >> (7 - (bp & 7))) & 1);
      bp++;
    }
    return v;
  }

  int sgn(int v, int n) => v >= (1 << (n - 1)) ? v - (1 << n) : v;

  while (pos < f.length) {
    bp = pos * 8;
    expect(rd(14), 0x3FFE);
    rd(2);
    final bsCode = rd(4);
    final rateCode = rd(4);
    final assign = rd(4);
    rd(4);
    var lead = rd(8);
    var extra = 0;
    while (lead & (0x80 >> (extra + 1)) != 0 && extra < 6) {
      extra++;
    }
    if (extra > 0) rd(8 * extra);
    final n = bsCode == 12 ? 4096 : rd(16) + 1;
    if (rateCode == 12) rd(8);
    if (rateCode == 13 || rateCode == 14) rd(16);
    final hdrEnd = bp ~/ 8;
    expect(rd(8), _crc8(f, pos, hdrEnd), reason: 'crc8');
    final subs = <List<int>>[];
    for (var c = 0; c < channels; c++) {
      final side = (assign == 8 && c == 1) || (assign == 9 && c == 0) || (assign == 10 && c == 1);
      final bps = bits + (side ? 1 : 0);
      expect(rd(1), 0);
      final type = rd(6);
      expect(rd(1), 0, reason: 'wasted bits unsupported');
      final x = List<int>.filled(n, 0);
      if (type == 0) {
        x.fillRange(0, n, sgn(rd(bps), bps));
      } else if (type == 1) {
        for (var i = 0; i < n; i++) {
          x[i] = sgn(rd(bps), bps);
        }
      } else {
        final order = type - 8;
        expect(order, inInclusiveRange(0, 4));
        for (var i = 0; i < order; i++) {
          x[i] = sgn(rd(bps), bps);
        }
        final method = rd(2);
        final pOrder = rd(4);
        final pb = method == 0 ? 4 : 5;
        for (var j = 0; j < 1 << pOrder; j++) {
          final k = rd(pb);
          expect(k, lessThan(method == 0 ? 15 : 31));
          final count = (n >> pOrder) - (j == 0 ? order : 0);
          for (var m = 0; m < count; m++) {
            var q = 0;
            while (rd(1) == 0) {
              q++;
            }
            final u = (q << k) | (k > 0 ? rd(k) : 0);
            final r = (u & 1) == 0 ? u >> 1 : -((u + 1) >> 1);
            final i = (j == 0 ? order : j * (n >> pOrder)) + m;
            final p = i < order + 0 ? 0 : 0;
            assert(p == 0);
            x[i] =
                r +
                switch (order) {
                  0 => 0,
                  1 => x[i - 1],
                  2 => 2 * x[i - 1] - x[i - 2],
                  3 => 3 * x[i - 1] - 3 * x[i - 2] + x[i - 3],
                  _ => 4 * x[i - 1] - 6 * x[i - 2] + 4 * x[i - 3] - x[i - 4],
                };
          }
        }
      }
      subs.add(x);
    }
    bp = (bp + 7) & ~7;
    final end = bp ~/ 8;
    expect(rd(16), _crc16(f, pos, end), reason: 'crc16');
    pos = bp ~/ 8;
    if (assign == 8) {
      for (var i = 0; i < n; i++) {
        subs[1][i] = subs[0][i] - subs[1][i];
      }
    } else if (assign == 9) {
      for (var i = 0; i < n; i++) {
        subs[0][i] = subs[0][i] + subs[1][i];
      }
    } else if (assign == 10) {
      for (var i = 0; i < n; i++) {
        final side = subs[1][i];
        final mid = (subs[0][i] << 1) | (side & 1);
        subs[0][i] = (mid + side) >> 1;
        subs[1][i] = (mid - side) >> 1;
      }
    }
    for (var c = 0; c < channels; c++) {
      out[c].addAll(subs[c]);
    }
  }
  return out;
}

int _crc8(Uint8List d, int from, int to) {
  var c = 0;
  for (var i = from; i < to; i++) {
    c ^= d[i];
    for (var k = 0; k < 8; k++) {
      c = (c & 0x80) != 0 ? ((c << 1) ^ 0x07) & 0xFF : (c << 1) & 0xFF;
    }
  }
  return c;
}

int _crc16(Uint8List d, int from, int to) {
  var c = 0;
  for (var i = from; i < to; i++) {
    c ^= d[i] << 8;
    for (var k = 0; k < 8; k++) {
      c = (c & 0x8000) != 0 ? ((c << 1) ^ 0x8005) & 0xFFFF : (c << 1) & 0xFFFF;
    }
  }
  return c;
}

/// Interleaved PCM (s16le, or s32le with the sample in the top three bytes) of a mix of sines and noise.
Uint8List _music(int frames, int channels, int bits, {double noise = 0.01, double width = 0.3, int seed = 1}) {
  final rng = math.Random(seed);
  final peak = bits == 16 ? 32767.0 : 8388607.0;
  final out = ByteData(frames * channels * (bits == 16 ? 2 : 4));
  for (var s = 0; s < frames; s++) {
    final t = s / 48000;
    final common =
        0.3 * math.sin(2 * math.pi * 220 * t) +
        0.2 * math.sin(2 * math.pi * 659.3 * t) +
        0.1 * math.sin(2 * math.pi * 3520 * t) * (0.5 + 0.5 * math.sin(2 * math.pi * 0.5 * t));
    for (var c = 0; c < channels; c++) {
      final own = width * 0.2 * math.sin(2 * math.pi * (330 + 55 * c) * t);
      final v = ((common + own + noise * (rng.nextDouble() * 2 - 1)) * peak).round().clamp(-peak, peak).toInt();
      final i = (s * channels + c) * (bits == 16 ? 2 : 4);
      if (bits == 16) {
        out.setInt16(i, v, Endian.little);
      } else {
        out.setInt32(i, v << 8, Endian.little);
      }
    }
  }
  return out.buffer.asUint8List();
}

Future<Uint8List> _encode(Uint8List raw, int rate, int channels, int bits, FlacCompression mode) async {
  Stream<List<int>> chunks() async* {
    for (var o = 0; o < raw.length; o += 9001) {
      yield Uint8List.sublistView(raw, o, math.min(o + 9001, raw.length));
    }
  }

  final b = BytesBuilder(copy: false);
  await for (final x in FlacStream.encode(chunks(), rate: rate, channels: channels, bits: bits, compression: mode)) {
    b.add(x);
  }
  return b.takeBytes();
}

List<int> _samples(Uint8List raw, int channel, int channels, int bits) {
  final d = ByteData.sublistView(raw);
  final w = bits == 16 ? 2 : 4;
  return [
    for (var i = channel * w; i < raw.length; i += channels * w)
      bits == 16 ? d.getInt16(i, Endian.little) : d.getInt32(i, Endian.little) >> 8,
  ];
}

void compressionTests() {
  final ffmpeg = _hasFfmpeg();
  final hasFlac = Process.runSync('which', ['flac']).exitCode == 0;

  // Signals chosen to hit every subframe kind and stereo mode.
  final cases = <String, Uint8List Function(int bits, int ch)>{
    'music': (bits, ch) => _music(4096 * 6 + 333, ch, bits),
    'wide stereo': (bits, ch) => _music(4096 * 4 + 5, ch, bits, width: 4, noise: 0.05),
    'loud noise': (bits, ch) => _music(4096 * 3 + 1, ch, bits, noise: 2),
    'silence': (bits, ch) => Uint8List(4096 * 3 * ch * (bits == 16 ? 2 : 4)),
    'tiny': (bits, ch) => _music(3, ch, bits),
  };
  for (final bits in [16, 24]) {
    for (final ch in [1, 2, 3]) {
      for (final e in cases.entries) {
        test('compressed ${e.key}, $bits-bit, $ch ch is bit-exact', () async {
          final raw = e.value(bits, ch);
          final flac = await _encode(raw, 48000, ch, bits, FlacCompression.fast);
          final got = _decode(flac, bits: bits, channels: ch);
          for (var c = 0; c < ch; c++) {
            expect(got[c], _samples(raw, c, ch, bits), reason: 'channel $c');
          }
          if (e.key == 'music' && ch == 2) {
            final verbatim = await _encode(raw, 48000, ch, bits, FlacCompression.none);
            expect(flac.length, lessThan(verbatim.length * 0.9));
          }
        });
      }
    }
  }

  test('extreme samples (full-scale square) survive prediction and side channels', () async {
    for (final bits in [16, 24]) {
      final n = 4096 * 2 + 10;
      final w = bits == 16 ? 2 : 4;
      final d = ByteData(n * 2 * w);
      final lo = bits == 16 ? -32768 : -8388608, hi = bits == 16 ? 32767 : 8388607;
      for (var s = 0; s < n; s++) {
        for (var c = 0; c < 2; c++) {
          final v = ((s ~/ 3) + c).isEven ? lo : hi;
          if (bits == 16) {
            d.setInt16((s * 2 + c) * w, v, Endian.little);
          } else {
            d.setInt32((s * 2 + c) * w, v << 8, Endian.little);
          }
        }
      }
      final raw = d.buffer.asUint8List();
      final flac = await _encode(raw, 44100, 2, bits, FlacCompression.fast);
      final got = _decode(flac, bits: bits, channels: 2);
      expect(got[0], _samples(raw, 0, 2, bits));
      expect(got[1], _samples(raw, 1, 2, bits));
    }
  });

  test('the importer can patch STREAMINFO of a compressed file', () async {
    final raw = _music(4096 * 3, 2, 16);
    final flac = await _encode(raw, 48000, 2, 16, FlacCompression.fast);
    expect(ByteData.sublistView(flac).getUint32(18), (48000 << 12) | (1 << 9) | (15 << 4));
  });

  test('compressed files pass flac -t and ffmpeg', () async {
    if (!hasFlac && !ffmpeg) return markTestSkipped('no flac or ffmpeg');
    final dir = Directory.systemTemp.createTempSync('riflay-flac2');
    try {
      for (final bits in [16, 24]) {
        for (final e in cases.entries) {
          final raw = e.value(bits, 2);
          final f = File('${dir.path}/t.flac')
            ..writeAsBytesSync(await _encode(raw, 48000, 2, bits, FlacCompression.fast));
          if (hasFlac) {
            final r = await Process.run('flac', ['-t', '-s', f.path]);
            expect(r.exitCode, 0, reason: '${e.key} $bits: ${r.stderr}');
          }
          if (ffmpeg && e.key != 'tiny') {
            final r = await Process.run('ffmpeg', [
              '-v', 'error', '-i', f.path, '-f', bits == 16 ? 's16le' : 's32le', '-', //
            ], stdoutEncoding: null);
            expect(r.stderr.toString().trim(), isEmpty);
            expect(md5.convert(r.stdout as List<int>), md5.convert(raw), reason: '${e.key} $bits');
          }
        }
      }
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('speed and size (printed, not asserted)', () async {
    final rows = StringBuffer();
    for (final bits in [16, 24]) {
      final raw = _music(48000 * 60, 2, bits);
      final sizes = <FlacCompression, int>{};
      for (final mode in FlacCompression.values) {
        final sw = Stopwatch()..start();
        final flac = await _encode(raw, 48000, 2, bits, mode);
        sw.stop();
        sizes[mode] = flac.length;
        rows.writeln(
          '$bits-bit ${mode.name}: 60 s in ${sw.elapsedMilliseconds} ms '
          '(${(60000 / math.max(1, sw.elapsedMilliseconds)).toStringAsFixed(0)}x real time), ${flac.length} bytes',
        );
      }
      rows.writeln(
        '$bits-bit fast/none = ${(sizes[FlacCompression.fast]! / sizes[FlacCompression.none]!).toStringAsFixed(3)}',
      );
      if (ffmpeg) {
        final dir = Directory.systemTemp.createTempSync('riflay-flac3');
        try {
          final src = File('${dir.path}/in.raw')..writeAsBytesSync(raw);
          final r = await Process.run('ffmpeg', [
            '-v', 'error', '-f', bits == 16 ? 's16le' : 's32le', '-ar', '48000', '-ac', '2', '-i', src.path, //
            '-c:a', 'flac', '-sample_fmt', bits == 16 ? 's16' : 's32', '-y', '${dir.path}/ff.flac',
          ]);
          final ff = File('${dir.path}/ff.flac').lengthSync();
          rows.writeln(
            '$bits-bit ffmpeg flac: $ff bytes (exit ${r.exitCode}); ours/ffmpeg = '
            '${(sizes[FlacCompression.fast]! / ff).toStringAsFixed(3)}',
          );
        } finally {
          dir.deleteSync(recursive: true);
        }
      }
    }
    // ignore: avoid_print
    print(rows);
  }, timeout: const Timeout(Duration(minutes: 5)));
}

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/audio_engine.dart';

bool get _ffmpeg {
  try {
    return Process.runSync('ffmpeg', ['-version']).exitCode == 0;
  } catch (_) {
    return false;
  }
}

/// A quiet 100 Hz tone (amplitude 4 LSB) in float, rounded to 16 bits by libswresample with [shape]'s
/// `dither_method`; returns how much of the rounding noise sits at high frequencies: the energy of its first
/// difference (a high-pass) over its own energy. triangular_hp is already tilted up a little (about 3), the shaped ones more.
double _highShare(DitherShape shape) {
  const rate = 44100, lsb = 4.0;
  final r = Process.runSync('ffmpeg', [
    '-loglevel', 'error', '-f', 'lavfi', '-i', 'aevalsrc=${lsb / 32768}*sin(2*PI*100*t):s=$rate:d=2', //
    '-af', 'aresample=osf=s16:dither_method=${shape.swresample}', '-f', 's16le', '-',
  ], stdoutEncoding: null);
  final out = Int16List.view(Uint8List.fromList(r.stdout as List<int>).buffer);
  var noise = 0.0, diff = 0.0, prev = 0.0;
  for (var i = 0; i < out.length; i++) {
    final e = out[i] - lsb * sin(2 * pi * 100 * i / rate);
    noise += e * e;
    diff += (e - prev) * (e - prev);
    prev = e;
  }
  return diff / noise;
}

void main() {
  test('every shape names a distinct libswresample dither_method', () {
    expect(DitherShape.values.map((d) => d.swresample).toSet().length, DitherShape.values.length);
    expect(DitherShape.flat.swresample, 'triangular_hp');
  });

  test('noise shaping moves the rounding noise to high frequencies', () {
    final flat = _highShare(DitherShape.flat);
    expect(_highShare(DitherShape.lipshitz), greaterThan(flat * 1.2));
    expect(_highShare(DitherShape.shibata), greaterThan(flat * 1.2));
  }, skip: _ffmpeg ? false : 'needs ffmpeg');
}

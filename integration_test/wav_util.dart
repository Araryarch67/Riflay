// WAV files for the integration tests that render through mpv (ao=pcm): one to play, and what came out measured.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// A 16-bit stereo 48 kHz WAV of [frames] frames; [sample] gives (left, right) in −1..1.
/// [float]: 32-bit float instead, which holds samples past full scale (as Opus and AAC decode).
File writeWav(String path, int frames, (double, double) Function(int i) sample, {bool float = false}) {
  final width = float ? 4 : 2;
  final data = ByteData(44 + frames * 2 * width);
  void tag(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  data.setUint32(4, 36 + frames * 2 * width, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  data
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, float ? 3 : 1, Endian.little)
    ..setUint16(22, 2, Endian.little)
    ..setUint32(24, 48000, Endian.little)
    ..setUint32(28, 48000 * 2 * width, Endian.little)
    ..setUint16(32, 2 * width, Endian.little)
    ..setUint16(34, 8 * width, Endian.little);
  tag(36, 'data');
  data.setUint32(40, frames * 2 * width, Endian.little);
  for (var i = 0; i < frames; i++) {
    final (l, r) = sample(i);
    final at = 44 + i * 2 * width;
    if (float) {
      data
        ..setFloat32(at, l, Endian.little)
        ..setFloat32(at + 4, r, Endian.little);
    } else {
      data
        ..setInt16(at, (l * 32767).round(), Endian.little)
        ..setInt16(at + 2, (r * 32767).round(), Endian.little);
    }
  }
  return File(path)..writeAsBytesSync(data.buffer.asUint8List());
}

/// What mpv wrote: its rate, each channel's RMS in dBFS over the second half
/// (what was filtered before a change may still sit in the output's buffer),
/// and the peak there, in dBFS.
({int rate, List<double> db, double peak}) measureWav(File wav) {
  final b = ByteData.sublistView(wav.readAsBytesSync());
  var at = 12;
  int? format, bits, channels, rate;
  while (at + 8 <= b.lengthInBytes) {
    final id = String.fromCharCodes(Uint8List.sublistView(b, at, at + 4));
    final size = b.getUint32(at + 4, Endian.little);
    if (id == 'fmt ') {
      format = b.getUint16(at + 8, Endian.little);
      channels = b.getUint16(at + 10, Endian.little);
      rate = b.getUint32(at + 12, Endian.little);
      bits = b.getUint16(at + 22, Endian.little);
      if (format == 0xFFFE) format = b.getUint16(at + 32, Endian.little); // extensible: the subformat GUID
    } else if (id == 'data') {
      final end = size == 0 || size == 0xFFFFFFFF ? b.lengthInBytes : math.min(at + 8 + size, b.lengthInBytes);
      final step = bits! ~/ 8, frame = step * channels!;
      final start = at + 8 + (end - at - 8) ~/ 2 ~/ frame * frame;
      final sums = List.filled(channels, 0.0);
      var n = 0;
      var peak = 0.0;
      for (var i = start; i + frame <= end; i += frame, n++) {
        for (var c = 0; c < channels; c++) {
          final p = i + c * step;
          final v = switch ((format, bits)) {
            (3, 32) => b.getFloat32(p, Endian.little),
            (3, 64) => b.getFloat64(p, Endian.little),
            (1, 16) => b.getInt16(p, Endian.little) / 32768,
            (1, 32) => b.getInt32(p, Endian.little) / 2147483648,
            _ => throw StateError('unexpected WAV format $format/$bits'),
          };
          sums[c] += v * v;
          peak = math.max(peak, v.abs());
        }
      }
      return (
        rate: rate!,
        db: [for (final s in sums) s == 0 ? -200.0 : 10 * math.log(s / n) / math.ln10],
        peak: peak == 0 ? -200.0 : 20 * math.log(peak) / math.ln10,
      );
    }
    at += 8 + size + (size & 1);
  }
  throw StateError('no data in ${wav.path}');
}

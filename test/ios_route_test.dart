import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/audio_engine.dart';
import 'package:riflay/services/ios_route.dart';
import 'package:riflay/services/linux_alsa.dart';

Uint8List _flac(int rate) {
  final b = Uint8List(42)..setAll(0, 'fLaC'.codeUnits);
  b[18] = rate >> 12;
  b[19] = (rate >> 4) & 0xff;
  b[20] = (rate & 0xf) << 4;
  return b;
}

Uint8List _wav(int rate) {
  final b = Uint8List(44)..setAll(0, 'RIFF'.codeUnits);
  b.setAll(8, 'WAVEfmt '.codeUnits);
  b.buffer.asByteData().setUint32(16, 16, Endian.little);
  b.buffer.asByteData().setUint32(24, rate, Endian.little);
  return b;
}

Uint8List _aiff(int exp, int mantissaHigh) {
  final b = Uint8List(54)..setAll(0, 'FORM'.codeUnits);
  b.setAll(8, 'AIFFCOMM'.codeUnits);
  final d = b.buffer.asByteData();
  d.setUint32(16, 18);
  d.setUint16(28, exp);
  d.setUint32(30, mantissaHigh);
  return b;
}

void main() {
  test('reads the rate from FLAC, WAV and AIFF headers', () {
    for (final r in [44100, 48000, 96000, 192000, 384000]) {
      expect(parseSourceRate(_flac(r)), r);
      expect(parseSourceRate(_wav(r)), r);
    }
    // 44100 = 0xAC44 as an 80-bit float: exponent 0x400E, mantissa 0xAC44 << 16.
    expect(parseSourceRate(_aiff(0x400E, 0xAC440000)), 44100);
    expect(parseSourceRate(Uint8List(64)), isNull);
  });

  test('a fixed output rate wins over the song\'s', () {
    expect(preferredRate(outputRate: 96000, songRate: 44100), 96000);
    expect(preferredRate(outputRate: null, songRate: 44100), 44100);
    expect(preferredRate(outputRate: 0, songRate: null), isNull);
  });

  test('a 44.1 kHz song on a 48 kHz iOS output is resampled by the mixer, never bit-perfect', () {
    SignalPath path(int hw) => SignalPath(
      codec: 'flac',
      container: 'flac',
      inFormat: 's16',
      inRate: 44100,
      inChannels: 2,
      outFormat: 'floatp',
      outRate: 44100,
      outChannels: 2,
      output: 'audiounit',
      device: 'auto',
      filters: const [],
      volume: 100,
      leveling: false,
      bitrate: null,
      dac: HwParams(format: 'FLOAT_LE', rate: hw, channels: 2),
      dacName: 'USB DAC',
    );
    expect(path(48000).mixerResamples, isTrue);
    expect(path(44100).mixerResamples, isFalse);
    expect(path(44100).bitPerfect, isFalse);
  });
}

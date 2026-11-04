import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/linux_alsa.dart';

void main() {
  test('a USB DAC that stops at 96 kHz (KTMicro CDS.KT dongle) can\'t take DoP', () {
    final rates = LinuxAlsa.ratesOf(File('test/fixtures/stream0_ktmicro.txt').readAsStringSync())!;
    expect(rates, {44100, 48000, 88200, 96000}, reason: 'playback rates only, not the capture side');
    expect(rates.contains(176400), isFalse, reason: 'DSD64 over DoP needs 176.4 kHz');
  });

  test('a continuous range and a card that says nothing', () {
    const stream0 = '''
Some DAC : USB Audio

Playback:
  Interface 1
    Altset 1
    Format: S32_LE
    Channels: 2
    Rates: 44100 - 384000 (continuous)
''';
    expect(LinuxAlsa.ratesOf(stream0), containsAll(<int>[176400, 352800, 384000]));
    expect(LinuxAlsa.ratesOf('Capture:\n  Rates: 48000\n'), isNull);
  });
}

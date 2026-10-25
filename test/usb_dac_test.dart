import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/audio_engine.dart';
import 'package:riflay/services/usb_dac.dart';

MixerFormat _f(int rate, String encoding) => MixerFormat(rate, encoding);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final dac = [
    _f(44100, 'pcm16'),
    _f(48000, 'pcm16'),
    _f(44100, 'pcm32'),
    _f(48000, 'pcm32'),
    _f(96000, 'pcm32'),
    _f(192000, 'pcm32'),
    _f(176400, 'pcm32'),
  ];

  group('chooseMixer', () {
    test('16-bit song gets 16-bit PCM at its rate, mpv s16', () {
      final c = chooseMixer(dac, rate: 44100, bits: 16)!;
      expect(c.format, _f(44100, 'pcm16'));
      expect(c.bitPerfect, isTrue);
      expect(c.format.mpvFormat, 's16');
    });

    test('24-bit song gets 32-bit PCM, mpv s32', () {
      final c = chooseMixer(dac, rate: 96000, bits: 24)!;
      expect(c.format, _f(96000, 'pcm32'));
      expect(c.bitPerfect, isTrue);
      expect(c.format.mpvFormat, 's32');
    });

    test('a rate the DAC lacks falls back to the nearest and is not bit-perfect', () {
      final c = chooseMixer(dac, rate: 88200, bits: 24)!;
      expect(c.format.rate, 96000);
      expect(c.exactRate, isFalse);
      expect(c.bitPerfect, isFalse);
    });

    test('a tie goes to the higher rate', () {
      expect(chooseMixer([_f(44100, 'pcm32'), _f(48000, 'pcm32')], rate: 46050, bits: 24)!.format.rate, 48000);
    });

    test('a 16-bit song fits a 32-bit-only DAC losslessly', () {
      final c = chooseMixer([_f(44100, 'pcm32')], rate: 44100, bits: 16)!;
      expect(c.bitPerfect, isTrue);
      expect(c.format.mpvFormat, 's32');
    });

    test('a 24-bit song on a 16-bit-only DAC is not bit-perfect', () {
      final c = chooseMixer([_f(44100, 'pcm16')], rate: 44100, bits: 24)!;
      expect(c.exactRate, isTrue);
      expect(c.exactDepth, isFalse);
      expect(c.bitPerfect, isFalse);
    });

    test('nothing usable gives null', () {
      expect(chooseMixer(const [], rate: 44100, bits: 16), isNull);
      expect(chooseMixer([_f(44100, 'float')], rate: 44100, bits: 16), isNull);
    });
  });

  group('DoP', () {
    test('DSD64 needs 176.4 kHz, DSD128 352.8 kHz, as 32-bit', () {
      final d = UsbDevice(1, 'DAC', dac);
      expect(d.takesDop(2822400), isTrue);
      expect(d.takesDop(5644800), isFalse);
      expect(d.dopCapable, isTrue);
      expect(UsbDevice(2, 'x', [_f(352800, 'pcm32')]).takesDop(5644800), isTrue);
      expect(UsbDevice(3, 'x', [_f(176400, 'pcm16')]).dopCapable, isFalse);
    });

    test('a DoP stream (24-bit at 176.4 kHz) picks the DoP rate', () {
      final c = chooseMixer(dac, rate: 2822400 ~/ 16, bits: 24)!;
      expect(c.format, _f(176400, 'pcm32'));
      expect(c.bitPerfect, isTrue);
    });
  });

  group('signal path on Android', () {
    SignalPath path({bool usb = true, String inFormat = 's32', int inRate = 96000, int outRate = 96000}) => SignalPath(
      codec: 'flac',
      container: 'flac',
      inFormat: inFormat,
      inRate: inRate,
      inChannels: 2,
      outFormat: 's32',
      outRate: outRate,
      outChannels: 2,
      output: 'opensles',
      device: 'auto',
      filters: const [],
      volume: 100,
      leveling: false,
      bitrate: null,
      usbDacName: 'Test DAC',
      usbBitPerfect: usb,
    );

    test('the Android mixer alone is not bit-perfect', () {
      expect(path(usb: false).bitPerfect, isFalse);
    });

    test('exact mixer attributes make it bit-perfect', () {
      expect(path().bitPerfect, isTrue);
    });

    test('a resampled fallback rate is not', () {
      expect(path(usb: false, outRate: 192000).bitPerfect, isFalse);
    });
  });

  group('channel', () {
    test('reads the state, sets a format once, clears it', () async {
      final calls = <MethodCall>[];
      const channel = MethodChannel('riflay/usb_dac_test');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'state' => {
            'supported': true,
            'devices': [
              {
                'id': 7,
                'name': 'Test DAC',
                'formats': [
                  {'rate': 44100, 'encoding': 'pcm16'},
                ],
              },
            ],
          },
          'prefer' => true,
          _ => null,
        };
      });
      final usb = UsbDac(channel: channel);
      await usb.init();
      expect(usb.supported, isTrue);
      expect(usb.device?.name, 'Test DAC');
      expect(await usb.prefer(_f(44100, 'pcm16')), isTrue);
      expect(await usb.prefer(_f(44100, 'pcm16')), isTrue);
      expect(calls.where((c) => c.method == 'prefer'), hasLength(1));
      await usb.clear();
      expect(calls.last.method, 'clear');
      expect(usb.active, isNull);
    });
  });
}

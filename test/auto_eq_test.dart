import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riflay/services/audio_engine.dart';
import 'package:riflay/services/auto_eq.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// KZ ZSN Pro measured by crinacle, as AutoEQ has it: two shelves among peaking filters, out of frequency order.
const _zsnPro = '''
Preamp: -3.4 dB
Filter 1: ON LSC Fc 105 Hz Gain 1.0 dB Q 0.70
Filter 2: ON PK Fc 159 Hz Gain -3.5 dB Q 0.65
Filter 3: ON PK Fc 800 Hz Gain 4.0 dB Q 0.86
Filter 4: ON PK Fc 2280 Hz Gain -3.5 dB Q 1.30
Filter 5: ON PK Fc 3292 Hz Gain 4.6 dB Q 4.16
Filter 6: ON HSC Fc 10000 Hz Gain -4.0 dB Q 0.70
Filter 7: ON PK Fc 4774 Hz Gain -5.1 dB Q 4.96
Filter 8: ON PK Fc 6507 Hz Gain 3.7 dB Q 5.13
Filter 9: ON PK Fc 8713 Hz Gain 2.8 dB Q 3.19
Filter 10: ON PK Fc 3916 Hz Gain 2.3 dB Q 5.89
''';

const _index = '''
# Index
This is a list of all equalization profiles.

- [KZ ZSN Pro](./crinacle/711%20in-ear/KZ%20ZSN%20Pro) by crinacle on 711
- [KZ ZSN Pro X](./oratory1990/in-ear/KZ%20ZSN%20Pro%20X) by oratory1990
- [Moondrop Chu 2](./crinacle/711%20in-ear/Moondrop%20Chu%202) by crinacle on 711
- [Sony WH-1000XM4](./oratory1990/over-ear/Sony%20WH-1000XM4) by oratory1990
''';

/// The equalizer's curve at [f], in dB.
double _bandsDb(List<EqBand> bands, double f) =>
    AutoEq.responseDb([for (final b in bands) AutoEqFilter(AutoEqFilterType.peaking, b.frequency, b.gain, b.q)], f);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory support;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    support = Directory.systemTemp.createTempSync('autoeq');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => support.path,
    );
    AutoEq.forgetIndex();
  });
  tearDown(() => support.deleteSync(recursive: true));

  test('the index lists each model with who measured it, on which rig', () {
    final all = AutoEq.parseIndex(_index);
    expect(all, hasLength(4));
    expect(all.first.name, 'KZ ZSN Pro');
    expect(all.first.path, 'crinacle/711%20in-ear/KZ%20ZSN%20Pro');
    expect(all.first.by, 'crinacle · 711');
    expect(all[1].by, 'oratory1990');
  });

  test('search finds every word, the closest names first', () {
    final all = AutoEq.parseIndex(_index);
    expect(AutoEq.search(all, 'zsn pro').map((e) => e.name), ['KZ ZSN Pro', 'KZ ZSN Pro X']);
    expect(AutoEq.search(all, 'kz zsn pro x').single.name, 'KZ ZSN Pro X');
    expect(AutoEq.search(all, 'chu'), hasLength(1));
    expect(AutoEq.search(all, 'Moondrop Chu II').single.name, 'Moondrop Chu 2', reason: 'Roman numbers as digits');
    expect(AutoEq.search(all, 'wh1000xm4').single.name, 'Sony WH-1000XM4', reason: 'punctuation is ignored');
    expect(AutoEq.search(all, '  '), isEmpty);
  });

  test('a ParametricEQ.txt reads as its filters', () {
    final f = AutoEq.parseParametric(_zsnPro);
    expect(f, hasLength(10));
    expect(f.first.type, AutoEqFilterType.lowShelf);
    expect(f[5].type, AutoEqFilterType.highShelf);
    expect((f[9].frequency, f[9].gain, f[9].q), (3916, 2.3, 5.89));
  });

  test('peaking filters the equalizer can hold are taken as they are', () {
    final fit = AutoEq.toBands(
      AutoEq.parseParametric(
        'Filter 1: ON PK Fc 200 Hz Gain -3.0 dB Q 1.00\nFilter 2: ON PK Fc 3000 Hz Gain 2.5 dB Q 2.00',
      ),
    );
    expect(fit.error, 0);
    expect(fit.bands, hasLength(10), reason: 'the rest sit at the default frequencies, flat');
    expect(fit.bands.where((b) => b.gain != 0).map((b) => (b.frequency, b.gain, b.q)), [(200, -3, 1), (3000, 2.5, 2)]);
    final freqs = fit.bands.map((b) => b.frequency).toList();
    expect(freqs, [...freqs]..sort());
  });

  test('a profile with shelves is fitted with ten peaking bands that follow its curve', () {
    final filters = AutoEq.parseParametric(_zsnPro);
    final fit = AutoEq.toBands(filters);
    expect(fit.bands, hasLength(10));
    for (final b in fit.bands) {
      expect(b.gain.abs(), lessThanOrEqualTo(12));
      expect(b.q, inInclusiveRange(0.3, 8));
      expect(b.frequency, inInclusiveRange(20, 20000));
    }
    expect(fit.error, lessThan(1.0), reason: 'within a dB of the profile up to 10 kHz');
    // Checked independently of the fit's own figure, every third of an octave.
    var worst = 0.0;
    for (var f = 20.0; f <= 10000; f *= math.pow(2, 1 / 3)) {
      worst = math.max(worst, (_bandsDb(fit.bands, f) - AutoEq.responseDb(filters, f)).abs());
    }
    expect(worst, lessThan(1.0));
  });

  test('the list of models is kept on the device, and an old copy serves when GitHub can\'t be reached', () async {
    var gets = 0;
    final online = MockClient((req) async {
      gets++;
      expect(req.url.toString(), endsWith('/results/INDEX.md'));
      return http.Response(_index, 200);
    });
    expect(await AutoEq.index(client: online), hasLength(4));
    AutoEq.forgetIndex();
    expect(await AutoEq.index(client: online), hasLength(4));
    expect(gets, 1, reason: 'a recent copy is read from the device');

    final file = File('${support.path}/autoeq_index.md');
    file.setLastModifiedSync(DateTime.now().subtract(const Duration(days: 40)));
    AutoEq.forgetIndex();
    final offline = MockClient((_) async => throw const SocketException('offline'));
    expect(await AutoEq.index(client: offline), hasLength(4));
  });

  test('a picked model\'s profile is downloaded from its folder and becomes the equalizer\'s bands', () async {
    final e = AutoEq.parseIndex(_index).first;
    final client = MockClient((req) async {
      expect(
        req.url.toString(),
        'https://raw.githubusercontent.com/jaakkopasanen/AutoEq/master/results/'
        'crinacle/711%20in-ear/KZ%20ZSN%20Pro/KZ%20ZSN%20Pro%20ParametricEQ.txt',
      );
      return http.Response(_zsnPro, 200);
    });
    final fit = await AutoEq.fitFor(e, client: client);
    final audio = AudioEngine();
    await audio.applyEqProfile('${e.name} (${e.source})', fit.bands);
    expect(audio.eqActive, isTrue);
    expect(audio.eqProfile, 'KZ ZSN Pro (crinacle)');
    expect(audio.filterChain, contains('@eq:'));
    await audio.setBand(0, audio.bands[0].copyWith(gain: 1));
    expect(audio.eqProfile, isNull, reason: 'a band moved by hand is no longer the profile');
  });
}

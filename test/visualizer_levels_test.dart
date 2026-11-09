import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/visualizer_levels.dart';

void main() {
  test('complete metadata maps real frequency bands without shifting their positions', () {
    final levels = VisualizerLevels();
    addTearDown(levels.dispose);
    const metadata = '{"lavfi.astats.1.RMS_level":"0","lavfi.astats.3.RMS_level":"-12","lavfi.astats.4.RMS_level":-30}';
    levels.addMetadata(metadata);
    expect(levels.value[0], closeTo(0.68, 0.000001));
    expect(levels.value[1], closeTo(0.425, 0.000001));
    expect(levels.value.skip(2), everyElement(0));
    levels.addMetadata(metadata);
    expect(levels.value[0], greaterThan(levels.value[1]));
    expect(levels.value.skip(2), everyElement(0), reason: 'frequency peaks must not travel like a train');
    final measured = levels.value[0];
    levels.addMetadata('{}');
    expect(levels.value[0], inExclusiveRange(0, measured));
  });

  test('aspectralstats metadata stands as tall as astats for the same sound', () {
    // Measured by FFmpeg 9 on a 1 kHz tone: astats -27.07 dB RMS; aspectralstats mean 4.55e-05 and variance
    // 6.53e-07 (power -61.84 dB).
    expect(VisualizerLevels.spectralDb(4.55094e-05, 6.53e-07)!, closeTo(-27.07, 0.4));
    expect(VisualizerLevels.spectralDb(0, 0), isNull);
    final spectral = VisualizerLevels();
    final rms = VisualizerLevels();
    addTearDown(spectral.dispose);
    addTearDown(rms.dispose);
    final mean = 0.001, variance = 0.00002;
    final db = VisualizerLevels.spectralDb(mean, variance)!;
    spectral.addMetadata(
      '{"lavfi.aspectralstats.1.mean":"1","lavfi.aspectralstats.3.mean":"$mean",'
      '"lavfi.aspectralstats.3.variance":"$variance","lavfi.aspectralstats.4.mean":"0"}',
    );
    rms.addMetadata('{"lavfi.astats.3.RMS_level":"$db"}');
    expect(spectral.value[0], closeTo(rms.value[0], 1e-9));
    expect(spectral.value.skip(1), everyElement(0));
  });

  test('mono metadata starts the analysis after its one original channel', () {
    final levels = VisualizerLevels();
    addTearDown(levels.dispose);
    levels.addMetadata('{"lavfi.astats.2.RMS_level":"-6"}', firstBandChannel: 2);
    expect(levels.value.first, greaterThan(0.7));
    expect(levels.value.skip(1), everyElement(0));
  });

  test('missing, malformed and silent filter metadata are safe before playback starts', () {
    for (final metadata in [
      '',
      '{}',
      'null',
      '[]',
      'not json',
      '{"lavfi.astats.Overall.RMS_level":"-inf"}',
      '{"lavfi.astats.Overall.RMS_level":null}',
      '{"lavfi.astats.Overall.RMS_level":true}',
    ]) {
      final levels = VisualizerLevels();
      levels.addMetadata(metadata);
      expect(levels.value, everyElement(0), reason: metadata);
      levels.dispose();
    }
  });

  test('bass onsets kick Pulse and sustained sound settles without invented beats', () {
    final levels = VisualizerLevels();
    addTearDown(levels.dispose);
    final tone = List<double>.filled(VisualizerLevels.samples, 0.6);
    levels.addBands(tone);
    expect(levels.beat, greaterThan(0.8));
    for (var i = 0; i < 60; i++) {
      levels.addBands(tone);
    }
    expect(levels.beat, lessThan(0.001));
    levels.clear();
    expect(levels.beat, 0);
  });

  test('silence, invalid metadata and clipping stay within display range', () {
    for (final input in ['', '-inf', 'nan', 'Infinity', '-80', '-60']) {
      expect(VisualizerLevels.amplitude(input), 0, reason: input);
    }
    expect(VisualizerLevels.amplitude('-30'), closeTo(0.5, 0.001));
    expect(VisualizerLevels.amplitude('6'), 1);
  });

  test('real level changes attack quickly, decay smoothly and reset between songs', () {
    final levels = VisualizerLevels();
    addTearDown(levels.dispose);
    levels.add('-12');
    final attack = levels.value.last;
    expect(attack, greaterThan(0.5));
    levels.add('-inf');
    expect(levels.value.last, inExclusiveRange(0, attack));
    expect(levels.value.length, VisualizerLevels.samples);
    for (var i = 0; i < 100; i++) {
      levels.add('-inf');
    }
    expect(levels.value.last, lessThan(0.001));
    levels.clear();
    expect(levels.value, everyElement(0));
    expect(levels.backgroundEnergy, 0);
  });

  test('display interpolation is independent of refresh rate and leaves audio untouched', () {
    final source = VisualizerLevels()..add('-12');
    final at60Hz = VisualizerLevels();
    final at120Hz = VisualizerLevels();
    addTearDown(source.dispose);
    addTearDown(at60Hz.dispose);
    addTearDown(at120Hz.dispose);
    final measured = List<double>.of(source.value);

    for (var i = 0; i < 6; i++) {
      at60Hz.follow(source, const Duration(microseconds: 16666));
    }
    for (var i = 0; i < 12; i++) {
      at120Hz.follow(source, const Duration(microseconds: 8333));
    }
    expect(at60Hz.value.last, inExclusiveRange(0, source.value.last));
    expect(at120Hz.value.last, closeTo(at60Hz.value.last, 0.000001));
    expect(at120Hz.frame, closeTo(at60Hz.frame, 0.000001));
    expect(at120Hz.backgroundEnergy, closeTo(at60Hz.backgroundEnergy, 0.000001));
    expect(source.value, measured);

    var settled = false;
    for (var i = 0; i < 100; i++) {
      if (!at60Hz.follow(source, const Duration(milliseconds: 16))) {
        settled = true;
        break;
      }
    }
    expect(settled, isTrue, reason: 'the display ticker must stop when levels settle');
    expect(at60Hz.value, source.value);
    expect(at60Hz.frame, source.frame);
    expect(at60Hz.backgroundEnergy, source.backgroundEnergy);
  });

  test('Balanced\'s 12 measured bands are spread over the 24 bars, its 4096-point window read 6 dB up', () {
    expect(
      VisualizerLevels.spectralDb(1, 0, window: 4096)! - VisualizerLevels.spectralDb(1, 0)!,
      closeTo(6.02, 0.01),
    );
    // Bass loud, treble silent: the bars fall from the first to the last, through the middle.
    final metadata = StringBuffer('{');
    for (var band = 0; band < 12; band++) {
      metadata.write('"lavfi.astats.${band + 3}.RMS_level":"${band == 0 ? -6 : -60}",');
    }
    metadata.write('"x":"0"}');
    final levels = VisualizerLevels()..addMetadata(metadata.toString(), bands: 12);
    expect(levels.value.length, 24);
    expect(levels.value.first, greaterThan(0.7));
    expect(levels.value[1], greaterThan(levels.value[2]));
    expect(levels.value[2], greaterThan(0), reason: 'between band 0 and band 1');
    expect(levels.value.last, 0);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/visualizer_levels.dart';

void main() {
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
}

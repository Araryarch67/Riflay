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
  });
}

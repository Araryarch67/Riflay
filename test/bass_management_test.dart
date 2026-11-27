import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/audio_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the filter splits stereo at the crossover into 2.1, and clamps it', () {
    final f = AudioEngine.bassManagementFilter(80);
    expect(f, allOf(contains('highpass=f=80.0'), contains('lowpass=f=80.0'), contains('channel_layout=2.1')));
    expect(AudioEngine.bassManagementFilter(5), contains('lowpass=f=40.0'));
    expect(AudioEngine.bassManagementFilter(900), contains('highpass=f=200.0'));
  });

  test('it only runs where a third channel fits, and not twice with Virtual speakers', () {
    final a = AudioEngine()..bassManagement = true;
    expect(a.filterChain, contains('@bass:'));
    a.sourceChannels = 6;
    expect(a.bassManagementActive, isFalse, reason: 'a 5.1 song already has its LFE');
    a
      ..sourceChannels = 2
      ..mono = MonoAudio.both;
    expect(a.bassManagementActive, isFalse);
    a
      ..mono = MonoAudio.off
      ..bitPerfect = true;
    expect(a.bassManagementActive, isFalse);
  });

  test('settings keep it', () async {
    final a = AudioEngine();
    await a.setBassManagement(true);
    await a.setBassCrossover(120);
    final b = AudioEngine();
    await b.load();
    expect(b.bassManagement, isTrue);
    expect(b.bassCrossover, 120);
  });
}

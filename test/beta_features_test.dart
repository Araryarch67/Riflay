import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/beta_features.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('stable features default on and experimental audio analysis defaults off', () async {
    SharedPreferences.setMockInitialValues({});
    final b = BetaFeatures();
    await b.load();
    for (final f in BetaFeature.values) {
      expect(b.isOn(f), f.defaultOn);
    }
  });

  test('visualizer opt-in survives reload and old decoration preferences cannot enable it', () async {
    SharedPreferences.setMockInitialValues({
      'layout.v1': '{"visualizer":true}',
      'appearance.v1': '{"reactiveBackground":true}',
    });
    final beta = BetaFeatures();
    expect(beta.isOn(BetaFeature.audioVisualizer), isFalse);
    await beta.load();
    expect(beta.isOn(BetaFeature.audioVisualizer), isFalse);
    await beta.set(BetaFeature.audioVisualizer, true);
    final restored = BetaFeatures();
    await restored.load();
    expect(restored.isOn(BetaFeature.audioVisualizer), isTrue);
    await restored.set(BetaFeature.audioVisualizer, false);
    await restored.reload();
    expect(restored.isOn(BetaFeature.audioVisualizer), isFalse);
  });

  test('a switch is saved as features.<id> and read back', () async {
    SharedPreferences.setMockInitialValues({});
    final b = BetaFeatures();
    var notified = 0;
    b.addListener(() => notified++);
    await b.set(BetaFeature.musixmatch, false);
    expect(b.isOn(BetaFeature.musixmatch), isFalse);
    expect(b.isOn(BetaFeature.videoMode), isTrue);
    expect(notified, greaterThan(0));
    expect((await SharedPreferences.getInstance()).getBool('features.musixmatch'), isFalse);

    final again = BetaFeatures();
    await again.load();
    expect(again.isOn(BetaFeature.musixmatch), isFalse);
    await again.set(BetaFeature.musixmatch, true);
    expect((await SharedPreferences.getInstance()).getBool('features.musixmatch'), isTrue);
  });

  test('legacy choices survive promotion and new preferences take precedence', () async {
    SharedPreferences.setMockInitialValues({'beta.musixmatch': false});
    final prefs = BetaFeatures();
    await prefs.load();
    expect(prefs.isOn(BetaFeature.musixmatch), isFalse);
    await prefs.set(BetaFeature.musixmatch, true);
    final restored = BetaFeatures();
    await restored.load();
    expect(restored.isOn(BetaFeature.musixmatch), isTrue);
  });

  test('keys are unique and every feature has a one-line description', () {
    expect(BetaFeature.values.map(BetaFeatures.keyOf).toSet(), hasLength(BetaFeature.values.length));
    for (final f in BetaFeature.values) {
      expect(f.description, isNotEmpty);
      expect(f.description.contains('\n'), isFalse);
    }
  });
}

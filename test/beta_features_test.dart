import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/beta_features.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('everything is on by default', () async {
    SharedPreferences.setMockInitialValues({});
    final b = BetaFeatures();
    await b.load();
    for (final f in BetaFeature.values) {
      expect(b.isOn(f), isTrue);
    }
  });

  test('a switch is saved as beta.<id> and read back', () async {
    SharedPreferences.setMockInitialValues({});
    final b = BetaFeatures();
    var notified = 0;
    b.addListener(() => notified++);
    await b.set(BetaFeature.musixmatch, false);
    expect(b.isOn(BetaFeature.musixmatch), isFalse);
    expect(b.isOn(BetaFeature.spotify), isTrue);
    expect(notified, greaterThan(0));
    expect((await SharedPreferences.getInstance()).getBool('beta.musixmatch'), isFalse);

    final again = BetaFeatures();
    await again.load();
    expect(again.isOn(BetaFeature.musixmatch), isFalse);
    await again.set(BetaFeature.musixmatch, true);
    expect((await SharedPreferences.getInstance()).getBool('beta.musixmatch'), isTrue);
  });

  test('keys are unique and every feature has a one-line description', () {
    expect(BetaFeature.values.map(BetaFeatures.keyOf).toSet(), hasLength(BetaFeature.values.length));
    for (final f in BetaFeature.values) {
      expect(f.description, isNotEmpty);
      expect(f.description.contains('\n'), isFalse);
    }
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/lyrics_translation.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('pronunciation defaults on and preserves an explicitly saved off setting', () async {
    SharedPreferences.setMockInitialValues({});
    await LyricsTranslation.load();
    expect(LyricsTranslation.romanize.value, isTrue);
    SharedPreferences.setMockInitialValues({'lyrics.romanize': false});
    await LyricsTranslation.load();
    expect(LyricsTranslation.romanize.value, isFalse);
  });
}

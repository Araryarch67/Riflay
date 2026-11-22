import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/lyrics_translation.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('pronunciation defaults on and preserves an explicitly saved off setting', () async {
    SharedPreferences.setMockInitialValues({});
    LyricsTranslation.debugForgetLoad();
    await LyricsTranslation.load();
    expect(LyricsTranslation.romanize.value, isTrue);
    SharedPreferences.setMockInitialValues({'lyrics.romanize': false});
    // Loaded once per run; read again as a fresh start would.
    LyricsTranslation.debugForgetLoad();
    await LyricsTranslation.load();
    expect(LyricsTranslation.romanize.value, isFalse);
  });
}

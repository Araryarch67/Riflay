import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/language.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => Language.instance.set(AppLanguage.english));

  test('English by default whatever the device speaks, Indonesian when chosen, and it is kept', () async {
    await Language.instance.load();
    expect(Language.instance.choice, AppLanguage.english);
    expect(Language.instance.locale.languageCode, 'en');
    expect(tr.navSettings, 'Settings');
    expect(tr.songsCount(3), '3 songs');

    await Language.instance.set(AppLanguage.indonesian);
    expect(Language.instance.locale.languageCode, 'id');
    expect(tr.navSettings, 'Pengaturan');
    expect(tr.songsCount(3), '3 lagu');

    Language.instance.choice = AppLanguage.english;
    await Language.instance.load();
    expect(Language.instance.choice, AppLanguage.indonesian, reason: 'the choice is saved');
  });

  test('every English string has an Indonesian one, with the same placeholders', () {
    Map<String, dynamic> read(String f) => jsonDecode(File('lib/l10n/$f').readAsStringSync()) as Map<String, dynamic>;
    final en = read('app_en.arb'), id = read('app_id.arb');
    final keys = en.keys.where((k) => !k.startsWith('@'));
    for (final k in keys) {
      expect(id[k], isA<String>(), reason: '$k has no Indonesian');
      final holes = RegExp(r'\{(\w+)\}');
      expect(
        holes.allMatches(id[k] as String).map((m) => m[1]).toSet(),
        holes.allMatches(en[k] as String).map((m) => m[1]).toSet(),
        reason: '$k: placeholders differ',
      );
    }
  });
}

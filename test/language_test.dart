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

  test('Japanese when chosen', () async {
    await Language.instance.set(AppLanguage.japanese);
    expect(Language.instance.locale.languageCode, 'ja');
    expect(tr.navSettings, '設定');
    expect(tr.songsCount(3), '3曲');
    expect(tr.streakTooltip(1), 'リスニングストリーク：1日');
  });

  test('every English string is in every language, with the same placeholders', () {
    Map<String, dynamic> read(File f) => jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    final en = read(File('lib/l10n/app_en.arb'));
    final keys = en.keys.where((k) => !k.startsWith('@'));
    final others = Directory('lib/l10n')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.arb') && !f.path.endsWith('app_en.arb'));
    for (final language in AppLanguage.values.where((l) => l.code != null && l.code != 'en')) {
      expect(
        others.map((f) => f.path),
        contains('lib/l10n/app_${language.code}.arb'),
        reason: '${language.name} has no .arb',
      );
    }
    for (final f in others) {
      final other = read(f);
      for (final k in keys) {
        expect(other[k], isA<String>(), reason: '$k missing in ${f.path}');
        final holes = RegExp(r'\{(\w+)\}');
        expect(
          holes.allMatches(other[k] as String).map((m) => m[1]).toSet(),
          holes.allMatches(en[k] as String).map((m) => m[1]).toSet(),
          reason: '$k: placeholders differ in ${f.path}',
        );
      }
    }
  });
}

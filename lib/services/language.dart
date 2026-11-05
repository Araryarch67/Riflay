import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/generated/app_localizations.dart';

/// The languages Riflay speaks, as Settings › Look & feel › Appearance offers them. Each is named in its own
/// language, so someone who can't read the current one still finds theirs.
enum AppLanguage {
  system(null, ''),
  english('en', 'English'),
  indonesian('id', 'Bahasa Indonesia');

  const AppLanguage(this.code, this.ownName);

  /// Null for [system]: the device's language, when Riflay has it.
  final String? code;
  final String ownName;
}

/// The language the screens are in (Settings › Look & feel › Appearance › Language). [tr] gives the words in it.
class Language extends ChangeNotifier {
  Language._();

  static final instance = Language._();

  static const _key = 'language.v1';

  /// English until someone picks another language, wherever they are: the device's language is only followed
  /// when System is picked.
  AppLanguage choice = AppLanguage.english;

  /// The locale shown: the chosen one, or the device's when Riflay speaks it, else English.
  Locale get locale {
    final code = choice.code ?? PlatformDispatcher.instance.locale.languageCode;
    return AppLocalizations.supportedLocales.firstWhere(
      (l) => l.languageCode == code,
      orElse: () => const Locale('en'),
    );
  }

  AppLocalizations? _strings;
  Locale? _stringsFor;

  /// The words in [locale]; looked up once per language.
  AppLocalizations get strings {
    final l = locale;
    if (_stringsFor != l) {
      _strings = lookupAppLocalizations(l);
      _stringsFor = l;
    }
    return _strings!;
  }

  Future<void> load() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getString(_key);
      choice = AppLanguage.values.asNameMap()[saved] ?? AppLanguage.english;
    } catch (e) {
      debugPrint('Language setting unreadable: $e');
    }
  }

  Future<void> set(AppLanguage v) async {
    if (v == choice) return;
    choice = v;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setString(_key, v.name);
    } catch (e) {
      debugPrint('Language setting not saved: $e');
    }
  }

  /// The device's language changed: matters while following it.
  void deviceLocaleChanged() {
    if (choice == AppLanguage.system) notifyListeners();
  }
}

/// The app's words in the language shown now (see [Language]). Usable anywhere, also without a BuildContext;
/// a language change rebuilds every screen, so widgets reading it follow.
AppLocalizations get tr => Language.instance.strings;

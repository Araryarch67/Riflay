import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Settings › Accounts & services › Music sources: the free, lossless places Riflay looks besides YouTube Music
/// and SoundCloud. Both are on until turned off.
class MusicSources extends ChangeNotifier {
  MusicSources._();

  static final instance = MusicSources._();

  static const _archiveKey = 'sources.archive.v1';
  static const _radioKey = 'sources.radioParadise.v1';

  /// Search's "All" also shows Internet Archive recordings with FLAC files.
  bool archive = true;

  /// The search page shows Radio Paradise's FLAC channels before anything is typed.
  bool radioParadise = true;

  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final p = await SharedPreferences.getInstance();
    archive = p.getBool(_archiveKey) ?? true;
    radioParadise = p.getBool(_radioKey) ?? true;
    notifyListeners();
  }

  Future<void> setArchive(bool v) async {
    archive = v;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool(_archiveKey, v);
  }

  Future<void> setRadioParadise(bool v) async {
    radioParadise = v;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool(_radioKey, v);
  }

  @visibleForTesting
  void reset() {
    _loaded = false;
    archive = radioParadise = true;
  }
}

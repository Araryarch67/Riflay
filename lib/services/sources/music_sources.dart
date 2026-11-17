import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../merged_download.dart';

/// Settings › Accounts & services › Music sources: the places Riflay looks besides YouTube Music. Each one is on
/// until turned off.
class MusicSources extends ChangeNotifier {
  MusicSources._();

  static final instance = MusicSources._();

  static const _soundcloudKey = 'sources.soundcloud.v1';
  static const _monochromeKey = 'sources.monochrome.v1';
  static const _smartMergeKey = 'sources.smartMerge.v1';
  static const _cacheKey = 'sources.smartMergeCacheMb.v1';

  /// How much Smart merge keeps on disk of the songs it played (MB), so a song played again opens from there
  /// without asking the service; 0 keeps none.
  int smartMergeCacheMb = 1024;
  static const cacheChoices = [0, 512, 1024, 2048, 5120];
  bool soundcloud = true;
  bool monochrome = true;

  /// A YouTube Music song plays its sound from the best place that has the same recording (see `SmartMerge`).
  bool smartMerge = true;

  Future<void>? _loading;

  Future<void> load() => _loading ??= _read();

  Future<void> _read() async {
    final p = await SharedPreferences.getInstance();
    soundcloud = p.getBool(_soundcloudKey) ?? true;
    monochrome = p.getBool(_monochromeKey) ?? true;
    smartMerge = p.getBool(_smartMergeKey) ?? true;
    smartMergeCacheMb = p.getInt(_cacheKey) ?? 1024;
    _applyCache();
    notifyListeners();
  }

  Future<void> setSoundcloud(bool value) async {
    soundcloud = value;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool(_soundcloudKey, value);
  }

  Future<void> setMonochrome(bool value) async {
    monochrome = value;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool(_monochromeKey, value);
  }

  Future<void> setSmartMerge(bool value) async {
    smartMerge = value;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool(_smartMergeKey, value);
  }

  Future<void> setSmartMergeCacheMb(int mb) async {
    smartMergeCacheMb = mb;
    _applyCache();
    notifyListeners();
    await (await SharedPreferences.getInstance()).setInt(_cacheKey, mb);
  }

  void _applyCache() {
    MergedDownload.keptBytes = smartMergeCacheMb << 20;
    MergedDownload.keepsSongs = smartMergeCacheMb > 0 && MergedDownload.keepsByDefault;
  }

  @visibleForTesting
  void reset() {
    _loading = null;
    soundcloud = monochrome = smartMerge = true;
  }
}

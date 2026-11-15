import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Settings › Accounts & services › Music sources: the places Riflay looks besides YouTube Music. Each one is off
/// until turned on.
class MusicSources extends ChangeNotifier {
  MusicSources._();

  static final instance = MusicSources._();

  static const _soundcloudKey = 'sources.soundcloud.v1';
  static const _monochromeKey = 'sources.monochrome.v1';
  static const _smartMergeKey = 'sources.smartMerge.v1';
  bool soundcloud = false;
  bool monochrome = false;

  /// A YouTube Music song plays its sound from the best place that has the same recording (see `SmartMerge`).
  bool smartMerge = false;

  Future<void>? _loading;

  Future<void> load() => _loading ??= _read();

  Future<void> _read() async {
    final p = await SharedPreferences.getInstance();
    soundcloud = p.getBool(_soundcloudKey) ?? false;
    monochrome = p.getBool(_monochromeKey) ?? false;
    smartMerge = p.getBool(_smartMergeKey) ?? false;
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

  @visibleForTesting
  void reset() {
    _loading = null;
    soundcloud = monochrome = smartMerge = false;
  }
}

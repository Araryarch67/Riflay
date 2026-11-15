import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Settings › Accounts & services › Music sources: the places Riflay looks besides YouTube Music. Each one is off
/// until turned on.
class MusicSources extends ChangeNotifier {
  MusicSources._();

  static final instance = MusicSources._();

  static const _soundcloudKey = 'sources.soundcloud.v1';
  static const _monochromeKey = 'sources.monochrome.v1';
  bool soundcloud = false;
  bool monochrome = false;

  Future<void>? _loading;

  Future<void> load() => _loading ??= _read();

  Future<void> _read() async {
    final p = await SharedPreferences.getInstance();
    soundcloud = p.getBool(_soundcloudKey) ?? false;
    monochrome = p.getBool(_monochromeKey) ?? false;
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

  @visibleForTesting
  void reset() {
    _loading = null;
    soundcloud = monochrome = false;
  }
}

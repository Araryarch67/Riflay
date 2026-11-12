import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audius.dart';
import 'ccmixter.dart';
import 'jamendo.dart';
import 'song_source.dart';

/// Settings › Accounts & services › Music sources: the free places Riflay looks besides YouTube Music and
/// SoundCloud. Internet Archive and Radio Paradise are on until turned off; the song sources ([SongSource]:
/// Jamendo, Audius, ccMixter) are off until turned on.
class MusicSources extends ChangeNotifier {
  MusicSources._();

  static final instance = MusicSources._();

  static const _archiveKey = 'sources.archive.v1';
  static const _radioKey = 'sources.radioParadise.v1';

  /// Search's "All" also shows Internet Archive recordings with FLAC files.
  bool archive = true;

  /// The search page shows Radio Paradise's FLAC channels before anything is typed.
  bool radioParadise = true;

  /// Every optional song source, in the order its shelf and switch appear.
  static final List<SongSource> songSources = [Jamendo.instance, Audius.instance, CcMixter.instance];

  final Set<String> _on = {};

  static String _key(SongSource s) => 'sources.${s.prefix.replaceAll(':', '')}.v1';

  /// Whether search's "All" shows [source]'s songs.
  bool isOn(SongSource source) => source.available && _on.contains(source.prefix);

  /// The song sources search's "All" asks, in order.
  List<SongSource> get enabledSongSources => [
    for (final s in songSources)
      if (isOn(s)) s,
  ];

  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final p = await SharedPreferences.getInstance();
    archive = p.getBool(_archiveKey) ?? true;
    radioParadise = p.getBool(_radioKey) ?? true;
    _on
      ..clear()
      ..addAll([
        for (final s in songSources)
          if (p.getBool(_key(s)) ?? false) s.prefix,
      ]);
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

  Future<void> setOn(SongSource source, bool v) async {
    v ? _on.add(source.prefix) : _on.remove(source.prefix);
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool(_key(source), v);
  }

  @visibleForTesting
  void reset() {
    _loaded = false;
    archive = radioParadise = true;
    _on.clear();
  }
}

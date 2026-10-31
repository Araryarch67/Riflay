import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/features.dart';

/// A feature still in Beta that Settings › Beta features can switch off.
enum BetaFeature {
  musixmatch(
    'musixmatch',
    'Musixmatch lyrics',
    'Look for word-by-word lyrics on Musixmatch when other sources have none.',
  ),
  videoMode('video', 'Video mode', 'Watch a song\'s music video in the player, in step with the song.');

  const BetaFeature(this.id, this.title, this.description);

  /// Stored as `beta.<id>`.
  final String id;
  final String title;

  /// One plain line.
  final String description;

  /// Whether this build has the feature at all (the web build has no Video mode).
  bool get available => this != videoMode || Features.videoMode;
}

/// Which Beta features are on. All are on until switched off, so nothing changes for current users.
class BetaFeatures extends ChangeNotifier {
  BetaFeatures();

  static final instance = BetaFeatures();

  static String keyOf(BetaFeature f) => 'beta.${f.id}';

  final _off = <BetaFeature>{};
  Future<void>? _loading;

  /// Whether [f] is on. Before [load] finishes everything reads as on.
  bool isOn(BetaFeature f) => f.available && !_off.contains(f);

  /// Reads the saved switches once; later calls share the first.
  Future<void> load() => _loading ??= _read();

  Future<void> _read() async {
    try {
      final p = await SharedPreferences.getInstance();
      _off
        ..clear()
        ..addAll([
          for (final f in BetaFeature.values)
            if (p.getBool(keyOf(f)) == false) f,
        ]);
      notifyListeners();
    } catch (e) {
      debugPrint('Beta features not read: $e');
    }
  }

  Future<void> set(BetaFeature f, bool on) async {
    await load();
    if (on == isOn(f)) return;
    on ? _off.remove(f) : _off.add(f);
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setBool(keyOf(f), on);
    } catch (e) {
      debugPrint('Beta feature not saved: $e');
    }
  }

  /// Forgets what was read and loads again (tests).
  @visibleForTesting
  Future<void> reload() {
    _loading = null;
    return load();
  }
}

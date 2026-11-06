import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/features.dart';
import '../platform/host.dart';
import 'language.dart';

/// Optional player features, configured in their respective settings pages.
enum BetaFeature {
  musixmatch('musixmatch'),
  videoMode('video'),

  /// Android's Direct USB (Settings › Sound › Output & quality): experimental, so off until asked for, behind a
  /// warning. Off, the option isn't offered and Direct USB never runs.
  directUsb('directUsb');

  const BetaFeature(this.id);

  /// Stored as `features.<id>`; legacy beta keys are still read.
  final String id;
  String get title => switch (this) {
    musixmatch => tr.musixmatchLyrics,
    videoMode => tr.videoMode,
    directUsb => tr.directUsb,
  };

  /// One plain line.
  String get description => switch (this) {
    musixmatch => tr.betaMusixmatchBody,
    videoMode => tr.betaVideoModeBody,
    directUsb => tr.betaDirectUsbBody,
  };

  bool get defaultOn => this != directUsb;

  /// Whether this build has the feature at all (the web build has no Video mode).
  bool get available => switch (this) {
    videoMode => Features.videoMode,
    directUsb => Host.isAndroid,
    _ => true,
  };
}

/// Optional features, each with its own switch in its settings.
class BetaFeatures extends ChangeNotifier {
  BetaFeatures();

  static final instance = BetaFeatures();

  static String keyOf(BetaFeature f) => 'features.${f.id}';

  final _off = <BetaFeature>{
    for (final f in BetaFeature.values)
      if (!f.defaultOn) f,
  };
  Future<void>? _loading;

  /// Whether [f] is on.
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
            if ((p.getBool(keyOf(f)) ?? p.getBool('beta.${f.id}') ?? f.defaultOn) == false) f,
        ]);
      notifyListeners();
    } catch (e) {
      debugPrint('Feature preferences not read: $e');
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
      debugPrint('Feature preference not saved: $e');
    }
  }

  /// Forgets what was read and loads again (tests).
  @visibleForTesting
  Future<void> reload() {
    _loading = null;
    return load();
  }
}

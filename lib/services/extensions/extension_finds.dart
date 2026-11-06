import '../../models/track.dart';

/// Which extension found the songs played from its results, by the YouTube Music song they were matched to:
/// Detail stats says so ("Found with Apple Music"), since the sound itself comes from YouTube Music.
abstract final class ExtensionFinds {
  static final _by = <String, String>{};

  /// The extension that found [track], or null for a song found any other way.
  static String? of(Track track) => _by[track.id];

  static void remember(Track track, String extension) {
    _by.remove(track.id);
    _by[track.id] = extension;
    while (_by.length > 64) {
      _by.remove(_by.keys.first);
    }
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';
import '../platform/host.dart';
import 'cover_art.dart';
import 'private_files.dart';

/// Pictures the person chose for a playlist or Liked music, kept on this device.
///
/// YouTube Music draws a playlist's cover itself and has no way to replace it, so a cover picked here belongs to
/// Riflay alone: it is shown on every screen that lists the collection, and removing it brings the automatic cover
/// back. The picture is copied into the app's own folder (a browser keeps it in the settings as a small JPEG), so
/// moving or deleting the original file doesn't take it away.
class PlaylistCovers extends ChangeNotifier {
  PlaylistCovers._();

  static final instance = PlaylistCovers._();

  /// [Collection.coverKey] of YouTube Music's Liked music.
  static const likedKey = 'liked';

  /// [Collection.coverKey] of the library's All songs.
  static const allSongsKey = 'allSongs';

  /// [Collection.coverKey] of the library's downloaded songs.
  static const downloadsKey = 'downloads';

  /// [Collection.coverKey] of a smart playlist ([SmartList.id]).
  static String smartKey(String id) => 'smartList:$id';

  /// [Collection.coverKey] of a music folder, by its path.
  static String folderKey(String path) => 'folder:$path';

  /// [Collection.coverKey] of an album, by its title and artist.
  static String albumKey(String title, String artist) => 'album:${title.toLowerCase()}\u0000${artist.toLowerCase()}';

  /// [Collection.coverKey] of a Riflay playlist.
  static String playlistKey(String id) => 'pl:$id';

  /// [Collection.coverKey] of a YouTube Music playlist.
  static String remoteKey(String id) => 'remote:$id';

  static const _prefsKey = 'playlistCovers.v1';
  static const _folder = 'covers';

  /// A file name in [_folder], or a data URL in a browser.
  final _sources = <String, String>{};

  /// Bumped whenever a cover changes, so the artwork cache sees a new picture instead of the old one.
  final _revisions = <String, int>{};

  Directory? _dir;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _sources.clear();
    try {
      final saved = prefs.getString(_prefsKey);
      if (saved != null) {
        final map = jsonDecode(saved);
        if (map is Map) {
          for (final entry in map.entries) {
            if (entry.key is String && entry.value is String) _sources[entry.key as String] = entry.value as String;
          }
        }
      }
    } catch (e) {
      debugPrint('Ignoring unreadable playlist covers: $e');
    }
    _revisions.clear();
    _dir = null;
    if (!Host.isWeb) {
      try {
        _dir = Directory(p.join((await PrivateFiles.dir()).path, _folder));
      } catch (e) {
        // Widget tests have no app folder; the rest of the app still works without one.
        debugPrint('No playlist cover folder: $e');
      }
    }
    notifyListeners();
  }

  bool has(String? key) => key != null && _sources.containsKey(key);

  /// The picture chosen for [key], as a picture-only track for [Artwork], or null when it has none.
  Track? coverOf(String? key) {
    final source = key == null ? null : _sources[key];
    if (source == null) return null;
    final revision = _revisions[key] ?? 0;
    final id = 'cover:$key:$revision';
    if (source.startsWith('data:')) {
      return Track(id: id, uri: Uri.parse(source), title: '', artist: '', tagged: true, artworkUrl: source);
    }
    final dir = _dir;
    if (dir == null) return null;
    return Track(id: id, uri: Uri.file(p.join(dir.path, source)), title: '', artist: '', tagged: true);
  }

  /// [key]'s own picture when it has one, else [fallback].
  Track? coverOr(String? key, Track? fallback) => coverOf(key) ?? fallback;

  /// Replaces [key]'s cover with [image] (JPEG, PNG or WebP, any shape).
  Future<void> setCover(String key, Uint8List image) async {
    final jpeg = await CoverArt.squareJpeg(image, size: 900, quality: 88);
    final dir = _dir;
    if (Host.isWeb) {
      _sources[key] = 'data:image/jpeg;base64,${base64Encode(jpeg)}';
    } else {
      if (dir == null) throw const FileSystemException('The cover folder is not available');
      await dir.create(recursive: true);
      final name = '${sha1.convert(utf8.encode(key))}.jpg';
      final file = File(p.join(dir.path, name));
      final part = File('${file.path}.part');
      await part.writeAsBytes(jpeg, flush: true);
      await part.rename(file.path);
      _sources[key] = name;
    }
    _revisions[key] = (_revisions[key] ?? 0) + 1;
    await _save();
    notifyListeners();
  }

  /// Takes [key]'s picture away, bringing back the automatic cover.
  Future<void> removeCover(String key) async {
    final source = _sources.remove(key);
    _revisions[key] = (_revisions[key] ?? 0) + 1;
    final dir = _dir;
    if (source != null && dir != null && !source.startsWith('data:')) {
      try {
        await File(p.join(dir.path, source)).delete();
      } catch (e) {
        debugPrint('Old playlist cover not deleted: $e');
      }
    }
    await _save();
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(_sources));
  }
}

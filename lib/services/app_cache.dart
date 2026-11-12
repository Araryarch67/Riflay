import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'auto_eq.dart';
import 'youtube_audio_source.dart';

/// Settings › About › Clear cache: what Riflay keeps only to save the network or time, and fetches again when
/// it is gone. Covers of online songs and the media notification's copies, lyrics found online, YouTube Music's
/// Discover shelves, AutoEQ's list of headphones, Wrap's share images, and streamed songs a crash left behind.
///
/// Never touched: the library, playlists, downloads, settings, lyrics written by hand (`my-lyrics`), and the
/// loudness and bit-depth measurements (`audio-analysis.json`): measuring them again decodes every file, and
/// volume leveling uses them meanwhile. The songs streaming now stay too (the player drops them on its own).
///
/// The cache folders themselves stay: covers are written into folders opened once per launch.
abstract final class AppCache {
  /// Tests point these at folders of their own.
  @visibleForTesting
  static Future<({String support, String cache, String temp})> Function()? foldersOverride;

  static Future<({String support, String cache, String temp})> _folders() async =>
      await foldersOverride?.call() ??
      (
        support: (await getApplicationSupportDirectory()).path,
        cache: (await getApplicationCacheDirectory()).path,
        temp: (await getTemporaryDirectory()).path,
      );

  /// Everything [clear] deletes: folders (their contents go) and single files.
  static Future<List<FileSystemEntity>> _targets() async {
    final f = await _folders();
    final streaming = await YoutubeAudioSource.cacheFolder();
    final temp = Directory(f.temp);
    return [
      Directory(p.join(f.cache, 'artwork')),
      Directory(p.join(f.cache, 'now-playing-art')),
      Directory(p.join(f.support, 'lyrics-cache')),
      File(p.join(f.support, 'autoeq_index.md')),
      File(p.join(f.support, 'discover-cache.json')),
      Directory(p.join(f.temp, 'shared')),
      if (temp.existsSync())
        for (final e in temp.listSync())
          if (e is Directory && p.basename(e.path).startsWith('riflay-stream-') && e.path != streaming) e,
    ];
  }

  static int _sizeOf(FileSystemEntity e) {
    try {
      if (e is File) return e.existsSync() ? e.lengthSync() : 0;
      if (e is Directory && e.existsSync()) {
        var n = 0;
        for (final f in e.listSync(recursive: true, followLinks: false)) {
          if (f is File) n += f.lengthSync();
        }
        return n;
      }
    } on FileSystemException {
      // Gone or unreadable meanwhile: nothing to count.
    }
    return 0;
  }

  /// Bytes [clear] would free.
  static Future<int> size() async {
    if (kIsWeb) return 0;
    final targets = await _targets();
    return compute(_total, [for (final t in targets) (t.path, t is Directory)]);
  }

  static int _total(List<(String, bool)> paths) =>
      [for (final (path, dir) in paths) _sizeOf(dir ? Directory(path) : File(path))].fold(0, (a, b) => a + b);

  /// Deletes the cache, and returns the bytes freed. A file in use (Windows) is left for next time.
  static Future<int> clear() async {
    if (kIsWeb) return 0;
    var freed = 0;
    for (final t in await _targets()) {
      final bytes = _sizeOf(t);
      try {
        if (t is File) {
          if (t.existsSync()) await t.delete();
        } else if (t is Directory && t.existsSync()) {
          if (p.basename(t.path).startsWith('riflay-stream-')) {
            await t.delete(recursive: true);
          } else {
            for (final e in t.listSync()) {
              await e.delete(recursive: true);
            }
          }
        }
        freed += bytes;
      } on FileSystemException catch (e) {
        debugPrint('Clear cache: ${t.path}: $e');
        freed += bytes - _sizeOf(t);
      }
    }
    AutoEq.forgetIndex();
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    return freed;
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../ui/debug_switches.dart';
import 'ytmusic_web.dart';

/// A downloaded song's music video, kept beside it by "Download with MV": `<song>.mv.mp4` (or `.mv.webm`), the
/// picture stream as YouTube serves it (no sound: the song's own file is the sound), and `<song>.mv.json`, which
/// says which video it is and where the song's parts are in it, so Video mode lines it up offline too.
///
/// The files follow the song's name, not a folder of their own: they are wherever the song was downloaded to, and
/// go when it is deleted ([delete]). `RIFLAY_NO_LOCAL_MV` makes Video mode stream as if there were none.
abstract final class MvSidecar {
  static const _extensions = ['mp4', 'webm'];

  static String _stem(String songPath) => p.withoutExtension(songPath);

  /// The video file of the song at [songPath], in [ext] (`mp4` or `webm`).
  static File videoFile(String songPath, String ext) => File('${_stem(songPath)}.mv.$ext');

  /// The file that says which video it is ([encode]).
  static File infoFile(String songPath) => File('${_stem(songPath)}.mv.json');

  static final _name = RegExp(r'\.mv\.(mp4|webm|json)$', caseSensitive: false);

  /// Whether [path] is one of these files (a folder scan must not take the video for a song).
  static bool isSidecar(String path) => _name.hasMatch(path);

  static final _known = <String, ({File file, MusicVideo video})?>{};

  /// The downloaded music video of the song at [songPath], or null when it has none. Looked at once per song
  /// (two file checks and a small read) and kept; [forget] after writing or deleting one.
  static ({File file, MusicVideo video})? of(String songPath) {
    if (DebugSwitches.noLocalMv) return null;
    if (_known.containsKey(songPath)) return _known[songPath];
    ({File file, MusicVideo video})? found;
    try {
      for (final ext in _extensions) {
        final file = videoFile(songPath, ext);
        if (!file.existsSync()) continue;
        final info = infoFile(songPath);
        final video = info.existsSync() ? decode(info.readAsStringSync()) : null;
        // No readable map: the video on the song's own timeline, named after the song.
        found = (file: file, video: video ?? MusicVideo(videoId: p.basename(_stem(songPath))));
        break;
      }
    } on FileSystemException catch (e) {
      debugPrint('Music video beside $songPath: $e');
    }
    while (_known.length >= 512) {
      _known.remove(_known.keys.first);
    }
    return _known[songPath] = found;
  }

  /// [songPath]'s files changed: the next [of] looks again.
  static void forget(String songPath) => _known.remove(songPath);

  /// Writes which video lies beside [songPath] and how it lines up with the song.
  static Future<void> write(String songPath, MusicVideo video) async {
    final file = infoFile(songPath);
    final part = File('${file.path}.part');
    await part.writeAsString(encode(video));
    await part.rename(file.path);
    forget(songPath);
  }

  /// Removes the music video of the song at [songPath], if it has one. Returns how many files couldn't be deleted.
  static Future<int> delete(String songPath) async {
    var failed = 0;
    for (final file in [for (final ext in _extensions) videoFile(songPath, ext), infoFile(songPath)]) {
      try {
        if (FileSystemEntity.typeSync(file.path, followLinks: false) == FileSystemEntityType.file) await file.delete();
      } on FileSystemException {
        failed++;
      }
    }
    forget(songPath);
    return failed;
  }

  /// The size of the video beside [songPath], or 0 with none.
  static int bytesOf(String songPath) {
    try {
      for (final ext in _extensions) {
        final file = videoFile(songPath, ext);
        if (file.existsSync()) return file.lengthSync();
      }
    } on FileSystemException catch (_) {}
    return 0;
  }

  /// [video] as the text of the `.mv.json` file. Times are milliseconds.
  static String encode(MusicVideo video) => jsonEncode({
    'version': 1,
    'videoId': video.videoId,
    if (video.offset != Duration.zero) 'offsetMs': video.offset.inMilliseconds,
    if (video.rate != 1) 'rate': video.rate,
    if (video.segments.isNotEmpty)
      'segments': [
        for (final s in video.segments)
          [s.songStart.inMilliseconds, s.videoStart.inMilliseconds, s.length.inMilliseconds],
      ],
  });

  /// What [encode] wrote; null for anything unreadable.
  static MusicVideo? decode(String text) {
    try {
      final j = jsonDecode(text);
      if (j is! Map || j['videoId'] is! String || (j['videoId'] as String).isEmpty) return null;
      final segments = <VideoSegment>[];
      if (j['segments'] case final List list) {
        for (final s in list) {
          if (s is! List || s.length != 3 || s.any((v) => v is! int)) return null;
          segments.add(
            VideoSegment(
              songStart: Duration(milliseconds: s[0] as int),
              videoStart: Duration(milliseconds: s[1] as int),
              length: Duration(milliseconds: s[2] as int),
            ),
          );
        }
      }
      return MusicVideo(
        videoId: j['videoId'] as String,
        segments: segments,
        offset: Duration(milliseconds: (j['offsetMs'] as num?)?.toInt() ?? 0),
        rate: (j['rate'] as num?)?.toDouble() ?? 1,
      );
    } catch (_) {
      return null;
    }
  }
}

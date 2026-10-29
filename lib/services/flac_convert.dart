import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/track.dart';
import 'download_prefs.dart';
import 'metadata.dart';
import 'player_controller.dart';
import 'sacd.dart';
import 'youtube_importer.dart';

/// "Convert to FLAC (Beta)": turns a song already in the library (a YouTube download, or a file in another
/// format) into a FLAC, with the machinery downloads use ([YoutubeImporter.toFlac]).
abstract final class FlacConvert {
  /// Formats that already keep every sample; converting them gains nothing. DSD is here too: it plays as it is.
  static const _lossless = {
    'flac',
    'wav',
    'aiff',
    'aif',
    'aifc',
    'alac',
    'w64',
    'caf',
    'wv',
    'ape',
    'tta',
    'dsf',
    'dff',
  };

  /// Ids being converted right now, so a second tap on the same song does nothing.
  static final _running = <String>{};

  /// Whether [t] is a lossy file Riflay could turn into a FLAC, going by its name alone (no disk access, so a menu
  /// can ask for every row). A song's ALAC inside an .m4a is only found while converting: see [isAlac].
  static bool isConvertible(Track t) {
    final path = t.path;
    if (path == null || t.isRemote || t.isCueTrack || SacdDisc.isSacdTrack(t)) return false;
    final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
    return Track.audioExtensions.contains(ext) && !_lossless.contains(ext);
  }

  /// Whether the menu should offer the conversion for [t]: a convertible file, and a device that can make FLAC.
  static bool available(Track t) => YoutubeImporter.canMakeFlac && isConvertible(t);

  /// Whether [t] is a file Riflay made (a download), which the FLAC replaces, rather than one the person added,
  /// which is kept. [downloadsDir] is the downloads folder; a download from an earlier folder has a [Track.sourceUrl].
  static bool replacesOriginal(Track t, String downloadsDir) {
    final path = t.path;
    return path != null && (t.sourceUrl != null || p.isWithin(downloadsDir, path));
  }

  /// Where the FLAC of [source] goes: beside it, or in [downloadsDir] when [keepOriginal] is set and the song's
  /// own folder can't be written to (Android). A name already taken gets " (2)", " (3)"… so nothing is overwritten.
  static String targetPath(
    String source, {
    required bool keepOriginal,
    required String downloadsDir,
    bool folderWritable = true,
    bool Function(String path)? exists,
  }) {
    final taken = exists ?? (String path) => File(path).existsSync();
    final folder = keepOriginal && !folderWritable ? downloadsDir : p.dirname(source);
    final stem = p.basenameWithoutExtension(source);
    var path = p.join(folder, '$stem.flac');
    for (var n = 2; taken(path); n++) {
      path = p.join(folder, '$stem ($n).flac');
    }
    return path;
  }

  /// Whether the .m4a / .mp4 at [path] holds Apple Lossless (its `alac` sample entry), already lossless.
  static Future<bool> isAlac(String path) async {
    final ext = p.extension(path).toLowerCase();
    if (ext != '.m4a' && ext != '.mp4' && ext != '.m4b') return false;
    RandomAccessFile? file;
    try {
      file = await File(path).open();
      final length = await file.length();
      var at = 0;
      // Top-level boxes: size (4 bytes), type (4 bytes); `moov` holds the sample descriptions.
      while (at + 8 <= length) {
        await file.setPosition(at);
        final head = ByteData.sublistView(await file.read(8));
        var size = head.getUint32(0);
        final type = String.fromCharCodes([for (var i = 4; i < 8; i++) head.getUint8(i)]);
        if (size == 1) {
          final big = ByteData.sublistView(await file.read(8));
          size = big.getUint32(4);
        } else if (size == 0) {
          size = length - at;
        }
        if (size < 8) return false;
        if (type == 'moov') {
          if (size > 64 << 20) return false;
          await file.setPosition(at);
          final moov = await file.read(size);
          const alac = [0x61, 0x6C, 0x61, 0x63];
          for (var i = 0; i + 4 <= moov.length; i++) {
            if (moov[i] == alac[0] && moov[i + 1] == alac[1] && moov[i + 2] == alac[2] && moov[i + 3] == alac[3]) {
              return true;
            }
          }
          return false;
        }
        at += size;
      }
    } catch (e) {
      debugPrint('FLAC convert: couldn\'t look inside $path: $e');
    } finally {
      await file?.close();
    }
    return false;
  }

  /// Whether files can be made in [dir].
  static Future<bool> _writable(Directory dir) async {
    try {
      final probe = File(p.join(dir.path, '.riflay-write-test'));
      await probe.writeAsString('');
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Makes the FLAC of [track] at [quality] and returns the song as it is now: the same id (so playlists, likes and
  /// lyrics still find it) pointing at the FLAC, which is not yet in the library: pass it to
  /// [PlayerController.replaceTrack]. A download's old file is deleted once the FLAC is complete; a file the person
  /// added is kept. Title, artist, album, numbers and cover go into the FLAC. Throws when the FLAC can't be made;
  /// nothing half-written is left behind.
  static Future<Track> convertFile(
    Track track,
    FlacQuality quality, {
    required Directory downloadsDir,
    bool Function()? isCancelled,
  }) async {
    final path = track.path;
    if (path == null || !isConvertible(track)) throw StateError('${track.id} can\'t be made into a FLAC.');
    final source = File(path);
    if (!source.existsSync()) throw FileSystemException('The song\'s file is missing', path);
    if (await isAlac(path)) throw const AlreadyLossless();
    final replace = replacesOriginal(track, downloadsDir.path);
    final writable = replace || await _writable(source.parent);
    final target = File(
      targetPath(path, keepOriginal: !replace, downloadsDir: downloadsDir.path, folderWritable: writable),
    );
    await target.parent.create(recursive: true);

    // What the file says about the song, read before it is touched: a conversion through libmpv carries no tags,
    // and ffmpeg's carry-over leaves the cover behind.
    final edit = await _tagsOf(track);

    // toFlac deletes what it converts, so a file that stays gets converted from a copy.
    File input = source;
    if (!replace) {
      input = File(
        p.join(target.parent.path, '${p.basenameWithoutExtension(target.path)}.riflay-src${p.extension(path)}'),
      );
      await source.copy(input.path);
    }
    try {
      await YoutubeImporter.toFlac(input, target, quality, isCancelled: isCancelled);
    } finally {
      if (!replace && input.existsSync()) input.deleteSync();
    }
    try {
      await Metadata.tagFile(target.path, edit);
    } catch (e) {
      // Tags are never worth the song: a FLAC without them still plays.
      debugPrint('FLAC convert: couldn\'t tag ${target.path}: $e');
    }
    if (!replace) await _copyLyrics(path, target.path);
    Metadata.forgetArtwork(track);
    return track.copyWith(uri: Uri.file(target.path));
  }

  /// The tags to write into the FLAC, from the library entry first and the file for what the library lacks.
  static Future<TagEdit> _tagsOf(Track track) async {
    TagEdit? file;
    try {
      file = await Metadata.readTags(track);
    } catch (e) {
      debugPrint('FLAC convert: couldn\'t read tags of ${track.path}: $e');
    }
    final edit = TagEdit(
      title: track.title,
      artist: track.artist,
      album: track.album,
      year: file?.year,
      trackNumber: track.trackNumber ?? file?.trackNumber,
      discNumber: track.discNumber ?? file?.discNumber,
      genre: file?.genre,
    );
    // Keeps the link a download came from; Ogg and MP3 carry theirs over, the FLAC writer has no comment field.
    edit.comment = track.sourceUrl;
    try {
      final cover = await Metadata.artwork(track);
      if (cover != null) {
        edit.cover = cover;
        edit.coverMime = _isPng(cover) ? 'image/png' : 'image/jpeg';
      }
    } catch (e) {
      debugPrint('FLAC convert: couldn\'t read the cover of ${track.path}: $e');
    }
    return edit;
  }

  static bool _isPng(Uint8List b) => b.length > 4 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47;

  /// A song's `.lrc` sits beside its file, so a FLAC made somewhere else needs its own copy to keep the lyrics.
  static Future<void> _copyLyrics(String from, String to) async {
    final lrc = File(p.setExtension(from, '.lrc'));
    final copy = p.setExtension(to, '.lrc');
    if (lrc.path == copy || !lrc.existsSync() || File(copy).existsSync()) return;
    try {
      await lrc.copy(copy);
    } catch (e) {
      debugPrint('FLAC convert: couldn\'t copy the lyrics of $from: $e');
    }
  }

  /// Converts [tracks] one after another and tells the person how it went through [PlayerController.notify]. Each
  /// converted song is replaced in the library as it finishes, so a stop halfway keeps what was done.
  static Future<void> convertAll(PlayerController c, List<Track> tracks, FlacQuality quality) async {
    final todo = tracks.where((t) => isConvertible(t) && !_running.contains(t.id)).toList();
    if (todo.isEmpty) return;
    final dir = await YoutubeImporter.downloadsDir();
    _running.addAll(todo.map((t) => t.id));
    c.notify(todo.length == 1 ? 'Converting ${todo.first.title} to FLAC…' : 'Converting ${todo.length} songs to FLAC…');
    var done = 0;
    var already = 0;
    final failed = <Track>[];
    for (final t in todo) {
      try {
        await c.replaceTrack(await convertFile(t, quality, downloadsDir: dir));
        done++;
      } on AlreadyLossless {
        already++;
      } catch (e) {
        debugPrint('FLAC convert: couldn\'t convert ${t.path}: $e');
        failed.add(t);
      } finally {
        _running.remove(t.id);
      }
    }
    if (todo.length == 1) {
      c.notify(
        done == 1
            ? 'Converted ${todo.first.title} to FLAC'
            : already == 1
            ? '${todo.first.title} is already lossless'
            : 'Couldn\'t convert ${todo.first.title}',
      );
      return;
    }
    String songs(int n) => n == 1 ? '1 song' : '$n songs';
    c.notify(
      failed.isEmpty
          ? 'Converted ${songs(done)} to FLAC'
          : done == 0
          ? 'Couldn\'t convert these songs'
          : 'Converted ${songs(done)} to FLAC, ${failed.length} couldn\'t be converted',
    );
  }
}

/// A file that is already lossless (Apple Lossless in an .m4a), found while converting.
class AlreadyLossless implements Exception {
  /// Creates the marker.
  const AlreadyLossless();
}

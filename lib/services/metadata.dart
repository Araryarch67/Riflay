import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../models/track.dart';
import '../platform/background.dart';
import '../platform/host.dart';
import 'cover_palette.dart';
import 'ffmpeg.dart';
import 'tag_writer.dart';

/// Who is waiting for a cover. A widget that leaves (scrolled away) cancels
/// its request; a cover nobody waits for any more is not read from its file.
class ArtworkRequest {
  bool _cancelled = false;
  bool get cancelled => _cancelled;
  void cancel() => _cancelled = true;
}

class _PendingArt {
  final requests = <ArtworkRequest>{};
  late Future<Uint8List?> future;
  bool dropped = false;

  /// Asked for only by widgets that have since gone.
  bool get abandoned => requests.isNotEmpty && requests.every((r) => r.cancelled);
}

/// Editable tags of one file.
class TagEdit {
  TagEdit({this.title, this.artist, this.album, this.year, this.trackNumber, this.discNumber, this.genre});

  String? title;
  String? artist;
  String? album;
  int? year;
  int? trackNumber;
  int? discNumber;
  String? genre;

  /// A free comment (a download's YouTube link). Unlike the fields above, null keeps whatever the file has.
  /// Written for every format the tag editor handles: ID3 COMM, Vorbis COMMENT (Ogg, Opus, FLAC), M4A ©cmt.
  String? comment;

  /// New front cover (replaces every embedded picture); null keeps the current one.
  Uint8List? cover;
  String coverMime = 'image/jpeg';
}

/// Reads embedded tags / cover art off the UI thread and caches the results.
abstract final class Metadata {
  /// Encoded covers kept in memory, newest last. Capped by size: an embedded
  /// hi-res cover can be several MB, so a count alone could hold hundreds.
  static const _maxCachedArtworkBytes = 16 << 20;
  static var _cachedArtworkBytes = 0;

  static final _artwork = <String, Uint8List?>{};
  static final _pendingArtwork = <String, _PendingArt>{};
  static final _accents = <String, Color>{};
  static final _pendingAccents = <String, Future<Color>>{};
  static final _coverColors = <String, CoverColors?>{};
  static final _pendingCoverColors = <String, Future<CoverColors?>>{};

  /// Returns [track] with title/artist/album/duration filled from its tags.
  static Future<Track> enrich(Track track) =>
      track.path == null ? Future.value(track.copyWith(tagged: true)) : inBackground(() => _enrichNow(track));

  /// [enrich] for many songs: batches of files are read in a few background
  /// isolates side by side (an isolate per file cost more than reading it).
  /// [onBatch] gets each batch as it's done.
  static Future<void> enrichAll(List<Track> tracks, void Function(List<Track> enriched) onBatch) async {
    const batch = 48;
    var next = 0;
    Future<void> worker() async {
      while (next < tracks.length) {
        final chunk = tracks.sublist(next, math.min(next + batch, tracks.length));
        next += chunk.length;
        onBatch(await _enrichBatch(chunk));
      }
    }

    final workers = (Platform.numberOfProcessors ~/ 2).clamp(1, 4);
    await Future.wait([for (var i = 0; i < workers; i++) worker()]);
  }

  /// A function of its own, so the isolate is sent the batch alone: a closure
  /// written inside [enrichAll] would carry `onBatch` (and the player behind it) along.
  static Future<List<Track>> _enrichBatch(List<Track> chunk) =>
      inBackground(() => [for (final t in chunk) _enrichNow(t)]);

  static Track _enrichNow(Track track) {
    final path = track.path;
    if (path == null) return track.copyWith(tagged: true);
    try {
      final m = readMetadata(File(path));
      return track.copyWith(
        title: _clean(m.title),
        artist: _clean(m.artist ?? m.albumArtist),
        album: _clean(m.album),
        duration: m.duration,
        trackNumber: m.trackNumber,
        discNumber: m.discNumber,
        tagged: true,
      );
    } catch (_) {
      return track.copyWith(tagged: true);
    }
  }

  /// FLAC and MP4/M4A (AAC, ALAC) are written in-process: the bundled writers
  /// keep every other tag, including ReplayGain and other freeform MP4 atoms
  /// that ffmpeg's MP4 muxer would drop. MP3, Ogg, WAV, AIFF, WavPack and APE
  /// go through [TagWriter], also in-process, on every platform. Only Matroska
  /// (and a layout [TagWriter] turns down, like ID3v2.2) needs the `ffmpeg`
  /// command, on a computer (installed, or fetched on first use: [Ffmpeg]).
  static const _inProcess = {'flac', 'm4a', 'm4b', 'mp4'};

  static const _ffmpegWritable = {'mka'};

  /// Looks for `ffmpeg` once at startup so [canEditTags] can answer synchronously.
  static Future<void> probeTagTools() => Ffmpeg.probe();

  /// Whether `ffmpeg` is here or can be fetched when needed ([probeTagTools] must have run).
  static bool get hasFfmpeg => Ffmpeg.available;

  static String _ext(String path) => path.split('.').last.toLowerCase();

  static bool canEditTags(Track t) {
    final path = t.path;
    if (path == null || t.isCueTrack) return false;
    final ext = _ext(path);
    return _inProcess.contains(ext) ||
        TagWriter.formats.contains(ext) ||
        (Ffmpeg.available && _ffmpegWritable.contains(ext));
  }

  /// Whether "Change cover" can be offered for [t].
  static bool canEditCover(Track t) => _inProcess.contains(_ext(t.path!)) || TagWriter.formats.contains(_ext(t.path!));

  static Future<TagEdit> readTags(Track track) {
    final path = track.path!;
    return inBackground(() {
      final m = readMetadata(File(path));
      return TagEdit(
        title: m.title,
        artist: m.artist,
        album: m.album,
        year: m.year?.year,
        trackNumber: m.trackNumber,
        discNumber: m.discNumber,
        genre: m.genres.firstOrNull,
      )..comment = m.comment;
    });
  }

  /// Writes [edit] into the file, safely: the change is made on a copy, which
  /// must come out readable before it replaces the original.
  static Future<Track> writeTags(Track track, TagEdit edit) async {
    _sniffCover(edit);
    final path = track.path!;
    final dot = path.lastIndexOf('.');
    final temp = File('${path.substring(0, dot)}.riflay-tmp${path.substring(dot)}');
    try {
      if (_inProcess.contains(_ext(path))) {
        await inBackground(() => _writeInProcess(path, temp, edit));
      } else if (TagWriter.formats.contains(_ext(path))) {
        try {
          await inBackground(() => _writeWithTagWriter(path, temp, edit));
        } on UnsupportedTagLayout catch (e) {
          if (!Ffmpeg.available) rethrow;
          debugPrint('Tag editor: $e, trying ffmpeg');
          await _writeWithFfmpeg(path, temp, edit);
        }
      } else {
        await _writeWithFfmpeg(path, temp, edit);
      }
      await temp.rename(path);
    } finally {
      if (temp.existsSync()) temp.deleteSync();
    }
    _forgetArtwork(_artKey(track));
    _accents.remove(_artKey(track));
    _coverColors.remove(_artKey(track));
    final updated = await enrich(track.copyWith(tagged: false));
    _forgetArtwork(_artKey(updated));
    _accents.remove(_artKey(updated));
    _coverColors.remove(_artKey(updated));
    return updated;
  }

  /// Writes [edit] into the file at [path] (a download that was just made), on a copy that replaces it only
  /// when it reads back right. Nothing else about the file changes. Throws when it can't be tagged.
  static Future<void> tagFile(String path, TagEdit edit) async {
    _sniffCover(edit);
    final dot = path.lastIndexOf('.');
    final temp = File('${path.substring(0, dot)}.riflay-tmp${path.substring(dot)}');
    try {
      if (_inProcess.contains(_ext(path))) {
        await inBackground(() => _writeInProcess(path, temp, edit));
      } else if (TagWriter.formats.contains(_ext(path))) {
        await inBackground(() => _writeWithTagWriter(path, temp, edit));
      } else {
        throw UnsupportedTagLayout('.${_ext(path)}');
      }
      await temp.rename(path);
    } finally {
      if (temp.existsSync()) temp.deleteSync();
    }
  }

  /// The cover's MIME type from its bytes, not from what the caller said (a PNG saved as `.jpg` stays a PNG).
  static void _sniffCover(TagEdit edit) {
    final c = edit.cover;
    if (c == null || c.length < 4) return;
    if (c[0] == 0xff && c[1] == 0xd8) {
      edit.coverMime = 'image/jpeg';
    } else if (c[0] == 0x89 && c[1] == 0x50 && c[2] == 0x4e && c[3] == 0x47) {
      edit.coverMime = 'image/png';
    }
  }

  static void _writeInProcess(String path, File temp, TagEdit edit) {
    File(path).copySync(temp.path);
    updateMetadata(temp, (m) {
      m.setTitle(edit.title);
      m.setArtist(edit.artist);
      m.setAlbum(edit.album);
      m.setYear(edit.year == null ? null : DateTime(edit.year!));
      m.setTrackNumber(edit.trackNumber);
      switch (m) {
        case final VorbisMetadata v:
          v.discNumber = edit.discNumber;
        case final Mp4Metadata v:
          v.discNumber = edit.discNumber;
        default:
      }
      m.setGenres([?edit.genre]);
      if (edit.comment != null) m.setComment(edit.comment);
      if (edit.cover != null) m.setPictures([Picture(edit.cover!, edit.coverMime, PictureType.coverFront)]);
    });
    final check = readMetadata(temp);
    if (check.title != edit.title || check.discNumber != edit.discNumber) {
      throw const FileSystemException('The new info didn\'t save correctly; the file was left as it was');
    }
  }

  static void _writeWithTagWriter(String path, File temp, TagEdit edit) {
    TagWriter.write(path, temp, edit);
    final check = readMetadata(temp);
    if (check.title != edit.title || check.discNumber != edit.discNumber) {
      throw const FileSystemException('The new info didn\'t save correctly; the file was left as it was');
    }
  }

  static Future<void> _writeWithFfmpeg(String path, File temp, TagEdit edit) async {
    final cover = edit.cover != null && _ext(path) == 'mp3';
    File? coverFile;
    if (cover) {
      coverFile = File('${temp.path}.${edit.coverMime == 'image/png' ? 'png' : 'jpg'}')..writeAsBytesSync(edit.cover!);
    }
    // Ogg keeps its tags (Vorbis comments) on the audio stream, not the file.
    final scope = const {'ogg', 'oga', 'opus'}.contains(_ext(path)) ? ':s:a:0' : '';
    try {
      final r = await Process.run(await Ffmpeg.executable(), [
        '-hide_banner', '-loglevel', 'error', '-y', '-i', path, //
        if (cover) ...['-i', coverFile!.path, '-map', '0', '-map', '-0:v?', '-map', '1'] else ...['-map', '0'],
        '-c', 'copy', '-map_metadata', '0',
        for (final (key, value) in [
          ('title', edit.title),
          ('artist', edit.artist),
          ('album', edit.album),
          ('date', edit.year),
          ('track', edit.trackNumber),
          ('disc', edit.discNumber),
          ('genre', edit.genre),
        ]) ...['-metadata$scope', '$key=${value ?? ''}'],
        if (cover) ...['-disposition:v:0', 'attached_pic'],
        if (_ext(path) == 'mp3') ...['-id3v2_version', '3'],
        temp.path,
      ]);
      if (r.exitCode != 0 || !temp.existsSync() || temp.lengthSync() == 0) {
        throw FileSystemException('Couldn\'t write the new info: ${(r.stderr as String).trim()}');
      }
    } finally {
      if (coverFile != null && coverFile.existsSync()) coverFile.deleteSync();
    }
  }

  static String? _clean(String? s) {
    final t = s?.trim();
    return t == null || t.isEmpty ? null : t;
  }

  /// Artwork already in memory, so widgets can paint it on the first frame.
  static Uint8List? cachedArtwork(Track track) => _artwork[_artKey(track)];

  static bool hasCachedArtwork(Track track) => _artwork.containsKey(_artKey(track));

  /// Tracks on the same album share one cover lookup.
  static String _artKey(Track t) => t.albumKey ?? t.id;

  /// Drops the cover remembered for [track] (and its album), after it was changed on disk.
  static void forgetArtwork(Track track) {
    _forgetArtwork(_artKey(track));
    _accents.remove(_artKey(track));
    _coverColors.remove(_artKey(track));
  }

  static void _forgetArtwork(String key) {
    _cachedArtworkBytes -= _artwork.remove(key)?.length ?? 0;
    _thumbBytes -= _thumbs.remove(key)?.length ?? 0;
  }

  /// Covers asked for by [artwork] with a [ArtworkRequest] that was cancelled
  /// before their file was read are skipped, and counted nowhere.
  static Future<Uint8List?> artwork(Track track, {ArtworkRequest? request}) {
    final key = _artKey(track);
    if (_artwork.containsKey(key)) return Future.value(_artwork[key]);
    final pending = _pendingArtwork[key];
    if (pending != null) {
      if (request != null) pending.requests.add(request);
      return pending.future;
    }
    final entry = _PendingArt();
    if (request != null) entry.requests.add(request);
    _pendingArtwork[key] = entry;
    entry.future = _loadArtwork(track, entry).then((bytes) {
      _pendingArtwork.remove(key);
      // Nobody wanted it any more: not remembered as "has no cover".
      if (entry.dropped) return null;
      _artwork[key] = bytes;
      _cachedArtworkBytes += bytes?.length ?? 0;
      while (_cachedArtworkBytes > _maxCachedArtworkBytes && _artwork.length > 1) {
        _cachedArtworkBytes -= _artwork.remove(_artwork.keys.first)?.length ?? 0;
      }
      return bytes;
    });
    return entry.future;
  }

  /// Longest side of the small covers lists and the mini player paint.
  static const thumbnailSide = 256;
  static const _maxThumbBytes = 12 << 20;
  static var _thumbBytes = 0;

  /// Least recently used first.
  static final _thumbs = <String, Uint8List?>{};
  static final _pendingThumbs = <String, Future<Uint8List?>>{};

  /// Covers cut down by [thumbnail] since start (tests).
  @visibleForTesting
  static int thumbnailsMade = 0;

  /// Cover files read since start (tests).
  @visibleForTesting
  static int coversRead = 0;

  static Uint8List? cachedThumbnail(Track track) {
    final key = _artKey(track);
    final t = _thumbs.remove(key);
    if (t != null || _thumbs.containsKey(key)) _thumbs[key] = t;
    return t;
  }

  static bool hasCachedThumbnail(Track track) => _thumbs.containsKey(_artKey(track));

  /// The cover at about [thumbnailSide] px, made once (in an isolate) and
  /// remembered, so a list of covers doesn't decode full-size pictures again.
  static Future<Uint8List?> thumbnail(Track track, {ArtworkRequest? request}) {
    final key = _artKey(track);
    if (_thumbs.containsKey(key)) return Future.value(cachedThumbnail(track));
    return _pendingThumbs[key] ??= artwork(track, request: request).then((full) async {
      Uint8List? small;
      if (full != null) {
        try {
          small = await inBackground(() => _shrink(full));
          thumbnailsMade++;
        } catch (_) {
          small = full;
        }
      }
      _pendingThumbs.remove(key);
      _thumbs[key] = small;
      _thumbBytes += small?.length ?? 0;
      while (_thumbBytes > _maxThumbBytes && _thumbs.length > 1) {
        _thumbBytes -= _thumbs.remove(_thumbs.keys.first)?.length ?? 0;
      }
      return small;
    });
  }

  static Uint8List _shrink(Uint8List full) {
    final image = img.decodeImage(full);
    if (image == null || (image.width <= thumbnailSide && image.height <= thumbnailSide)) return full;
    final small = image.width >= image.height
        ? img.copyResize(image, height: thumbnailSide, interpolation: img.Interpolation.average)
        : img.copyResize(image, width: thumbnailSide, interpolation: img.Interpolation.average);
    return Uint8List.fromList(img.encodeJpg(small, quality: 88));
  }

  static Future<Uint8List?> _loadArtwork(Track track, _PendingArt entry) {
    final path = track.path;
    if (path == null) return _networkArtwork(track.artworkUrl);
    final done = Completer<Uint8List?>();
    _fileArtQueue.add((path, done, entry));
    if (_fileArtReaders < 2) {
      _fileArtReaders++;
      // After this frame: the rows that scrolled into view all ask first.
      Timer.run(_readFileArt);
    }
    return done.future;
  }

  /// Covers waiting to be read from their files.
  static final _fileArtQueue = <(String, Completer<Uint8List?>, _PendingArt)>[];
  static int _fileArtReaders = 0;

  /// Reads the queue a batch per isolate, not a cover per isolate: a list
  /// scrolling into view asks for twenty at once, and starting an isolate
  /// cost the UI thread about as much as reading the cover did. Covers whose
  /// widgets are gone (scrolled far away, page closed) are not read.
  static Future<void> _readFileArt() async {
    try {
      while (_fileArtQueue.isNotEmpty) {
        final taken = _fileArtQueue.take(8).toList();
        _fileArtQueue.removeRange(0, taken.length);
        final batch = <(String, Completer<Uint8List?>, _PendingArt)>[];
        for (final e in taken) {
          if (e.$3.abandoned) {
            e.$3.dropped = true;
            e.$2.complete(null);
          } else {
            batch.add(e);
          }
        }
        if (batch.isEmpty) continue;
        coversRead += batch.length;
        List<Uint8List?> found;
        try {
          found = await _readCovers([for (final (path, _, _) in batch) path]);
        } catch (_) {
          found = List.filled(batch.length, null);
        }
        for (var i = 0; i < batch.length; i++) {
          batch[i].$2.complete(found[i]);
        }
      }
    } finally {
      _fileArtReaders--;
    }
  }

  static Future<List<Uint8List?>> _readCovers(List<String> paths) => inBackground(
    () => [
      for (final path in paths)
        () {
          try {
            return _embeddedPicture(path) ?? _sidecarImage(path);
          } catch (_) {
            return null;
          }
        }(),
    ],
  );

  /// One connection pool for every cover: a fresh client per image would pay
  /// a TLS handshake each time.
  static final _artHttp = http.Client();

  /// Covers of YouTube songs, kept on disk so the next launch paints them
  /// without the network. Null where there is no cache folder (tests).
  static final Future<Directory?> _artDir = () async {
    try {
      final dir = Directory('${(await getApplicationCacheDirectory()).path}${Host.pathSeparator}artwork');
      await dir.create(recursive: true);
      _pruneArtCache(dir).ignore();
      return dir;
    } catch (_) {
      return null;
    }
  }();

  /// Keeps the newest few thousand covers (each ~20-60 KB).
  static Future<void> _pruneArtCache(Directory dir, {int keep = 3000}) async {
    final files = await dir.list().where((e) => e is File).cast<File>().toList();
    if (files.length <= keep) return;
    final dated = [for (final f in files) (f, (await f.stat()).modified)]..sort((a, b) => b.$2.compareTo(a.$2));
    for (final (f, _) in dated.skip(keep)) {
      f.delete().ignore();
    }
  }

  static Future<Uint8List?> _networkArtwork(String? url) async {
    if (url == null) return null;
    final dir = await _artDir;
    final file = dir == null ? null : File('${dir.path}${Host.pathSeparator}${sha1.convert(url.codeUnits)}');
    try {
      if (file != null && await file.exists()) return await file.readAsBytes();
    } catch (_) {}
    try {
      final res = await _artHttp.get(Uri.parse(url));
      if (res.statusCode != 200) return null;
      if (file != null) {
        // Written aside and renamed, so a half-written cover never gets read.
        final part = File('${file.path}.part');
        part.writeAsBytes(res.bodyBytes).then((_) => part.rename(file.path)).ignore();
      }
      return res.bodyBytes;
    } catch (_) {
      return null;
    }
  }

  static const _coverHeaders = {'User-Agent': 'Riflay (https://github.com/Araryarch67/Riflay)'};

  /// Looks up the front cover of [album] by [artist] on MusicBrainz and
  /// downloads it from the Cover Art Archive. Null when nothing is found;
  /// throws when the services can't be reached.
  ///
  /// Takes the 1200 px rendition: sharp on any screen, while originals are
  /// often 20 MB+ scans that would be embedded into every song of the album.
  static Future<({Uint8List bytes, String mime})?> findCoverOnline(
    String artist,
    String album, {
    http.Client? client,
  }) async {
    final http.Client c = client ?? _artHttp;
    String quote(String s) => '"${s.replaceAllMapped(RegExp(r'["\\]'), (m) => '\\${m[0]}')}"';
    final search = Uri.https('musicbrainz.org', '/ws/2/release-group/', {
      'query': 'releasegroup:${quote(album)} AND artist:${quote(artist)}',
      'fmt': 'json',
      'limit': '5',
    });
    // MusicBrainz turns away some requests with 503 when it's busy (about one
    // in five, even one every few seconds) and asks clients to try again shortly.
    var res = await c.get(search, headers: _coverHeaders);
    for (var wait = 1; res.statusCode == 503 && wait <= 2; wait++) {
      await Future<void>.delayed(Duration(seconds: wait));
      res = await c.get(search, headers: _coverHeaders);
    }
    if (res.statusCode != 200) throw HttpException('MusicBrainz ${res.statusCode}');
    final groups = ((jsonDecode(utf8.decode(res.bodyBytes)) as Map)['release-groups'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        // Low scores are other albums that only share a word.
        .where((g) => ((g['score'] as num?) ?? 0) >= 90)
        .take(3);
    for (final g in groups) {
      final art = await c.get(
        Uri.https('coverartarchive.org', '/release-group/${g['id']}/front-1200'),
        headers: _coverHeaders,
      );
      if (art.statusCode == 404) continue;
      if (art.statusCode != 200) throw HttpException('Cover Art Archive ${art.statusCode}');
      final png = art.headers['content-type']?.contains('png') ?? false;
      return (bytes: art.bodyBytes, mime: png ? 'image/png' : 'image/jpeg');
    }
    return null;
  }

  static Uint8List? _embeddedPicture(String path) {
    try {
      final pictures = readMetadata(File(path), getImage: true).pictures;
      if (pictures.isEmpty) return null;
      final front = pictures.where((p) => p.pictureType == PictureType.coverFront);
      return (front.isEmpty ? pictures.first : front.first).bytes;
    } catch (_) {
      return null;
    }
  }

  /// `song.jpg` next to `song.m4a` (YouTube imports), then the usual folder art names.
  static Uint8List? _sidecarImage(String path) {
    final dir = File(path).parent.path;
    final stem = path.substring(0, path.lastIndexOf('.'));
    final candidates = [
      for (final ext in ['jpg', 'jpeg', 'png', 'webp']) '$stem.$ext',
      for (final name in ['cover', 'folder', 'front', 'Cover', 'Folder', 'Front'])
        for (final ext in ['jpg', 'png']) '$dir${Host.pathSeparator}$name.$ext',
    ];
    for (final c in candidates) {
      final f = File(c);
      // A cover, not a 100 MB scan someone named cover.png.
      if (f.existsSync() && f.lengthSync() < 32 << 20) return f.readAsBytesSync();
    }
    return null;
  }

  /// Neutral grey for anything without cover art.
  static const fallbackAccent = Color(0xFF535353);

  static Color? cachedAccent(Track track) => _accents[_artKey(track)];

  /// A punchy colour sampled from the cover art, for gradients and the mini player.
  static Future<Color> accent(Track track) {
    final key = _artKey(track);
    final cached = _accents[key];
    if (cached != null) return Future.value(cached);
    return _pendingAccents[key] ??= () async {
      final bytes = await artwork(track);
      final color = (bytes == null ? null : await _averageColor(bytes)) ?? fallbackAccent;
      _pendingAccents.remove(key);
      return _accents[key] = color;
    }();
  }

  /// The cover's colours if they were worked out already (null: not yet, or the cover has none).
  static CoverColors? cachedCoverColors(Track track) => _coverColors[_artKey(track)];

  /// The base and accent colours of the cover, for the Dynamic theme. The art is decoded once at 32 x 32
  /// and looked at in an isolate; remembered per cover. Null when there is no art. Never throws.
  static Future<CoverColors?> coverColors(Track track) {
    final key = _artKey(track);
    if (_coverColors.containsKey(key)) return Future.value(_coverColors[key]);
    return _pendingCoverColors[key] ??= () async {
      CoverColors? result;
      try {
        final bytes = await artwork(track);
        final rgba = bytes == null ? null : await _smallPixels(bytes);
        if (rgba != null) result = await inBackground(() => extractCoverColors(rgba));
      } catch (e) {
        debugPrint('Cover colours not read: $e');
      }
      _pendingCoverColors.remove(key);
      return _coverColors[key] = result;
    }();
  }

  static Future<Uint8List?> _smallPixels(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 32, targetHeight: 32);
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      frame.image.dispose();
      codec.dispose();
      return data?.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (_) {
      return null;
    }
  }

  static Future<Color?> _averageColor(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 16, targetHeight: 16);
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      frame.image.dispose();
      if (data == null) return null;
      var r = 0, g = 0, b = 0, n = 0;
      for (var i = 0; i < data.lengthInBytes; i += 4) {
        r += data.getUint8(i);
        g += data.getUint8(i + 1);
        b += data.getUint8(i + 2);
        n++;
      }
      final hsl = HSLColor.fromColor(Color.fromARGB(255, r ~/ n, g ~/ n, b ~/ n));
      // Keep it rich enough to read as a colour against black, but never neon.
      // A grey cover stays grey: forcing colour into it would tint everything red.
      if (hsl.saturation < 0.08) return hsl.withLightness(hsl.lightness.clamp(0.3, 0.45)).toColor();
      return hsl
          .withSaturation(hsl.saturation.clamp(0.35, 0.8))
          .withLightness(hsl.lightness.clamp(0.3, 0.45))
          .toColor();
    } catch (_) {
      return null;
    }
  }
}

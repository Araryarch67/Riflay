import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/track.dart';
import 'cover_art.dart';
import 'download_prefs.dart';
import 'ffmpeg.dart';
import 'flac_stream.dart';
import 'lyrics.dart';
import 'pcm_decoder.dart';
import 'private_files.dart';
import 'metadata.dart';
import 'ranged_download.dart';
import 'youtube_links.dart';
import 'youtube_stream.dart';
import 'webm_opus.dart';
import 'ytdlp.dart';
import 'ytmusic_web.dart';

enum DownloadStatus { queued, downloading, done, failed, cancelled }

/// What a running download is doing. Only [converting] is a real conversion (FLAC, MP3, a lower bitrate);
/// [finishing] is the quick remux and tagging at the end. Neither has progress to show.
enum DownloadPhase {
  downloading,
  converting,
  finishing;

  /// The line a list or notification shows for this phase.
  String get label => switch (this) {
    downloading => 'Downloading',
    converting => 'Converting…',
    finishing => 'Finishing…',
  };

  /// The phase after the stream has arrived: a conversion converts; a plain save only remuxes and tags.
  static DownloadPhase afterDownload(Conversion? convert) => convert == null ? finishing : converting;
}

/// Whether a partial file from an earlier run can be continued: only when the freshly resolved stream is the very
/// same one (same itag, same size). Stream URLs expire, so the URL is always resolved again first.
bool canResumePart({
  required String? savedItag,
  required int? savedSize,
  required String? freshItag,
  required int? freshSize,
  required int partBytes,
}) =>
    partBytes > 0 &&
    savedItag != null &&
    savedItag == freshItag &&
    savedSize != null &&
    savedSize == freshSize &&
    partBytes < savedSize;

/// One video being turned into a library track.
class DownloadJob {
  DownloadJob({
    required this.videoId,
    required this.title,
    required this.channel,
    required this.thumbnailUrl,
    this.knownNames = false,
    this.choice,
    this.album,
  });

  /// The format and quality asked for; null follows Settings when the download starts.
  DownloadChoice? choice;

  final String videoId;
  final String title;
  final String channel;

  /// [title] and [channel] are the song's real title and artist (a YouTube
  /// Music song), not a video title and uploader that still need splitting.
  final bool knownNames;
  final String thumbnailUrl;

  /// The album YouTube Music names for the song, if it does; goes in the file's tags.
  final String? album;

  DownloadStatus status = DownloadStatus.queued;
  double progress = 0;

  /// What the saved file really is, e.g. "Opus · 160 kbps", known once the stream is picked.
  String? quality;

  /// File size once the stream is resolved, and how much of it has arrived.
  int? totalBytes;
  int receivedBytes = 0;

  /// Smoothed transfer rate; null until the first sample.
  double? bytesPerSecond;

  Duration? get eta {
    final total = totalBytes, rate = bytesPerSecond;
    if (total == null || rate == null || rate <= 0) return null;
    return Duration(milliseconds: ((total - receivedBytes) / rate * 1000).round());
  }

  DownloadPhase phase = DownloadPhase.downloading;

  /// The stream has arrived and is being converted (FLAC, MP3, or a lower bitrate): no progress to show.
  bool get converting => phase == DownloadPhase.converting;

  String? error;
  Track? track;

  bool get isActive => status == DownloadStatus.queued || status == DownloadStatus.downloading;

  /// What is kept between runs; null for jobs that need no keeping (done, cancelled).
  Map<String, dynamic>? toJson() {
    if (status != DownloadStatus.queued && status != DownloadStatus.downloading && status != DownloadStatus.failed) {
      return null;
    }
    return {
      'videoId': videoId,
      'title': title,
      'channel': channel,
      'thumbnailUrl': thumbnailUrl,
      'knownNames': knownNames,
      'album': album,
      'status': status.name,
      'error': error,
      if (choice case final c?) 'choice': {'format': c.format.name, 'kbps': c.kbps, 'flac': c.flac.name},
    };
  }

  /// A job kept by [toJson], as it starts a new run: a download that was running goes back to waiting;
  /// a failed one stays failed (with Retry). Null for anything unreadable.
  static DownloadJob? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['videoId'], title = json['title'];
    if (id is! String || !YoutubeImporter.isVideoId(id) || title is! String) return null;
    DownloadChoice? choice;
    if (json['choice'] case final Map c) {
      final format = DownloadFormat.values.where((f) => f.name == c['format']).firstOrNull;
      if (format != null) {
        choice = DownloadChoice(
          format,
          kbps: c['kbps'] as int?,
          flac: FlacQuality.values.where((q) => q.name == c['flac']).firstOrNull ?? FlacQuality.standard,
        );
      }
    }
    final failed = json['status'] == DownloadStatus.failed.name;
    return DownloadJob(
        videoId: id,
        title: title,
        channel: json['channel'] as String? ?? '',
        thumbnailUrl: json['thumbnailUrl'] as String? ?? '',
        knownNames: json['knownNames'] == true,
        choice: choice,
        album: json['album'] as String?,
      )
      ..status = failed ? DownloadStatus.failed : DownloadStatus.queued
      ..error = failed ? (json['error'] as String? ?? 'Failed') : null;
  }
}

/// The download was held back because the phone is on mobile data and the user turned that off.
class _OnMobileData implements Exception {
  const _OnMobileData();
}

/// The job was cancelled while a file was being converted.
class _Cancelled implements Exception {
  const _Cancelled();
}

/// MP3 was chosen on a device without ffmpeg.
class _NoMp3 implements Exception {
  const _NoMp3();
}

/// FLAC was chosen on a device that can neither run ffmpeg nor decode with libmpv.
class _NoFlac implements Exception {
  const _NoFlac();
}

/// What a download fetches and what it becomes.
class _Audio {
  const _Audio({
    required this.url,
    required this.size,
    required this.sourceExt,
    required this.ext,
    required this.quality,
    this.convert,
    this.estimatedSize,
  });

  final Uri url;

  /// Size of the stream as served (not of the converted file).
  final int? size;

  /// The stream's own container ('webm' or 'm4a'): the file as downloaded.
  final String sourceExt;

  /// The saved file's extension: 'opus' for YouTube's Opus (remuxed out of its WebM), 'm4a', 'flac' or 'mp3'.
  final String ext;

  /// What the saved file is, e.g. "Opus · 96 kbps" or "FLAC · 16-bit / 48 kHz".
  final String quality;

  /// Applied after the stream has arrived; null keeps it byte-for-byte.
  final Conversion? convert;

  /// For FLAC and MP3: about how big the saved file will be.
  final int? estimatedSize;
}

/// What a pasted link resolved to, shown before the user commits to downloading.
sealed class YoutubePreview {
  const YoutubePreview();
}

class VideoPreview extends YoutubePreview {
  const VideoPreview(this.video);
  final Video video;
}

class PlaylistPreview extends YoutubePreview {
  const PlaylistPreview(this.playlist, this.videos);
  final Playlist playlist;
  final List<Video> videos;
}

/// Resolves YouTube links and downloads their audio-only stream into the app's
/// music folder, one job at a time.
class YoutubeImporter extends ChangeNotifier {
  YoutubeImporter({required this.onTrackReady, this.albumYearLookup, this._queueFile});

  /// Called with each finished track so it can be added to the library.
  final Future<void> Function(Track track) onTrackReady;

  /// The year an album came out; YouTube Music's own page by default.
  final Future<int?> Function(String album, String artist)? albumYearLookup;

  static const _maxPlaylistVideos = 200;

  final _yt = YoutubeExplode();

  /// Shared client, also used for streaming and YouTube search.
  YoutubeExplode get client => _yt;
  final List<DownloadJob> _jobs = [];

  List<DownloadJob> get jobs => List.unmodifiable(_jobs.reversed);
  int get activeCount => _jobs.where((j) => j.isActive).length;

  /// Overall progress of queued + running jobs, for the toolbar indicator.
  double? get activeProgress {
    final active = _jobs.where((j) => j.isActive).toList();
    if (active.isEmpty) return null;
    return active.fold(0.0, (sum, j) => sum + j.progress) / active.length;
  }

  /// Whether a bitrate below the best stream's can be made (ffmpeg is there).
  static bool get canReencode => Ffmpeg.available;

  /// Whether FLAC can be made: with ffmpeg, or on phones by libmpv decoding and [FlacStream] packing.
  /// Whether MP3 can be made: it needs ffmpeg (installed, or fetched on first use).
  static bool get canMakeMp3 => Ffmpeg.available;

  static bool get canMakeFlac => Ffmpeg.available || MpvPcm.supported;

  static bool looksLikeYoutubeUrl(String text) => YoutubeLinks.looksLikeLink(text);

  /// Where downloads live: ~/Documents/Riflay/YouTube on desktop, the app's
  /// private documents folder on mobile.
  static Future<Directory> downloadsDir() async {
    // A folder the user chose (computers); the default if it can't be used any more.
    if (DownloadPrefs.instance.folder case final chosen? when !Platform.isAndroid && !Platform.isIOS) {
      try {
        return await Directory(chosen).create(recursive: true);
      } catch (e) {
        debugPrint('Downloads folder $chosen unusable: $e');
      }
    }
    final docs = await getApplicationDocumentsDirectory();
    final mobile = Platform.isAndroid || Platform.isIOS;
    final dir = Directory(mobile ? p.join(docs.path, 'YouTube') : p.join(docs.path, 'Riflay', 'YouTube'));
    return dir.create(recursive: true);
  }

  /// Looks up a link. Pure playlist links (`/playlist?list=`) resolve to the whole
  /// playlist; watch links resolve to the single video even if they carry a list.
  Future<YoutubePreview> resolve(String url) async {
    final link = YoutubeLinks.parse(url, allowBareId: true);
    if (link is VideoLink) return VideoPreview(await _yt.videos.get(link.videoId));
    if (link is! PlaylistLink) throw const FormatException('That doesn\'t look like a YouTube link.');
    final playlistId = link.playlistId;
    final playlist = await _yt.playlists.get(playlistId);
    final videos = await _yt.playlists.getVideos(playlistId).take(_maxPlaylistVideos).toList();
    return PlaylistPreview(playlist, videos);
  }

  /// Queues videos for download; ones already queued or downloaded are skipped.
  /// Returns how many were newly queued.
  int enqueue(List<Video> videos, {DownloadChoice? choice}) => _enqueue([
    for (final v in videos)
      DownloadJob(
        videoId: v.id.value,
        title: v.title,
        channel: v.author,
        thumbnailUrl: v.thumbnails.highResUrl,
        choice: choice,
      ),
  ]);

  /// Saves streamed YouTube Music songs for offline playback.
  int enqueueTracks(List<Track> tracks, {DownloadChoice? choice}) => _enqueue([
    for (final t in tracks.where((t) => t.isRemote))
      DownloadJob(
        videoId: t.videoId!,
        title: t.title,
        channel: t.artist,
        thumbnailUrl: t.artworkUrl ?? 'https://i.ytimg.com/vi/${t.videoId}/hqdefault.jpg',
        knownNames: true,
        choice: choice,
        album: _clean(t.album),
      ),
  ]);

  /// The newest download of [videoId], if any (queued, running, done or failed).
  DownloadJob? jobFor(String videoId) => _jobs.where((j) => j.videoId == videoId).lastOrNull;

  /// YouTube's video ids: 11 letters, digits, `-` and `_`. Downloads are named
  /// after them, so anything else (a reply that was tampered with) must not
  /// reach a file name.
  static final _videoId = RegExp(r'^[A-Za-z0-9_-]{11}$');

  static bool isVideoId(String id) => _videoId.hasMatch(id);

  // ---- the queue survives the app being closed ----

  File? _queueFile;
  YtMusicWeb? _web;
  Timer? _saveTimer;
  String? _saved;
  bool _frozen = false;

  /// The jobs worth keeping as JSON text.
  static String encodeQueue(Iterable<DownloadJob> jobs) => jsonEncode({
    'version': 1,
    'jobs': [for (final j in jobs) ?j.toJson()],
  });

  /// The jobs [encodeQueue] kept, as a new run starts them. Unreadable text gives none.
  static List<DownloadJob> decodeQueue(String text) {
    try {
      final root = jsonDecode(text);
      final list = root is Map ? root['jobs'] : null;
      if (list is! List) return const [];
      final seen = <String>{};
      return [
        for (final item in list)
          if (DownloadJob.fromJson(item) case final job? when seen.add(job.videoId)) job,
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<File?> _file() async {
    if (_queueFile != null) return _queueFile;
    try {
      return _queueFile = await PrivateFiles.file('download_queue.json');
    } catch (_) {
      return null;
    }
  }

  /// Brings back what an earlier run left: waiting and interrupted downloads start again, failed ones show Retry.
  /// Half-written files are not continued (see [canResumePart]): the download starts clean.
  Future<void> restoreQueue() async {
    final file = await _file();
    if (file == null) return;
    try {
      if (!file.existsSync()) return;
      final jobs = decodeQueue(await file.readAsString());
      _saved = encodeQueue(jobs);
      for (final job in jobs) {
        if (_jobs.any((j) => j.videoId == job.videoId)) continue;
        _jobs.add(job);
      }
      if (jobs.isNotEmpty) {
        notifyListeners();
        unawaited(_drain());
      }
    } catch (e) {
      debugPrint('Download queue: couldn\'t restore: $e');
    }
  }

  void _scheduleSave() {
    if (_frozen) return;
    if (encodeQueue(_jobs) == _saved) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), () => unawaited(_save()));
  }

  Future<void> _save() async {
    _saveTimer?.cancel();
    final text = encodeQueue(_jobs);
    if (text == _saved) return;
    final file = await _file();
    if (file == null) return;
    _saved = text;
    try {
      await PrivateFiles.write(file, text);
    } catch (e) {
      _saved = null;
      debugPrint('Download queue: couldn\'t save: $e');
    }
  }

  /// Writes the queue now (tests, and when the app is closing).
  @visibleForTesting
  Future<void> flushQueue() => _save();

  @override
  void notifyListeners() {
    super.notifyListeners();
    _scheduleSave();
  }

  int _enqueue(List<DownloadJob> fresh) {
    var added = 0;
    for (final job in fresh.where((j) => _videoId.hasMatch(j.videoId))) {
      final existing = _jobs.where((j) => j.videoId == job.videoId).firstOrNull;
      if (existing != null && existing.status != DownloadStatus.failed && existing.status != DownloadStatus.cancelled) {
        continue;
      }
      _jobs.remove(existing);
      _jobs.add(job);
      added++;
    }
    notifyListeners();
    unawaited(_drain());
    return added;
  }

  void retry(DownloadJob job) {
    job
      ..status = DownloadStatus.queued
      ..progress = 0
      ..error = null;
    notifyListeners();
    unawaited(_drain());
  }

  void cancel(DownloadJob job) {
    if (!job.isActive) return;
    // The running download notices this between chunks and cleans up.
    job.status = DownloadStatus.cancelled;
    notifyListeners();
  }

  void clearFinished() {
    _jobs.removeWhere((j) => !j.isActive);
    notifyListeners();
  }

  /// Songs downloaded at the same time. Most of each job is yt-dlp resolving
  /// the stream (~1.5 s), so overlapping jobs speeds up playlists a lot.
  static const _parallelJobs = 3;
  int _running = 0;

  Future<void> _drain() async {
    while (_running < _parallelJobs) {
      final job = _jobs.where((j) => j.status == DownloadStatus.queued).firstOrNull;
      if (job == null) return;
      job
        ..status = DownloadStatus.downloading
        ..phase = DownloadPhase.downloading;
      _running++;
      unawaited(
        _download(job).whenComplete(() {
          _running--;
          _drain();
        }),
      );
    }
  }

  /// Size and quality of what a download would save. Exact, except for FLAC and MP3, which are
  /// estimated ([approx]): the stream's size says little about the file made from it.
  Future<({int? size, bool approx, String quality})?> peekAudio(String videoId, {DownloadChoice? choice}) async {
    try {
      await DownloadPrefs.instance.load();
      final r = await _resolveAudio(videoId, choice ?? DownloadPrefs.instance.choice);
      final made = r.convert is ToFlac || r.convert is ToMp3;
      return (size: made ? r.estimatedSize : r.size, approx: made, quality: r.quality);
    } catch (_) {
      return null;
    }
  }

  /// The audio to fetch (URL, size, the stream's container), and what the saved file will be.
  Future<_Audio> _resolveAudio(String videoId, DownloadChoice choice) async {
    final canReencode = Ffmpeg.available;
    // YouTube's player API (yt-dlp on desktop if refused), then the in-app extractor.
    try {
      final r = await YoutubeStream.forDownload(videoId, choice, canReencode: canReencode);
      final sourceExt = r.audio.ext == 'webm' ? 'webm' : 'm4a';
      return _Audio(
        url: r.audio.url,
        size: r.audio.size,
        sourceExt: sourceExt,
        ext: _savedExt(r.convert, sourceExt),
        quality: _qualityOf(r.convert, opus: r.audio.isOpus, kbps: r.audio.kbps),
        convert: r.convert,
        estimatedSize: _madeSize(r.convert, size: r.audio.size, kbps: r.audio.kbps),
      );
    } catch (e) {
      if (YtDlp.supported) rethrow;
      debugPrint('YouTube stream lookup failed, trying youtube_explode: $e');
    }
    final manifest = await _yt.videos.streams.getManifest(videoId);
    final pick = pickForDownload(
      [for (final s in manifest.audioOnly) AudioCandidate.fromExplode(s, processed: _isDrcOrDubbed(s))],
      choice,
      canReencode: canReencode,
    );
    if (pick == null) throw StateError('No playable audio stream for this video.');
    final stream = pick.candidate.ref! as AudioOnlyStreamInfo;
    final sourceExt = stream.container == StreamContainer.webM ? 'webm' : 'm4a';
    return _Audio(
      url: stream.url,
      size: stream.size.totalBytes,
      sourceExt: sourceExt,
      ext: _savedExt(pick.convert, sourceExt),
      quality: pick.label,
      convert: pick.convert,
      estimatedSize: _madeSize(pick.convert, size: stream.size.totalBytes, kbps: pick.candidate.kbps),
    );
  }

  /// The extension the saved file gets: YouTube's WebM Opus becomes an Ogg `.opus`.
  static String _savedExt(Conversion? convert, String sourceExt) => switch (convert) {
    ToFlac() => 'flac',
    ToMp3() => 'mp3',
    _ => sourceExt == 'webm' ? 'opus' : sourceExt,
  };

  static String? _clean(String? s) {
    final t = s?.trim();
    return t == null || t.isEmpty ? null : t;
  }

  /// The FLAC's or MP3's likely size.
  static int? _madeSize(Conversion? convert, {required int? size, required int? kbps}) =>
      _flacSize(convert, size: size, kbps: kbps) ?? _mp3Size(convert, size: size, kbps: kbps);

  /// The MP3's size: the song's length (from the stream's size and bitrate) times the MP3's bitrate.
  static int? _mp3Size(Conversion? convert, {required int? size, required int? kbps}) {
    if (convert is! ToMp3 || size == null || kbps == null || kbps <= 0) return null;
    return size * convert.kbps ~/ kbps;
  }

  /// The FLAC's likely size, from the stream's size and bitrate (which give the song's length).
  static int? _flacSize(Conversion? convert, {required int? size, required int? kbps}) {
    if (convert is! ToFlac || size == null || kbps == null || kbps <= 0) return null;
    final length = Duration(milliseconds: size * 8 ~/ kbps);
    return estimateFlacBytes(length, convert.quality, compressed: Ffmpeg.available);
  }

  static String _qualityOf(Conversion? convert, {required bool opus, required int? kbps}) => switch (convert) {
    ToFlac(:final quality) => describeFlac(quality, fromOpus: opus, fromKbps: kbps),
    ToMp3(kbps: final target) => 'MP3 · $target kbps',
    Reencode(kbps: final target) => describeAudio(opus: opus, kbps: target),
    null => describeAudio(opus: opus, kbps: kbps),
  };

  /// Phones only, and only if the user turned mobile data off for downloads.
  static Future<bool> _blockedByMobileData() async {
    if (!Platform.isAndroid && !Platform.isIOS) return false;
    await DownloadPrefs.instance.load();
    if (DownloadPrefs.instance.mobileData) return false;
    try {
      final now = await Connectivity().checkConnectivity();
      final cellular = now.contains(ConnectivityResult.mobile);
      final other = now.any((c) => c == ConnectivityResult.wifi || c == ConnectivityResult.ethernet);
      return cellular && !other;
    } catch (_) {
      return false;
    }
  }

  /// Converts [input] down to [kbps] in the same codec, replacing it. Returns the new file: Opus comes out as an
  /// Ogg `<id>.opus` (ffmpeg writes it directly), AAC replaces [input].
  static Future<File> _reencode(File input, {required bool opus, required int kbps}) async {
    final target = opus ? File(p.setExtension(input.path, '.opus')) : input;
    final out = File('${target.path}.small.part');
    try {
      final r = await Process.run(await Ffmpeg.executable(), [
        '-hide_banner', '-loglevel', 'error', '-y', '-i', input.path, '-map', '0:a:0', '-vn', '-map_metadata', '-1', //
        ...opus
            ? ['-c:a', 'libopus', '-b:a', '${kbps}k', '-f', 'opus']
            : ['-c:a', 'aac', '-b:a', '${kbps}k', '-movflags', '+faststart', '-f', 'mp4'],
        out.path,
      ]);
      if (r.exitCode != 0 || !out.existsSync() || out.lengthSync() == 0) {
        throw StateError('ffmpeg could not convert the download: ${r.stderr}');
      }
      if (input.existsSync()) await input.delete();
      return await out.rename(target.path);
    } catch (_) {
      if (out.existsSync()) out.deleteSync();
      rethrow;
    }
  }

  /// Makes [source] (a downloaded stream) into [target] (an .mp3) at a constant [kbps], by writing `<target>.part`
  /// and renaming it. Deletes [source] once the MP3 is in place. Needs ffmpeg. Returns [target].
  @visibleForTesting
  static Future<File> toMp3(File source, File target, int kbps) async {
    final part = File('${target.path}.part');
    try {
      if (!Ffmpeg.available) throw const _NoMp3();
      final r = await Process.run(await Ffmpeg.executable(), [
        '-hide_banner', '-loglevel', 'error', '-y', '-i', source.path, '-map', '0:a:0', '-vn', '-map_metadata', '-1', //
        '-c:a', 'libmp3lame', '-b:a', '${kbps}k', '-id3v2_version', '4', '-f', 'mp3', part.path,
      ]);
      if (r.exitCode != 0) throw StateError('ffmpeg could not make the MP3: ${r.stderr}');
      if (!part.existsSync() || part.lengthSync() == 0) throw StateError('The MP3 came out empty.');
      await part.rename(target.path);
      if (source.path != target.path && source.existsSync()) await source.delete();
      return target;
    } catch (_) {
      if (part.existsSync()) part.deleteSync();
      rethrow;
    }
  }

  /// YouTube's WebM Opus as an Ogg `.opus` file next to it (the packets are copied, not re-encoded); [webm] is
  /// removed. If that can't be done the WebM is returned as it is: a download is never lost over its container.
  @visibleForTesting
  static Future<File> remuxOpus(File webm) async {
    final target = File(p.setExtension(webm.path, '.opus'));
    final part = File('${target.path}.part');
    try {
      await WebmOpus.remuxFile(webm.path, part.path);
      if (!part.existsSync() || part.lengthSync() == 0) throw StateError('The Opus file came out empty.');
      await part.rename(target.path);
      await webm.delete();
      return target;
    } catch (e) {
      debugPrint('Download: couldn\'t remux ${webm.path} to Opus, keeping the WebM: $e');
      if (part.existsSync()) part.deleteSync();
      return webm;
    }
  }

  /// Makes [source] (a downloaded stream) into [target] (a .flac) at [q], by writing `<target>.part` and renaming it.
  /// Deletes [source] once the FLAC is in place. ffmpeg where there is one; otherwise libmpv decodes and
  /// [FlacStream] packs the samples (no compression, so those files are larger). Returns [target].
  static Future<File> toFlac(File source, File target, FlacQuality q, {bool Function()? isCancelled}) async {
    final part = File('${target.path}.part');
    try {
      if (Ffmpeg.available) {
        final r = await Process.run(await Ffmpeg.executable(), [
          '-hide_banner', '-loglevel', 'error', '-y', '-i', source.path, '-map', '0:a:0', '-vn', //
          '-c:a', 'flac', '-ar', '${q.rate}',
          ...q.bits == 16 ? ['-sample_fmt', 's16'] : ['-sample_fmt', 's32', '-bits_per_raw_sample', '24'],
          '-f', 'flac', part.path,
        ]);
        if (r.exitCode != 0) throw StateError('ffmpeg could not make the FLAC: ${r.stderr}');
      } else if (MpvPcm.supported) {
        await _flacWithMpv(source, part, q, isCancelled: isCancelled);
      } else {
        throw const _NoFlac();
      }
      if (isCancelled?.call() ?? false) throw const _Cancelled();
      if (!part.existsSync() || part.lengthSync() == 0) throw StateError('The FLAC came out empty.');
      await part.rename(target.path);
      if (source.path != target.path && source.existsSync()) await source.delete();
      return target;
    } catch (_) {
      if (part.existsSync()) part.deleteSync();
      rethrow;
    }
  }

  static Future<void> _flacWithMpv(File source, File out, FlacQuality q, {bool Function()? isCancelled}) async {
    final pcm = await MpvPcm.decode(PcmInput.file(source.path), rate: q.rate, bits: q.bits == 16 ? 16 : 32);
    final file = await out.open(mode: FileMode.write);
    var pcmBytes = 0;
    try {
      final counted = pcm.data.map((chunk) {
        pcmBytes += chunk.length;
        return chunk;
      });
      await for (final block in FlacStream.encode(
        counted,
        rate: pcm.rate,
        channels: pcm.channels,
        bits: q.bits,
        compression: FlacCompression.fast,
      )) {
        if (isCancelled?.call() ?? false) throw const _Cancelled();
        await file.writeFrom(block);
      }
      // FlacStream writes STREAMINFO with an unknown length, which leaves players without a duration or a seek bar.
      // The length is known now, so put it in (STREAMINFO starts at byte 8; rate, channels, bits and the sample
      // count are at byte 10 of it).
      final samples = pcmBytes ~/ (pcm.channels * (q.bits == 16 ? 2 : 4));
      final b = ByteData(8)
        ..setUint32(0, (pcm.rate << 12) | ((pcm.channels - 1) << 9) | ((q.bits - 1) << 4) | ((samples >> 32) & 0xF))
        ..setUint32(4, samples & 0xFFFFFFFF);
      await file.setPosition(18);
      await file.writeFrom(b.buffer.asUint8List());
    } finally {
      await pcm.cancel();
      await file.close();
    }
  }

  Future<void> _download(DownloadJob job) async {
    notifyListeners();
    File? partFile;
    File? downloaded;
    File? converted;
    try {
      await DownloadPrefs.instance.load();
      if (await _blockedByMobileData()) throw const _OnMobileData();
      final dir = await downloadsDir();
      final choice = job.choice ??= DownloadPrefs.instance.choice;
      if (choice.format.lossless && !canMakeFlac) throw const _NoFlac();
      if (choice.format == DownloadFormat.mp3 && !canMakeMp3) throw const _NoMp3();
      // Metadata and the stream URL resolve in parallel.
      final (video, audio) = await (_yt.videos.get(job.videoId), _resolveAudio(job.videoId, choice)).wait;
      job.quality = audio.quality;
      // The stream is stored byte-for-byte as YouTube serves it unless a conversion was asked for.
      final audioFile = File(p.join(dir.path, '${job.videoId}.${audio.sourceExt}'));
      partFile = File('${audioFile.path}.part');
      notifyListeners();

      var lastNotified = 0.0;
      var sampleBytes = 0;
      final sampleClock = Stopwatch()..start();
      job
        ..totalBytes = audio.size
        ..receivedBytes = 0
        ..bytesPerSecond = null;
      final thumbnail = _saveCover(video, job, p.join(dir.path, '${job.videoId}.jpg'));
      // YouTube Music already named the song; only a bare video title needs guessing.
      final names = job.knownNames ? (title: job.title, artist: job.channel) : parseTitle(video.title, video.author);
      // Looked up while the audio downloads, so the song has its lyrics offline too.
      final lyrics = _lyricsOf(job.videoId, names, video.duration);
      final albumYear = job.album == null ? Future<int?>.value() : _albumYearOf(job.album!, names.artist);
      try {
        await rangedDownload(
          url: audio.url,
          out: partFile,
          totalBytes: audio.size,
          isCancelled: () => job.status == DownloadStatus.cancelled,
          onProgress: (received, total) {
            job
              ..progress = received / total
              ..totalBytes = total
              ..receivedBytes = received;
            // Exponential moving average over ~250 ms windows keeps the speed readout steady.
            final elapsed = sampleClock.elapsedMicroseconds;
            if (elapsed >= 250000) {
              final rate = (received - sampleBytes) / (elapsed / 1e6);
              job.bytesPerSecond = job.bytesPerSecond == null ? rate : job.bytesPerSecond! * 0.6 + rate * 0.4;
              sampleBytes = received;
              sampleClock.reset();
            }
            if (job.progress - lastNotified >= 0.01) {
              lastNotified = job.progress;
              notifyListeners();
            }
          },
        );
      } catch (_) {
        // A stale cached URL is the usual cause; resolve fresh next time.
        YoutubeStream.invalidateEverywhere(job.videoId);
        rethrow;
      }
      downloaded = await partFile.rename(audioFile.path);
      var saved = audioFile;
      // Only a real conversion says "Converting…"; remuxing and tagging are "Finishing…". No progress either way.
      job.phase = DownloadPhase.afterDownload(audio.convert);
      notifyListeners();
      bool cancelled() => job.status == DownloadStatus.cancelled;
      switch (audio.convert) {
        case Reencode(:final kbps):
          saved = await _reencode(audioFile, opus: audio.sourceExt == 'webm', kbps: kbps);
        case ToFlac(:final quality):
          saved = await toFlac(
            audioFile,
            File(p.join(dir.path, '${job.videoId}.flac')),
            quality,
            isCancelled: cancelled,
          );
        case ToMp3(:final kbps):
          saved = await toMp3(audioFile, File(p.join(dir.path, '${job.videoId}.mp3')), kbps);
        case null:
          if (audio.sourceExt == 'webm') saved = await remuxOpus(audioFile);
      }
      converted = saved;
      if (cancelled()) throw const _Cancelled();
      job.phase = DownloadPhase.finishing;
      notifyListeners();
      final cover = await thumbnail;
      // A song on an album is dated by the album; the upload's year is only for songs without one.
      final year = job.album == null ? video.uploadDate?.year : await albumYear;
      await _tagFile(
        saved,
        TagEdit(title: names.title, artist: names.artist, album: job.album, year: year)
          ..comment = video.url
          ..cover = cover?.bytes
          ..coverMime = cover?.mime ?? 'image/jpeg',
      );
      if (cancelled()) throw const _Cancelled();
      job.totalBytes = saved.lengthSync();
      await _saveLyrics(await lyrics, saved.path);
      final track = Track(
        id: Uri.file(saved.path).toString(),
        uri: Uri.file(saved.path),
        title: names.title,
        artist: names.artist,
        album: job.album,
        duration: video.duration,
        addedAt: DateTime.now().millisecondsSinceEpoch,
        tagged: true,
        sourceUrl: video.url,
      );
      job
        ..track = track
        ..progress = 1
        ..status = DownloadStatus.done;
      await onTrackReady(track);
    } catch (e) {
      if (partFile != null && partFile.existsSync()) partFile.deleteSync();
      // Nothing half-made stays: the stream file and a finished FLAC of a job that didn't complete go too.
      if (job.track == null) {
        for (final f in [downloaded, converted]) {
          if (f != null && f.existsSync()) f.deleteSync();
        }
      }
      if (job.status != DownloadStatus.cancelled) {
        job
          ..status = DownloadStatus.failed
          ..error = _friendlyError(e);
      }
    } finally {
      job.phase = DownloadPhase.downloading;
      notifyListeners();
    }
  }

  /// The year of [album] by [artist], or null when it can't be found in time.
  Future<int?> _albumYearOf(String album, String artist) async {
    try {
      final lookup = albumYearLookup ?? (_web ??= YtMusicWeb.anonymous()).albumYearFor;
      return await lookup(album, artist).timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('Download: no album year: $e');
      return null;
    }
  }

  /// YouTube has no lossless audio; the best it serves is Opus (~130–160 kbps)
  /// or AAC (128 kbps). Take the highest-bitrate stream, preferring Opus on
  /// ties; [aacOnly] for TVs and speakers, which mostly can't decode Opus.
  static AudioOnlyStreamInfo? pickBestAudio(Iterable<AudioOnlyStreamInfo> streams, {bool aacOnly = false}) {
    final candidates = streams
        .where((s) => !aacOnly || s.container == StreamContainer.mp4)
        .where((s) => !_isDrcOrDubbed(s))
        .toList();
    if (candidates.isEmpty) return aacOnly ? null : streams.firstOrNull;
    // Opus is more efficient than AAC, so near-equal bitrates go to Opus.
    int score(AudioOnlyStreamInfo s) => s.bitrate.bitsPerSecond + (_isOpus(s) ? 16000 : 0);
    candidates.sort((a, b) => score(b).compareTo(score(a)));
    return candidates.first;
  }

  static bool _isOpus(AudioOnlyStreamInfo s) => s.audioCodec.toLowerCase().contains('opus');

  /// Skip "stable volume" (DRC) and non-original dubbed tracks: they're processed or not the original mix.
  static bool _isDrcOrDubbed(AudioOnlyStreamInfo s) {
    final xtags = Uri.decodeComponent(s.url.queryParameters['xtags'] ?? '');
    final track = s.audioTrack;
    return xtags.contains('drc=1') || (track != null && !track.audioIsDefault);
  }

  static String describe(AudioOnlyStreamInfo s) =>
      '${_isOpus(s) ? 'Opus' : 'AAC'} · ${s.bitrate.kiloBitsPerSecond.round()} kbps';

  /// The song's lyrics as LRC text (word times kept), null when there are none or they couldn't be found in time.
  static Future<String?> _lyricsOf(String videoId, ({String title, String artist}) names, Duration? length) async {
    try {
      final song = Track.youtube(videoId: videoId, title: names.title, artist: names.artist, duration: length);
      final found = await LyricsService.forTrack(song).timeout(const Duration(seconds: 30));
      return found.toLrc();
    } catch (e) {
      debugPrint('Download: no lyrics saved: $e');
      return null;
    }
  }

  /// Writes [lrc] next to the song (`song.lrc` beside `song.m4a`), where a file's own lyrics are read from.
  static Future<void> _saveLyrics(String? lrc, String audioPath) async {
    if (lrc == null || lrc.trim().isEmpty) return;
    try {
      final file = File(p.setExtension(audioPath, '.lrc'));
      final part = File('${file.path}.part');
      await part.writeAsString(lrc);
      await part.rename(file.path);
    } catch (e) {
      debugPrint('Download: couldn\'t save lyrics: $e');
    }
  }

  /// Tags a finished download. A file that can't be tagged is kept as it is: tags are never worth the song.
  static Future<void> _tagFile(File file, TagEdit edit) async {
    try {
      await Metadata.tagFile(file.path, edit);
    } catch (e) {
      debugPrint('Download: couldn\'t tag ${file.path}: $e');
    }
  }

  /// Googleusercontent / ggpht art can be asked for at any size and shape: ask for a big square.
  static String _squareArt(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.host.endsWith('googleusercontent.com') || uri.host.endsWith('ggpht.com'))) return url;
    final base = url.split('?').first;
    return RegExp(r'=[wsh]\d').hasMatch(base) ? base.replaceFirst(RegExp(r'=[^=/]*$'), '=w1000-h1000-l90-rj') : url;
  }

  /// The song's cover as a centred square, saved to [path] (also what [Metadata] finds next to the song) and returned
  /// for the file's tags. YouTube Music's own square art when the song has it, else the video's thumbnail cropped.
  static Future<({Uint8List bytes, String mime})?> _saveCover(Video video, DownloadJob job, String path) async {
    final urls = <String>{
      if (job.thumbnailUrl.isNotEmpty) _squareArt(job.thumbnailUrl),
      video.thumbnails.maxResUrl,
      video.thumbnails.highResUrl,
      job.thumbnailUrl,
    };
    for (final url in urls) {
      try {
        final res = await http.get(Uri.parse(url));
        if (res.statusCode != 200 || res.bodyBytes.isEmpty) continue;
        final jpeg = await CoverArt.squareJpeg(res.bodyBytes);
        await File(path).writeAsBytes(jpeg);
        return (bytes: jpeg, mime: 'image/jpeg');
      } catch (e) {
        debugPrint('Download: cover from $url failed: $e');
      }
    }
    return null;
  }

  /// What the downloads list says, in plain words (yt-dlp's own errors only go to the log).
  static String _friendlyError(Object e) {
    debugPrint('Download failed: $e');
    return switch (e) {
      // Subclass first: VideoUnavailableException extends VideoUnplayableException.
      VideoUnavailableException() => 'This video is unavailable.',
      VideoUnplayableException() => 'This video can\'t be played (private, age-restricted or region-locked).',
      _NoMp3() => 'MP3 downloads need ffmpeg, which isn\'t available here. Pick another format in Settings.',
      _NoFlac() => 'FLAC downloads aren\'t available on this device. Pick another format in Settings.',
      _OnMobileData() => 'Mobile data downloads are off. Connect to Wi-Fi, or allow them in Settings.',
      SocketException() || http.ClientException() || TimeoutException() => 'No internet connection. Try again.',
      _ => 'Couldn\'t download this song. Try again later.',
    };
  }

  static final _noise = RegExp(
    r'\s*[\(\[]\s*(official\s*|oficial\s*|officiel(le)?\s*)?'
    r'(music\s*|lyrics?\s*|letra\s*|audio\s*|áudio\s*|hd\s*|hq\s*|4k\s*|m/?v\s*|visuali[sz]er\s*|video\s*|vídeo\s*|clip\s*)+'
    r'(oficial\s*|officiel(le)?\s*)?[\)\]]',
    caseSensitive: false,
  );
  static final _channelSuffix = RegExp(r'(\s*-\s*Topic|VEVO|\s*Official)$', caseSensitive: false);

  /// Turns "Artist - Song (Official Video)" into title/artist; falls back to the channel name.
  /// Also handles the reversed "Song - Artist" order when the channel names the artist.
  static ({String title, String artist}) parseTitle(String rawTitle, String channel) {
    var title = rawTitle.replaceAll(_noise, '').trim();
    final channelName = channel.replaceAll(_channelSuffix, '').trim();
    // "Artist | Song" when the left side is the channel's own name; otherwise
    // what follows a "|" is the channel's tagline ("Song | Official Audio").
    final pipe = RegExp(r'\s*\|\s*').firstMatch(title);
    if (pipe != null) {
      final left = title.substring(0, pipe.start).trim();
      final right = title.substring(pipe.end).replaceFirst(RegExp(r'\s*\|.*$'), '').trim();
      final c = channelName.toLowerCase(), l = left.toLowerCase();
      if (left.isNotEmpty && right.isNotEmpty && c.isNotEmpty && (c.contains(l) || l.contains(c))) {
        return (title: right, artist: left);
      }
      title = left;
    }
    final dash = RegExp(r'\s+[-–—]\s+').firstMatch(title);
    if (dash != null) {
      final left = title.substring(0, dash.start).trim();
      final right = title.substring(dash.end).trim();
      if (left.isNotEmpty && right.isNotEmpty) {
        bool names(String side) => channelName.isNotEmpty && side.toLowerCase().contains(channelName.toLowerCase());
        if (names(right) && !names(left)) return (title: left, artist: right);
        return (title: right, artist: left);
      }
    }
    return (title: title.isEmpty ? rawTitle : title, artist: channelName.isEmpty ? channel : channelName);
  }

  /// iOS moves the app container on updates, so re-point downloaded tracks at
  /// the current downloads folder when their stored path has gone stale.
  static Future<Track> relocate(Track track) async {
    final path = track.path;
    if (track.sourceUrl == null || path == null || File(path).existsSync()) return track;
    final moved = File(p.join((await downloadsDir()).path, p.basename(path)));
    return moved.existsSync() ? track.copyWith(uri: Uri.file(moved.path)) : track;
  }

  @override
  void dispose() {
    // Closing the app is not cancelling: what was waiting or running is kept for the next start.
    _saveTimer?.cancel();
    final text = encodeQueue(_jobs);
    if (!_frozen && text != _saved && _queueFile != null) {
      try {
        PrivateFiles.writeSync(_queueFile!, text);
      } catch (_) {}
    }
    _frozen = true;
    _web?.close();
    for (final j in _jobs.where((j) => j.isActive)) {
      j.status = DownloadStatus.cancelled;
    }
    _yt.close();
    super.dispose();
  }
}

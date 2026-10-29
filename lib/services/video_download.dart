import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'download_prefs.dart';
import 'ffmpeg.dart';
import 'mp4_mux.dart';
import 'webm_mux.dart';

/// The picture codec of a video stream.
enum VideoCodec {
  avc,
  vp9,
  av1,
  other;

  /// From a codec string: `avc1.640028`, `vp09.00.40.08`, `vp9`, `av01.0.12M.08`.
  static VideoCodec of(String codec) {
    final c = codec.toLowerCase();
    if (c.startsWith('avc') || c.startsWith('h264')) return avc;
    if (c.startsWith('vp09') || c.startsWith('vp9')) return vp9;
    if (c.startsWith('av01') || c.startsWith('av1')) return av1;
    return other;
  }
}

/// One video stream a video offers, whichever service listed it. [progressive] streams carry their own sound
/// (YouTube's old single-file 360p MP4); the others are picture only.
class VideoCandidate {
  const VideoCandidate({
    required this.id,
    required this.height,
    required this.codec,
    this.fps = 30,
    this.kbps = 0,
    this.sizeBytes,
    this.lengthMs,
    this.webm = false,
    this.progressive = false,
    this.ref,
  });

  final String id;
  final int height;
  final VideoCodec codec;
  final int fps;
  final int kbps;

  /// The stream's exact size when the lister says it.
  final int? sizeBytes;

  /// How long the stream runs, when the lister says (player API `approxDurationMs`); with [kbps] it gives a size
  /// when [sizeBytes] is missing.
  final int? lengthMs;

  /// The stream is a WebM file (VP9); otherwise an MP4 (H.264, and YouTube's AV1).
  final bool webm;
  final bool progressive;

  /// Whatever the lister wants back for the stream it picked.
  final Object? ref;

  String get ext => webm ? 'webm' : 'mp4';

  /// From one entry of YouTube's player API `adaptiveFormats` (or `formats`, for the progressive ones); null if it
  /// isn't a usable video stream.
  static VideoCandidate? fromPlayer(Map<String, dynamic> f) {
    final mime = f['mimeType'] as String? ?? '';
    final height = (f['height'] as num?)?.toInt();
    if (!mime.startsWith('video/') || f['url'] is! String || height == null || height <= 0) return null;
    final codecs = RegExp(r'codecs="([^"]+)"').firstMatch(mime)?.group(1) ?? '';
    final list = codecs.split(',').map((c) => c.trim()).toList();
    return VideoCandidate(
      id: '${f['itag']}',
      height: height,
      codec: VideoCodec.of(list.first),
      fps: (f['fps'] as num?)?.toInt() ?? 30,
      kbps: (((f['averageBitrate'] ?? f['bitrate']) as num?) ?? 0) ~/ 1000,
      sizeBytes: int.tryParse('${f['contentLength'] ?? ''}'),
      lengthMs: int.tryParse('${f['approxDurationMs'] ?? ''}'),
      webm: mime.startsWith('video/webm'),
      progressive: list.length > 1 || codecs.contains('mp4a'),
      ref: f,
    );
  }

  /// From one entry of `yt-dlp -J`'s `formats`; null if it has no picture, or isn't one plain file.
  static VideoCandidate? fromYtDlp(Map<String, dynamic> f) {
    final vcodec = '${f['vcodec'] ?? 'none'}';
    final height = (f['height'] as num?)?.toInt();
    if (vcodec == 'none' || height == null || height <= 0) return null;
    final protocol = '${f['protocol'] ?? 'https'}';
    if (protocol != 'https' && protocol != 'http') return null;
    final acodec = '${f['acodec'] ?? 'none'}';
    return VideoCandidate(
      id: '${f['format_id']}',
      height: height,
      codec: VideoCodec.of(vcodec),
      fps: (f['fps'] as num?)?.round() ?? 30,
      kbps: ((f['vbr'] ?? f['tbr']) as num?)?.round() ?? 0,
      sizeBytes: ((f['filesize'] ?? f['filesize_approx']) as num?)?.round(),
      webm: f['ext'] == 'webm',
      progressive: acodec != 'none',
      ref: f,
    );
  }
}

/// Everything a video offers: its picture streams and its sound streams.
class VideoFormats {
  const VideoFormats(this.videos, this.audios);

  final List<VideoCandidate> videos;
  final List<AudioCandidate> audios;

  bool get isEmpty => videos.isEmpty;
}

/// One resolution a container can be saved at, with the stream that gives it.
class VideoOption {
  const VideoOption(this.height, this.video);

  final int height;
  final VideoCandidate video;

  /// "1080p", "1080p60", "2160p · AV1 (newer devices)".
  String get label => videoLabel(video);
}

/// "1080p", "1080p60" (above 30 frames a second), and for AV1 "· AV1 (newer devices)".
String videoLabel(VideoCandidate v) =>
    '${v.height}p${v.fps > 30 ? v.fps : ''}${v.codec == VideoCodec.av1 ? ' · AV1 (newer devices)' : ''}';

/// The stream a [VideoContainer] gets for each resolution, tallest first. Plain rules:
///
/// * MP4 is H.264 (plays everywhere), so only as tall as YouTube serves H.264: 1080p. Never VP9 or AV1.
/// * WebM is VP9; a resolution that only has AV1 offers that (marked "newer devices"), but AV1 comes as MP4
///   from YouTube, so putting it in a WebM needs ffmpeg ([ffmpeg]).
/// * Among streams of one resolution: the codec first, then the higher frame rate, then the higher bitrate.
///
/// Empty when the sound needed (AAC for MP4, Opus for WebM) isn't there.
List<VideoOption> videoOptions(VideoFormats f, VideoContainer container, {required bool ffmpeg}) {
  if (bestVideoAudio(f.audios, container) == null) return const [];
  final byHeight = <int, List<VideoCandidate>>{};
  for (final v in f.videos.where((v) => !v.progressive)) {
    byHeight.putIfAbsent(v.height, () => []).add(v);
  }
  int rank(VideoCandidate v) => switch (container) {
    VideoContainer.mp4 => v.codec == VideoCodec.avc ? 2 : -1,
    VideoContainer.webm => v.codec == VideoCodec.vp9 && v.webm ? 2 : (v.codec == VideoCodec.av1 && ffmpeg ? 1 : -1),
  };
  final out = <VideoOption>[];
  for (final e in byHeight.entries) {
    final usable = e.value.where((v) => rank(v) > 0).toList()
      ..sort((a, b) {
        final byCodec = rank(b).compareTo(rank(a));
        if (byCodec != 0) return byCodec;
        final byFps = b.fps.compareTo(a.fps);
        return byFps != 0 ? byFps : b.kbps.compareTo(a.kbps);
      });
    if (usable.isNotEmpty) out.add(VideoOption(e.key, usable.first));
  }
  out.sort((a, b) => b.height.compareTo(a.height));
  return out;
}

/// The size a download is recommended at: the best at or under 1080p, or the smallest there is when
/// everything is taller.
int? recommendedVideoHeightOf(Iterable<int> heights) {
  final list = heights.toList()..sort();
  if (list.isEmpty) return null;
  return list.lastWhere((h) => h <= recommendedVideoHeight, orElse: () => list.first);
}

/// The best sound for [container]: AAC for MP4, Opus for WebM (not the "stable volume" or dubbed variants); an
/// MP4 with no AAC takes Opus.
AudioCandidate? bestVideoAudio(Iterable<AudioCandidate> audios, VideoContainer container) {
  final usable = audios.where((a) => !a.processed).toList()..sort((a, b) => b.kbps.compareTo(a.kbps));
  final wantOpus = container == VideoContainer.webm;
  return usable.where((a) => a.opus == wantOpus).firstOrNull ?? (wantOpus ? null : usable.firstOrNull);
}

/// What [pickVideoDownload] decided.
class VideoPick {
  const VideoPick(this.video, this.audio, this.container);

  final VideoCandidate video;
  final AudioCandidate audio;
  final VideoContainer container;

  /// An AV1 stream saved as WebM is converted from its MP4 by ffmpeg (nothing is re-encoded).
  bool get needsFfmpeg => container == VideoContainer.webm && !video.webm;

  /// e.g. "Video · MP4 · 1080p".
  String get label => 'Video · ${container.label} · ${videoLabel(video)}';
}

/// Chooses the streams for [choice] (a video choice): the resolution asked for, or the tallest one that is at
/// or below it, or the smallest there is when everything is taller; null height is the tallest of all. Null when
/// the container can't be made for this video.
VideoPick? pickVideoDownload(VideoFormats f, DownloadChoice choice, {required bool ffmpeg}) {
  final container = choice.container;
  if (container == null) return null;
  final options = videoOptions(f, container, ffmpeg: ffmpeg);
  final audio = bestVideoAudio(f.audios, container);
  if (options.isEmpty || audio == null) return null;
  final want = choice.height;
  final VideoOption pick;
  if (want == null) {
    pick = options.first;
  } else {
    pick = options.where((o) => o.height <= want).firstOrNull ?? options.last;
  }
  return VideoPick(pick.video, audio, container);
}

/// The single-file stream (picture and sound together) to fall back on when the two can't be combined: the tallest
/// progressive MP4, usually 360p.
VideoCandidate? pickProgressive(VideoFormats f) {
  final list = f.videos.where((v) => v.progressive && !v.webm && v.codec == VideoCodec.avc).toList()
    ..sort((a, b) => b.height.compareTo(a.height));
  return list.firstOrNull;
}

/// What a video download weighs: the picture stream plus the sound stream. [exact] when both sizes are the
/// lister's own; otherwise worked out from the bitrates and the length the known size implies.
({int bytes, bool exact})? estimateVideoDownload(VideoFormats f, DownloadChoice choice, {required bool ffmpeg}) {
  final pick = pickVideoDownload(f, choice, ffmpeg: ffmpeg);
  if (pick == null) return null;
  final v = pick.video, a = pick.audio;
  if (v.sizeBytes != null && a.sizeBytes != null) return (bytes: v.sizeBytes! + a.sizeBytes!, exact: true);
  double? seconds;
  if (a.sizeBytes != null && a.kbps > 0) seconds = a.sizeBytes! * 8 / (a.kbps * 1000);
  if (seconds == null && v.sizeBytes != null && v.kbps > 0) seconds = v.sizeBytes! * 8 / (v.kbps * 1000);
  // No size from either: the length the lister gives (never a request per stream).
  final ms = v.lengthMs ?? a.lengthMs;
  if (seconds == null && ms != null && ms > 0) seconds = ms / 1000;
  if (seconds == null) return null;
  final video = v.sizeBytes ?? (v.kbps > 0 ? (seconds * v.kbps * 1000 / 8).round() : null);
  final audio = a.sizeBytes ?? (a.kbps > 0 ? (seconds * a.kbps * 1000 / 8).round() : null);
  if (video == null || audio == null) return null;
  return (bytes: video + audio, exact: false);
}

/// "4K" for 2160, "8K" for 4320, else "1440p".
String tallName(int height) => switch (height) {
  >= 4320 => '8K',
  >= 2160 => '4K',
  _ => '${height}p',
};

/// A plain line for when WebM goes taller than MP4 does ("4K is available as WebM."); null if it doesn't.
String? webmTallerNote(VideoFormats f, {required bool ffmpeg}) {
  final mp4 = videoOptions(f, VideoContainer.mp4, ffmpeg: ffmpeg);
  final webm = videoOptions(f, VideoContainer.webm, ffmpeg: ffmpeg);
  if (webm.isEmpty || mp4.isEmpty || webm.first.height <= mp4.first.height) return null;
  final taller = webm.first.height;
  return '${tallName(taller)} is available as WebM.';
}

/// The sizes the Settings picker offers when no video is at hand: what YouTube serves, and for MP4 up to 1080p.
List<int> standardVideoHeights(VideoContainer c) => switch (c) {
  VideoContainer.mp4 => const [1080, 720, 480, 360, 240, 144],
  VideoContainer.webm => const [2160, 1440, 1080, 720, 480, 360, 240, 144],
};

/// "Best available" or "1080p", for pickers.
String videoHeightLabel(int? height) => height == null ? 'Best available' : '${height}p';

// ---- putting the two streams into one file ----

/// Puts [video] and [audio] (the streams as YouTube serves them) into [out], without re-encoding. The Dart
/// muxers do it everywhere ([Mp4Mux] for MP4, [WebmMux] for WebM); where ffmpeg is installed it is used instead
/// (`-c copy`, `+faststart` for MP4), and also for an AV1 WebM, which only it can write. [out] is written
/// directly, so pass a `.part` path and rename it. Throws when it can't be made.
Future<void> muxVideo({
  required File video,
  required File audio,
  required File out,
  required VideoContainer container,
  MuxTags? tags,
  bool useFfmpeg = false,
}) async {
  if (useFfmpeg) {
    try {
      await _muxWithFfmpeg(video, audio, out, container, tags);
      return;
    } catch (e) {
      debugPrint('Video: ffmpeg couldn\'t combine the streams, trying the built-in muxer: $e');
      if (out.existsSync()) out.deleteSync();
    }
  }
  switch (container) {
    case VideoContainer.mp4:
      await Mp4Mux.muxFile(video: video.path, audio: audio.path, out: out.path, tags: tags);
    case VideoContainer.webm:
      await WebmMux.muxFile(video: video.path, audio: audio.path, out: out.path, tags: tags);
  }
  if (!out.existsSync() || out.lengthSync() == 0) throw const MuxException('the file came out empty');
}

Future<void> _muxWithFfmpeg(File video, File audio, File out, VideoContainer container, MuxTags? tags) async {
  final exe = await Ffmpeg.executable();
  File? cover;
  try {
    final hasCover = tags?.cover != null;
    if (hasCover) {
      cover = File('${out.path}.cover.${tags!.coverMime == 'image/png' ? 'png' : 'jpg'}')
        ..writeAsBytesSync(tags.cover!);
    }
    final mp4 = container == VideoContainer.mp4;
    final meta = <String>[
      for (final (key, value) in [
        ('title', tags?.title),
        ('artist', tags?.artist),
        ('album', tags?.album),
        ('date', tags?.year),
        ('comment', tags?.comment),
      ])
        if (value != null) ...['-metadata', '$key=$value'],
    ];
    final r = await Process.run(exe, [
      '-hide_banner', '-loglevel', 'error', '-y', '-i', video.path, '-i', audio.path, //
      if (hasCover && mp4) ...['-i', cover!.path],
      '-map', '0:v:0', '-map', '1:a:0', if (hasCover && mp4) ...['-map', '2:v:0'],
      '-c', 'copy', '-map_metadata', '-1', ...meta,
      if (hasCover && mp4) ...['-disposition:v:1', 'attached_pic'],
      if (hasCover && !mp4) ...[
        '-attach', cover!.path, //
        '-metadata:s:t:0', 'mimetype=${tags!.coverMime}',
        '-metadata:s:t:0', 'filename=cover.${tags.coverMime == 'image/png' ? 'png' : 'jpg'}',
      ],
      if (mp4) ...['-movflags', '+faststart'],
      '-f', mp4 ? 'mp4' : 'webm', out.path,
    ]);
    if (r.exitCode != 0 || !out.existsSync() || out.lengthSync() == 0) {
      throw MuxException('ffmpeg: ${(r.stderr as String).trim()}');
    }
  } finally {
    if (cover != null && cover.existsSync()) cover.deleteSync();
  }
}

/// Whether the file at [path] is a downloaded music video: an MP4, or a WebM with a picture track (YouTube's
/// audio-only downloads are `.opus`, `.m4a`, `.flac` or `.mp3`, but an Opus whose remux failed stays a `.webm`).
bool isVideoFile(String path) {
  final ext = p.extension(path).toLowerCase();
  if (ext == '.mp4') return true;
  if (ext != '.webm') return false;
  if (!File(path).existsSync()) return false;
  return _webmHasVideo.putIfAbsent(path, () => WebmMux.hasVideoTrack(path));
}

final _webmHasVideo = <String, bool>{};

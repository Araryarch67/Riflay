import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' show AudioOnlyStreamInfo;

/// The file type a download is saved as.
enum DownloadFormat {
  opus('Opus', 'Smallest files for the same sound. Plays in Riflay and most players.'),
  m4a('M4A (AAC)', 'The most widely supported. Plays on nearly every phone, TV and speaker.'),
  flac(
    'FLAC',
    'Lossless file for players and libraries that want FLAC. YouTube\'s sound is kept exactly; it gets no better.',
  ),
  mp3(
    'MP3',
    'For older players and car stereos. Made from YouTube\'s audio, so it never sounds better than Opus or M4A.',
  );

  const DownloadFormat(this.label, this.about);
  final String label;
  final String about;

  /// FLAC is made from the downloaded stream; the others are YouTube's own.
  bool get lossless => this == flac;

  /// FLAC and MP3 are always made from the downloaded stream; Opus and M4A are YouTube's own unless a lower
  /// bitrate is asked for.
  bool get alwaysConverted => this == flac || this == mp3;

  /// The bitrates offered for this format, best first; null is "Best available" (for MP3: [mp3BestKbps]).
  /// Empty for FLAC, which has [FlacQuality] instead.
  List<int?> get bitrates => switch (this) {
    flac => const [],
    mp3 => const [null, 160, 128, 96],
    _ => const [null, 128, 96, 64, 48],
  };
}

/// Whether a download is the song's sound alone or its music video too.
enum DownloadKind {
  audio('Audio'),
  video('Video');

  const DownloadKind(this.label);
  final String label;
}

/// The file a music video is saved as.
enum VideoContainer {
  mp4('MP4', 'H.264 picture and AAC sound. Plays on nearly every phone, TV and computer.'),
  webm('WebM', 'VP9 picture and Opus sound. Smaller files, and the tallest sizes; plays in Riflay and most computers.');

  const VideoContainer(this.label, this.about);
  final String label;
  final String about;
}

/// The size a music video is recommended at (and the default): 1080p, or the best the video has below that.
const recommendedVideoHeight = 1080;

/// What "Best available" means for MP3: enough to keep everything YouTube's ~130-160 kbps Opus or AAC carries.
const mp3BestKbps = 192;

/// Bit depth and sample rate of a FLAC download.
enum FlacQuality {
  standard('16-bit / 48 kHz', 16, 48000, 'Same sample rate as YouTube\'s audio. Plays everywhere.'),
  cd('16-bit / 44.1 kHz', 16, 44100, 'CD quality, for players and burners that want exactly that.'),
  hiRes('24-bit / 48 kHz', 24, 48000, 'Larger files, for libraries kept at 24-bit.');

  const FlacQuality(this.label, this.bits, this.rate, this.about);
  final String label;
  final int bits;
  final int rate;
  final String about;
}

/// "Best available" or "128 kbps", for pickers.
String bitrateLabel(int? kbps) => kbps == null ? 'Best available' : '$kbps kbps';

/// What a bitrate chip or picker entry says: "128 kbps", and for the best, "Best available" (MP3: "192 kbps (best)").
String bitrateLabelFor(DownloadFormat f, int? kbps) =>
    f == DownloadFormat.mp3 && kbps == null ? '$mp3BestKbps kbps (best)' : bitrateLabel(kbps);

/// A format and quality for one download.
class DownloadChoice {
  const DownloadChoice(this.format, {this.kbps, this.flac = FlacQuality.standard}) : container = null, height = null;

  /// A music video in [container] at [height] pixels tall (null: the tallest, at the highest frame rate, there is).
  const DownloadChoice.video(VideoContainer this.container, {this.height = recommendedVideoHeight})
    : format = DownloadFormat.opus,
      kbps = null,
      flac = FlacQuality.standard;

  /// Set for a video download; the audio fields below then mean nothing.
  final VideoContainer? container;
  final int? height;

  bool get isVideo => container != null;

  DownloadKind get kind => isVideo ? DownloadKind.video : DownloadKind.audio;

  final DownloadFormat format;

  /// Target bitrate for Opus and M4A; null for the best YouTube has. Ignored for FLAC.
  final int? kbps;

  /// Bit depth and sample rate for FLAC; ignored for the other formats.
  final FlacQuality flac;

  @override
  bool operator ==(Object other) =>
      other is DownloadChoice &&
      other.container == container &&
      (isVideo
          ? other.height == height
          : other.format == format && (format.lossless ? other.flac == flac : other.kbps == kbps));

  @override
  int get hashCode => isVideo ? Object.hash(container, height) : Object.hash(format, format.lossless ? flac : kbps);

  @override
  String toString() => isVideo
      ? 'video/${container!.name}/${height ?? 'best'}'
      : '${format.name}/${format.lossless ? flac.name : (kbps ?? 'best')}';
}

/// One audio-only stream a video offers, whichever service listed it.
class AudioCandidate {
  const AudioCandidate({
    required this.id,
    required this.opus,
    required this.kbps,
    this.processed = false,
    this.sizeBytes,
    this.ref,
  });

  final String id;
  final bool opus;
  final int kbps;

  /// The stream's exact size when the lister says it (player API `contentLength`, yt-dlp `filesize`).
  final int? sizeBytes;

  /// "Stable volume" (DRC) or a dubbed track: not the original mix.
  final bool processed;

  /// Whatever the lister wants back for the stream it picked.
  final Object? ref;

  /// From one entry of YouTube's player API `adaptiveFormats`; null if it isn't a usable audio stream.
  static AudioCandidate? fromPlayer(Map<String, dynamic> f) {
    final mime = f['mimeType'] as String? ?? '';
    if (!mime.startsWith('audio/') || f['url'] is! String) return null;
    final track = f['audioTrack'] as Map<String, dynamic>?;
    return AudioCandidate(
      id: '${f['itag']}',
      opus: mime.contains('opus'),
      kbps: (((f['averageBitrate'] ?? f['bitrate']) as num?) ?? 0) ~/ 1000,
      sizeBytes: int.tryParse('${f['contentLength'] ?? ''}'),
      processed:
          f['isDrc'] == true || (f['xtags'] as String? ?? '').contains('drc') || track?['audioIsDefault'] == false,
      ref: f,
    );
  }

  /// From one entry of `yt-dlp -J`'s `formats`; null if it carries video or no audio.
  static AudioCandidate? fromYtDlp(Map<String, dynamic> f) {
    final codec = '${f['acodec'] ?? 'none'}';
    if (codec == 'none' || (f['vcodec'] != null && f['vcodec'] != 'none')) return null;
    final id = '${f['format_id']}';
    final lang = f['language_preference'];
    return AudioCandidate(
      id: id,
      opus: codec.startsWith('opus'),
      kbps: ((f['abr'] ?? f['tbr']) as num?)?.round() ?? 0,
      sizeBytes: ((f['filesize'] ?? f['filesize_approx']) as num?)?.round(),
      processed: id.contains('drc') || (lang is num && lang < 0),
      ref: f,
    );
  }

  static AudioCandidate fromExplode(AudioOnlyStreamInfo s, {required bool processed}) => AudioCandidate(
    id: '${s.tag}',
    opus: s.audioCodec.toLowerCase().contains('opus'),
    kbps: s.bitrate.kiloBitsPerSecond.round(),
    sizeBytes: s.size.totalBytes,
    processed: processed,
    ref: s,
  );
}

/// What a downloaded stream is turned into after it arrives.
sealed class Conversion {
  const Conversion();
}

/// The same codec at a lower bitrate (needs ffmpeg).
class Reencode extends Conversion {
  const Reencode(this.kbps);
  final int kbps;

  @override
  bool operator ==(Object other) => other is Reencode && other.kbps == kbps;
  @override
  int get hashCode => kbps.hashCode;
}

/// Decoded and saved as FLAC (ffmpeg, or libmpv plus FlacStream where there is no ffmpeg).
class ToFlac extends Conversion {
  const ToFlac(this.quality);
  final FlacQuality quality;

  @override
  bool operator ==(Object other) => other is ToFlac && other.quality == quality;
  @override
  int get hashCode => quality.hashCode;
}

/// Encoded to MP3 at [kbps] (needs ffmpeg).
class ToMp3 extends Conversion {
  const ToMp3(this.kbps);
  final int kbps;

  @override
  bool operator ==(Object other) => other is ToMp3 && other.kbps == kbps;
  @override
  int get hashCode => kbps.hashCode;
}

/// What [pickForDownload] decided.
class AudioPick {
  const AudioPick(this.candidate, {this.convert});

  final AudioCandidate candidate;

  /// Null keeps the stream byte-for-byte as YouTube serves it.
  final Conversion? convert;

  /// Set when the stream is converted down to a lower bitrate. Never above the stream's own.
  int? get reencodeKbps => switch (convert) {
    Reencode(:final kbps) => kbps,
    _ => null,
  };

  /// The bitrate of the saved file (for FLAC: the stream it was made from).
  int get kbps => reencodeKbps ?? candidate.kbps;

  bool get opus => candidate.opus;

  /// The saved file's extension.
  String get ext => switch (convert) {
    ToFlac() => 'flac',
    ToMp3() => 'mp3',
    _ => opus ? 'webm' : 'm4a',
  };

  /// e.g. "Opus · 138 kbps" or "FLAC · 16-bit / 48 kHz", for the downloads list.
  String get label => switch (convert) {
    ToFlac(:final quality) => describeFlac(quality, fromOpus: opus, fromKbps: candidate.kbps),
    ToMp3(:final kbps) => 'MP3 · $kbps kbps',
    _ => describeAudio(opus: opus, kbps: kbps),
  };
}

String describeAudio({required bool opus, required int? kbps}) =>
    '${opus ? 'Opus' : 'AAC'}${kbps == null || kbps <= 0 ? '' : ' · $kbps kbps'}';

/// e.g. "FLAC · 16-bit / 48 kHz · from Opus 137 kbps": the stream it was made from says how good it really is.
String describeFlac(FlacQuality q, {bool? fromOpus, int? fromKbps}) {
  final from = fromOpus == null
      ? ''
      : ' · from ${fromOpus ? 'Opus' : 'AAC'}${fromKbps == null || fromKbps <= 0 ? '' : ' $fromKbps kbps'}';
  return 'FLAC · ${q.label}$from';
}

/// Roughly how big a FLAC of [length] at [q] comes out. [compressed] is ffmpeg's FLAC (a decoded lossy
/// stream packs to a bit over half its raw size); without it [FlacStream] stores the samples as they are.
int estimateFlacBytes(Duration length, FlacQuality q, {required bool compressed}) {
  final raw = length.inMilliseconds / 1000 * q.rate * 2 * q.bits / 8;
  return (compressed ? raw * 0.6 : raw).round();
}

/// The choice offered first, and tagged "Recommended": Opus at the best YouTube has (smallest file for the same sound).
bool isRecommended(DownloadChoice c) => !c.isVideo && c.format == DownloadFormat.opus && c.kbps == null;

/// The choice a picker preselects: the saved one, or the recommended one if the person never chose.
const recommendedChoice = DownloadChoice(DownloadFormat.opus);

/// The video choice a picker preselects when the person never chose one: MP4 at 1080p.
const recommendedVideoChoice = DownloadChoice.video(VideoContainer.mp4);

/// Roughly how many bytes a download of [c] comes out at, from what the video offers; null when that isn't known.
/// The stream's exact size when it is kept as it is; otherwise its length (size / bitrate) times the target bitrate,
/// and for FLAC [estimateFlacBytes].
int? estimateDownloadBytes(Iterable<AudioCandidate> all, DownloadChoice c, {required bool canReencode}) {
  final pick = pickForDownload(all, c, canReencode: canReencode);
  if (pick == null) return null;
  final stream = pick.candidate;
  final convert = pick.convert;
  if (convert == null) return stream.sizeBytes;
  final size = stream.sizeBytes;
  if (size == null || size <= 0 || stream.kbps <= 0) return null;
  final seconds = size * 8 / (stream.kbps * 1000);
  return switch (convert) {
    Reencode(:final kbps) || ToMp3(:final kbps) => (seconds * kbps * 1000 / 8).round(),
    ToFlac(:final quality) => estimateFlacBytes(
      Duration(milliseconds: (seconds * 1000).round()),
      quality,
      compressed: canReencode,
    ),
  };
}

/// "Downloading in MP3 · 192 kbps…", for the long-press download.
String describeChoice(DownloadChoice c) => c.isVideo
    ? 'Video · ${c.container!.label} · ${c.height == null ? 'best available' : '${c.height}p'}'
    : _describeAudioChoice(c);

String _describeAudioChoice(DownloadChoice c) => switch (c.format) {
  DownloadFormat.flac => 'FLAC · ${c.flac.label}',
  DownloadFormat.mp3 => 'MP3 · ${c.kbps ?? mp3BestKbps} kbps',
  _ => '${c.format == DownloadFormat.opus ? 'Opus' : 'M4A'} · ${c.kbps == null ? 'best available' : '${c.kbps} kbps'}',
};

/// Below this, a stream is taken for a broken one when the other format has a real one.
const _brokenKbps = 32;

/// A served stream this close to the bitrate asked for (either way) is used as it is.
const _closeEnough = 0.15;

/// Chooses the stream for [choice] out of everything a video offers.
///
/// * The format asked for wins; the other one only if the video has none.
///   FLAC is made from the best stream, Opus first.
/// * "Best available", or a bitrate at or near the best stream's, is the
///   highest-bitrate stream. Nothing is ever converted up.
/// * A lower bitrate takes YouTube's own stream when one is within 15% of it;
///   otherwise the best stream is converted down to it (if [canReencode], i.e.
///   ffmpeg is there). Without ffmpeg the highest stream at or under it is
///   used as it is, or the smallest one.
AudioPick? pickForDownload(Iterable<AudioCandidate> all, DownloadChoice choice, {required bool canReencode}) {
  final usable = all.where((c) => !c.processed).toList();
  if (usable.isEmpty) return null;
  final wantOpus = choice.format != DownloadFormat.m4a;
  var pool = usable.where((c) => c.opus == wantOpus).toList();
  if (pool.isEmpty) pool = usable;
  pool.sort((a, b) => b.kbps.compareTo(a.kbps));
  // Some uploads carry a near-silent Opus beside a normal AAC. A 4 kbps file is
  // not what anyone asking for the best wants: take the other format then.
  final other = usable.where((c) => c.opus != pool.first.opus).toList()..sort((a, b) => b.kbps.compareTo(a.kbps));
  if (pool.first.kbps < _brokenKbps && other.isNotEmpty && other.first.kbps >= 96) pool = other;
  final best = pool.first;
  if (choice.format.lossless) return AudioPick(best, convert: ToFlac(choice.flac));
  if (choice.format == DownloadFormat.mp3) return AudioPick(best, convert: ToMp3(choice.kbps ?? mp3BestKbps));
  final target = choice.kbps;
  if (target == null || target >= best.kbps * (1 - _closeEnough)) return AudioPick(best);
  AudioCandidate? near;
  for (final c in pool) {
    if ((c.kbps - target).abs() <= target * _closeEnough &&
        (near == null || (c.kbps - target).abs() < (near.kbps - target).abs())) {
      near = c;
    }
  }
  if (near != null) return AudioPick(near);
  if (canReencode) return AudioPick(best, convert: Reencode(target));
  for (final c in pool) {
    if (c.kbps <= target) return AudioPick(c);
  }
  return AudioPick(pool.last);
}

/// What the user set under Settings › Library & downloads › Downloads.
class DownloadPrefs extends ChangeNotifier {
  DownloadPrefs();

  static final instance = DownloadPrefs();

  DownloadFormat format = DownloadFormat.opus;

  /// Audio (the default) or the music video.
  DownloadKind kind = DownloadKind.audio;
  VideoContainer videoContainer = VideoContainer.mp4;

  /// The size set per container; a missing entry is the recommended 1080p, 0 is "Best available".
  final Map<VideoContainer, int> _height = {};

  /// Target bitrate per lossy format; a missing entry is "Best available".
  final Map<DownloadFormat, int> _kbps = {};
  FlacQuality flac = FlacQuality.standard;
  bool askEveryTime = false;

  /// A folder the user chose (computers); null keeps the default.
  String? folder;

  /// Phones: download on mobile data too.
  bool mobileData = true;

  /// The bitrate set for [f]; null for "Best available".
  int? kbpsFor(DownloadFormat f) => _kbps[f];

  /// The height set for [c]: null is "Best available".
  int? heightFor(VideoContainer c) => switch (_height[c]) {
    null => recommendedVideoHeight,
    0 => null,
    final h => h,
  };

  /// The audio choice, whatever [kind] is (what a song without a music video is saved as).
  DownloadChoice get audioChoice => DownloadChoice(format, kbps: kbpsFor(format), flac: flac);

  DownloadChoice get videoChoice => DownloadChoice.video(videoContainer, height: heightFor(videoContainer));

  /// What a download follows: the video choice when Video is picked, else the audio one.
  DownloadChoice get choice => kind == DownloadKind.video ? videoChoice : audioChoice;

  Future<void>? _loaded;

  Future<void> load() => _loaded ??= () async {
    final prefs = await SharedPreferences.getInstance();
    format = DownloadFormat.values.asNameMap()[prefs.getString('downloads.format')] ?? format;
    // Before bitrates: one "quality" step for both formats.
    final legacy = switch (prefs.getString('downloads.quality')) {
      'smaller' => 96,
      'smallest' => 64,
      _ => null,
    };
    for (final f in DownloadFormat.values.where((f) => !f.lossless)) {
      final kbps = prefs.getInt('downloads.kbps.${f.name}') ?? legacy;
      if (kbps != null && f.bitrates.contains(kbps)) _kbps[f] = kbps;
    }
    kind = DownloadKind.values.asNameMap()[prefs.getString('downloads.kind')] ?? kind;
    videoContainer = VideoContainer.values.asNameMap()[prefs.getString('downloads.video.container')] ?? videoContainer;
    for (final c in VideoContainer.values) {
      final h = prefs.getInt('downloads.video.height.${c.name}');
      if (h != null && h >= 0) _height[c] = h;
    }
    flac = FlacQuality.values.asNameMap()[prefs.getString('downloads.flac')] ?? flac;
    askEveryTime = prefs.getBool('downloads.ask') ?? askEveryTime;
    folder = prefs.getString('downloads.folder');
    mobileData = prefs.getBool('downloads.mobileData') ?? mobileData;
    notifyListeners();
  }();

  Future<void> _save(String key, Object? value) async {
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    switch (value) {
      case null:
        await prefs.remove(key);
      case final bool b:
        await prefs.setBool(key, b);
      case final int i:
        await prefs.setInt(key, i);
      case final String s:
        await prefs.setString(key, s);
    }
  }

  Future<void> setKind(DownloadKind v) {
    kind = v;
    return _save('downloads.kind', v.name);
  }

  Future<void> setVideoContainer(VideoContainer v) {
    videoContainer = v;
    return _save('downloads.video.container', v.name);
  }

  /// [height] null is "Best available".
  Future<void> setVideoHeight(VideoContainer c, int? height) {
    _height[c] = height ?? 0;
    return _save('downloads.video.height.${c.name}', height ?? 0);
  }

  Future<void> setFormat(DownloadFormat v) {
    format = v;
    return _save('downloads.format', v.name);
  }

  /// [kbps] null is "Best available". Not for FLAC.
  Future<void> setKbps(DownloadFormat f, int? kbps) {
    assert(!f.lossless && f.bitrates.contains(kbps));
    if (kbps == null) {
      _kbps.remove(f);
    } else {
      _kbps[f] = kbps;
    }
    return _save('downloads.kbps.${f.name}', kbps);
  }

  Future<void> setFlac(FlacQuality v) {
    flac = v;
    return _save('downloads.flac', v.name);
  }

  Future<void> setAskEveryTime(bool v) {
    askEveryTime = v;
    return _save('downloads.ask', v);
  }

  Future<void> setFolder(String? v) {
    folder = v;
    return _save('downloads.folder', v);
  }

  Future<void> setMobileData(bool v) {
    mobileData = v;
    return _save('downloads.mobileData', v);
  }
}

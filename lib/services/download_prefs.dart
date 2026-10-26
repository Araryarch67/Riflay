import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' show AudioOnlyStreamInfo;

/// The file type a download is saved as.
enum DownloadFormat {
  opus('Opus', 'Smallest files for the same sound. Plays in Riflay and most players.'),
  m4a('M4A (AAC)', 'The most widely supported. Plays on nearly every phone, TV and speaker.');

  const DownloadFormat(this.label, this.about);
  final String label;
  final String about;
}

/// How much quality a download keeps. YouTube serves one best stream per
/// format and a few smaller ones; these steps never go above what it serves.
enum DownloadQuality {
  best('Best available', null, 'The best sound YouTube has for the song.'),
  smaller('Smaller files', 96, 'Up to about 96 kbps. Saves space, sounds a little less full.'),
  smallest('Smallest files', 64, 'Up to about 64 kbps. Saves the most space.');

  const DownloadQuality(this.label, this.capKbps, this.about);
  final String label;

  /// The highest bitrate this step allows; null for no limit.
  final int? capKbps;
  final String about;
}

/// A format and quality for one download.
class DownloadChoice {
  const DownloadChoice(this.format, this.quality);

  final DownloadFormat format;
  final DownloadQuality quality;

  @override
  bool operator ==(Object other) => other is DownloadChoice && other.format == format && other.quality == quality;

  @override
  int get hashCode => Object.hash(format, quality);

  @override
  String toString() => '${format.name}/${quality.name}';
}

/// One audio-only stream a video offers, whichever service listed it.
class AudioCandidate {
  const AudioCandidate({required this.id, required this.opus, required this.kbps, this.processed = false, this.ref});

  final String id;
  final bool opus;
  final int kbps;

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
      processed: id.contains('drc') || (lang is num && lang < 0),
      ref: f,
    );
  }

  static AudioCandidate fromExplode(AudioOnlyStreamInfo s, {required bool processed}) => AudioCandidate(
    id: '${s.tag}',
    opus: s.audioCodec.toLowerCase().contains('opus'),
    kbps: s.bitrate.kiloBitsPerSecond.round(),
    processed: processed,
    ref: s,
  );
}

/// What [pickForDownload] decided.
class AudioPick {
  const AudioPick(this.candidate, {this.reencodeKbps});

  final AudioCandidate candidate;

  /// Set when nothing YouTube serves is small enough: the stream is converted
  /// down to this bitrate after it arrives. Never above the stream's own.
  final int? reencodeKbps;

  /// The bitrate the saved file really has.
  int get kbps => reencodeKbps ?? candidate.kbps;

  bool get opus => candidate.opus;

  /// e.g. "Opus · 138 kbps", for the downloads list.
  String get label => describeAudio(opus: opus, kbps: kbps);
}

String describeAudio({required bool opus, required int? kbps}) =>
    '${opus ? 'Opus' : 'AAC'}${kbps == null || kbps <= 0 ? '' : ' · $kbps kbps'}';

/// Chooses the stream for [choice] out of everything a video offers.
///
/// * The format asked for wins; the other one only if the video has none.
/// * "Best available" is the highest bitrate. Smaller steps take the highest
///   stream at or under their cap, YouTube's own lower stream where it has one.
/// * Only when every stream is above the cap is one converted down (if
///   [canReencode], i.e. ffmpeg is there). Nothing is ever converted up, and
///   without ffmpeg the smallest stream is used as it is.
/// Below this, a stream is taken for a broken one when the other format has a real one.
const _brokenKbps = 32;

AudioPick? pickForDownload(Iterable<AudioCandidate> all, DownloadChoice choice, {required bool canReencode}) {
  final usable = all.where((c) => !c.processed).toList();
  if (usable.isEmpty) return null;
  final wantOpus = choice.format == DownloadFormat.opus;
  var pool = usable.where((c) => c.opus == wantOpus).toList();
  if (pool.isEmpty) pool = usable;
  pool.sort((a, b) => b.kbps.compareTo(a.kbps));
  // Some uploads carry a near-silent Opus beside a normal AAC. A 4 kbps file is
  // not what anyone asking for the best wants: take the other format then.
  final other = usable.where((c) => c.opus != pool.first.opus).toList()..sort((a, b) => b.kbps.compareTo(a.kbps));
  if (pool.first.kbps < _brokenKbps && other.isNotEmpty && other.first.kbps >= 96) pool = other;
  final cap = choice.quality.capKbps;
  if (cap == null) return AudioPick(pool.first);
  for (final c in pool) {
    if (c.kbps <= cap) return AudioPick(c);
  }
  final smallest = pool.last;
  return AudioPick(smallest, reencodeKbps: canReencode && smallest.kbps > cap ? cap : null);
}

/// What the user set under Settings › Downloads.
class DownloadPrefs extends ChangeNotifier {
  DownloadPrefs();

  static final instance = DownloadPrefs();

  DownloadFormat format = DownloadFormat.opus;
  DownloadQuality quality = DownloadQuality.best;
  bool askEveryTime = false;

  /// A folder the user chose (computers); null keeps the default.
  String? folder;

  /// Phones: download on mobile data too.
  bool mobileData = true;

  DownloadChoice get choice => DownloadChoice(format, quality);

  Future<void>? _loaded;

  Future<void> load() => _loaded ??= () async {
    final prefs = await SharedPreferences.getInstance();
    format = DownloadFormat.values.asNameMap()[prefs.getString('downloads.format')] ?? format;
    quality = DownloadQuality.values.asNameMap()[prefs.getString('downloads.quality')] ?? quality;
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
      case final String s:
        await prefs.setString(key, s);
    }
  }

  Future<void> setFormat(DownloadFormat v) {
    format = v;
    return _save('downloads.format', v.name);
  }

  Future<void> setQuality(DownloadQuality v) {
    quality = v;
    return _save('downloads.quality', v.name);
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

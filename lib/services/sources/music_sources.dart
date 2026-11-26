import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../merged_download.dart';
import '../metadata.dart';
import '../youtube_stream.dart';
import '../youtube_audio_source.dart';
import '../video_stream_cache.dart';

/// Settings › Accounts & services › Music sources: the places Riflay looks besides YouTube Music. Each service is
/// off until turned on; Monochrome only downloads.
class MusicSources extends ChangeNotifier {
  MusicSources._();

  static final instance = MusicSources._();

  // Each version turns every source off once for everyone (v2: they left songs stuck fetching; v3: YouTube
  // Music alone again); older choices are dropped on first start ([_read]).
  static const _soundcloudKey = 'sources.soundcloud.v3';
  static const _monochromeKey = 'sources.monochrome.v3';
  static const _smartMergeKey = 'sources.smartMerge.v3';
  static const _oldKeys = [
    'sources.soundcloud.v1',
    'sources.monochrome.v1',
    'sources.smartMerge.v1',
    'sources.soundcloud.v2',
    'sources.monochrome.v2',
    'sources.smartMerge.v2',
  ];
  static const _cacheKey = 'sources.smartMergeCacheMb.v1';

  /// How much Smart merge keeps on disk of the songs it played (MB), so a song played again opens from there
  /// without asking the service; 0 keeps none.
  int audioCap = 0;
  bool dataSaver = false;
  Future<void> setAudioCap(int cap) async {
    audioCap = cap;
    YoutubeStream.configurePlayback(cap, dataSaver);
    notifyListeners();
    await (await SharedPreferences.getInstance()).setInt('stream.audioCap', cap);
  }

  Future<void> setDataSaver(bool value) async {
    dataSaver = value;
    YoutubeStream.configurePlayback(audioCap, value);
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool('stream.dataSaver', value);
  }

  int smartMergeCacheMb = 1024;
  int videoMb = 384, imageMb = 128;
  Future<void> setVideoMb(int mb) async {
    videoMb = mb;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setInt('cache.videoMb', mb);
    await VideoStreamCache.instance.setLimit(mb << 20);
  }

  Future<void> setImageMb(int mb) async {
    imageMb = mb;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setInt('cache.imageMb', mb);
    await Metadata.setArtLimit(mb << 20);
  }

  static const cacheChoices = [0, 512, 1024, 2048, 5120];
  bool soundcloud = false;
  bool monochrome = false;

  /// A YouTube Music song plays from a lossless file of the same recording in the library (see `SmartMerge`). On
  /// by default: it never waits on the network.
  bool smartMerge = true;

  Future<void>? _loading;

  Future<void> load() => _loading ??= _read();

  Future<void> _read() async {
    final p = await SharedPreferences.getInstance();
    audioCap = p.getInt('stream.audioCap') ?? 0;
    dataSaver = p.getBool('stream.dataSaver') ?? false;
    YoutubeStream.configurePlayback(audioCap, dataSaver);
    soundcloud = p.getBool(_soundcloudKey) ?? false;
    monochrome = p.getBool(_monochromeKey) ?? false;
    smartMerge = p.getBool(_smartMergeKey) ?? true;
    for (final old in _oldKeys) {
      if (p.containsKey(old)) p.remove(old).ignore();
    }
    videoMb = (p.getInt('cache.videoMb') ?? 384).clamp(0, 5120);
    imageMb = (p.getInt('cache.imageMb') ?? 128).clamp(0, 5120);
    VideoStreamCache.instance.maxBytes = videoMb << 20;
    Metadata.artLimit = imageMb << 20;
    smartMergeCacheMb = p.getInt(_cacheKey) ?? 1024;
    _applyCache();
    notifyListeners();
  }

  Future<void> setSoundcloud(bool value) async {
    soundcloud = value;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool(_soundcloudKey, value);
  }

  Future<void> setMonochrome(bool value) async {
    monochrome = value;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool(_monochromeKey, value);
  }

  Future<void> setSmartMerge(bool value) async {
    smartMerge = value;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool(_smartMergeKey, value);
  }

  Future<void> setSmartMergeCacheMb(int mb) async {
    smartMergeCacheMb = mb;
    _applyCache();
    notifyListeners();
    await (await SharedPreferences.getInstance()).setInt(_cacheKey, mb);
    await MergedDownload.trimKept();
  }

  void _applyCache() {
    // Reserve a small share of the music budget for YouTube's streaming session.
    final sessionMb = (smartMergeCacheMb ~/ 8).clamp(0, 64);
    YoutubeAudioSource.setCacheBudget(sessionMb << 20);
    MergedDownload.keptBytes = (smartMergeCacheMb - sessionMb) << 20;
    MergedDownload.keepsSongs = smartMergeCacheMb > 0 && MergedDownload.keepsByDefault;
  }

  @visibleForTesting
  void reset() {
    _loading = null;
    soundcloud = monochrome = false;
    smartMerge = true;
  }
}

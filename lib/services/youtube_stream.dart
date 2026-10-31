import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/host.dart';
import 'download_prefs.dart';
import 'video_download.dart';
import 'youtube_player_api.dart';
import 'ytdlp.dart';

/// Finds a YouTube song's audio stream with one request to YouTube's player
/// API (~0.2 s once warmed up). Desktop falls back to yt-dlp ([best]) when
/// YouTube refuses it; phones, which have no yt-dlp, to youtube_explode.
///
/// The requests and the stream choice are in `youtube_player_api.dart` (the web proxy sends the same ones). URLs
/// from the Android clients youtube_explode uses stop after the first megabyte (HTTP 403).
abstract final class YoutubeStream {
  static final _http = http.Client();

  static Future<String?>? _visitor;
  static DateTime? _visitorAt;
  static const _visitorKey = 'youtube.visitor.v1';
  static const _visitorLife = Duration(hours: 6);

  /// A visitor id, reused for a few hours, across restarts too (the first
  /// song after launch then needs no extra request).
  static Future<String?> _visitorData(String videoId, {bool fresh = false}) {
    final stale = _visitorAt == null || DateTime.now().difference(_visitorAt!) > _visitorLife;
    if (fresh || stale || _visitor == null) {
      _visitorAt = DateTime.now();
      _visitor = () async {
        if (!fresh) {
          final saved = await _savedVisitor();
          if (saved != null) return saved;
        }
        final id = await _fetchVisitor(videoId);
        if (id != null) _saveVisitor(id).ignore();
        return id;
      }();
      _visitor!.then<void>((_) {}, onError: (Object _) => _visitor = null);
    }
    return _visitor!;
  }

  static Future<String?> _savedVisitor() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getString(_visitorKey)?.split(' ');
      if (saved == null || saved.length != 2) return null;
      final at = DateTime.fromMillisecondsSinceEpoch(int.tryParse(saved[0]) ?? 0);
      if (DateTime.now().difference(at) > _visitorLife) return null;
      _visitorAt = at;
      return saved[1];
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveVisitor(String id) async =>
      (await SharedPreferences.getInstance()).setString(_visitorKey, '${DateTime.now().millisecondsSinceEpoch} $id');

  /// InnerTube's visitor_id endpoint (~1 KB); the watch page (~1.4 MB) if that fails.
  static Future<String?> _fetchVisitor(String videoId) async {
    try {
      final res = await _http
          .post(
            YoutubePlayerApi.visitorUrl,
            headers: YoutubePlayerApi.visitorHeaders,
            body: jsonEncode(YoutubePlayerApi.visitorBody),
          )
          .timeout(const Duration(seconds: 10));
      final id = YoutubePlayerApi.visitorFrom(jsonDecode(res.body));
      if (res.statusCode == 200 && id != null) return id;
    } catch (e) {
      debugPrint('visitor_id failed, reading the watch page: $e');
    }
    final page = await _http.get(
      Uri.parse('https://www.youtube.com/watch?v=$videoId&bpctr=9999999999&has_verified=1'),
      headers: {'user-agent': YoutubePlayerApi.pageUserAgent, 'accept-language': 'en-US,en;q=0.9'},
    );
    return RegExp(r'"VISITOR_DATA":"([^"]+)"').firstMatch(page.body)?.group(1);
  }

  /// Fetches the visitor id in the background, so the first song starts fast.
  static void warmUp() => _visitorData('dQw4w9WgXcQ').ignore();

  /// The stream to play or download: the player API first, then yt-dlp where
  /// there is one (much slower: a process per song, but it keeps up with
  /// YouTube's changes). Both are cached while the URL is fresh.
  ///
  /// [aac] asks for AAC even where Opus would be better, for players that
  /// can't decode Opus (most TVs and speakers on the network).
  static Future<ResolvedAudio> best(String videoId, {bool aac = false}) async {
    try {
      return await resolve(videoId, aac: aac);
    } catch (e) {
      if (!YtDlp.supported) rethrow;
      debugPrint('YouTube player API failed for $videoId, using yt-dlp: $e');
      return YtDlp.resolve(videoId, aac: aac);
    }
  }

  /// Forget [videoId]'s URL everywhere (e.g. after the server rejected it).
  static void invalidateEverywhere(String videoId) {
    invalidate(videoId);
    if (YtDlp.supported) YtDlp.invalidate(videoId);
  }

  static final _resolved = <String, Future<ResolvedAudio>>{};

  /// The best original audio stream of [videoId], cached while its URL is fresh.
  static Future<ResolvedAudio> resolve(String videoId, {bool aac = false}) {
    final cached = _resolved[aac ? 'aac:$videoId' : videoId];
    if (cached != null) return cached.then((r) => r.isFresh ? r : _refresh(videoId, aac));
    return _refresh(videoId, aac);
  }

  /// Forget a cached URL (e.g. after the server rejected it).
  static void invalidate(String videoId) => _resolved
    ..remove(videoId)
    ..remove('aac:$videoId');

  static Future<ResolvedAudio> _refresh(String videoId, bool aac) {
    final key = aac ? 'aac:$videoId' : videoId;
    final future = _player(videoId, aac: aac).catchError((Object _) => _player(videoId, aac: aac, freshVisitor: true));
    _resolved[key] = future;
    future.then<void>((_) {}, onError: (Object _) => _resolved.remove(key));
    return future;
  }

  static Future<ResolvedAudio> _player(String videoId, {bool aac = false, bool freshVisitor = false}) async {
    final j = await _playerResponse(videoId, freshVisitor: freshVisitor);
    final best = pickBest(_adaptiveFormats(j), aacOnly: aac);
    if (best == null) throw StateError('No audio stream for this song.');
    return _resolvedFrom(best, j);
  }

  static List<Map<String, dynamic>> _adaptiveFormats(Map<String, dynamic> j) => YoutubePlayerApi.adaptiveFormats(j);

  static ResolvedAudio _resolvedFrom(Map<String, dynamic> best, Map<String, dynamic> j) {
    final url = Uri.parse(best['url'] as String);
    final mime = best['mimeType'] as String;
    final loudness = (j['playerConfig'] as Map<String, dynamic>?)?['audioConfig'] as Map<String, dynamic>?;
    return ResolvedAudio(
      url: url,
      formatId: '${best['itag']}',
      ext: mime.startsWith('audio/webm') ? 'webm' : 'm4a',
      codec: RegExp(r'codecs="([^"]+)"').firstMatch(mime)?.group(1) ?? '',
      kbps: (((best['averageBitrate'] ?? best['bitrate']) as num?)?.toDouble() ?? 0) ~/ 1000,
      size: int.tryParse(best['contentLength'] as String? ?? '') ?? int.tryParse(url.queryParameters['clen'] ?? ''),
      resolvedAt: DateTime.now(),
      via: 'YouTube player API',
      loudness: (loudness?['trackAbsoluteLoudnessLkfs'] as num?)?.toDouble(),
      loudnessTarget: (loudness?['loudnessTargetLkfs'] as num?)?.toDouble(),
    );
  }

  static const _listingLife = Duration(minutes: 10);
  static const _expiryMargin = Duration(minutes: 5);
  static const _listingCap = 40;

  static final _listings = <String, Future<_Listing>>{};

  /// When a googlevideo stream URL stops working (its `expire` parameter, seconds since the epoch); null if it has none.
  static DateTime? urlExpiry(Uri url) => YoutubePlayerApi.urlExpiry(url);

  /// Whether a listing fetched at [fetchedAt] can still be used at [now]: under ten minutes old, and none of its
  /// [urls] expires within five minutes.
  static bool listingFresh(DateTime fetchedAt, Iterable<Uri> urls, DateTime now) {
    if (now.difference(fetchedAt) >= _listingLife) return false;
    for (final u in urls) {
      final e = urlExpiry(u);
      if (e != null && e.difference(now) < _expiryMargin) return false;
    }
    return true;
  }

  /// Every audio stream YouTube offers for [videoId] (sizes included), for the download picker and for
  /// [forDownload]. Cached for ten minutes; a call while one is running shares it.
  static Future<List<AudioCandidate>> downloadCandidates(String videoId) async => (await _listing(videoId)).candidates;

  /// Every picture and sound stream YouTube offers for [videoId], for the video download. Shares the cached
  /// listing of [downloadCandidates].
  static Future<VideoFormats> videoFormats(String videoId) async {
    final l = await _listing(videoId);
    return VideoFormats(l.videos, l.candidates);
  }

  /// Finds the music video that goes with a song (its video id), or null when it has none. Set by the app, whose
  /// YouTube Music client knows the pairs a signed-in account gets; without it no video is offered.
  static Future<String?> Function(String songId)? musicVideoIdLookup;

  static final _videoLookups = <String, Future<_VideoLookup>>{};

  /// What the music video of the song [songId] offers (picture and sound streams), or null when it has none.
  /// Cached like [downloadCandidates] (ten minutes, and while no URL is about to expire); a call while one is
  /// running shares it. Throws when the lookup fails.
  static Future<VideoFormats?> musicVideoFormats(String songId) async => (await _videoLookup(songId)).formats;

  /// The lookup behind [musicVideoFormats]. The slow parts overlap: while YouTube Music is asked for the video's
  /// id, the visitor id is made ready ([warm]), and the song's own formats are looked up too (they are cached by
  /// the audio prefetch), because a song that is itself a video is the very video wanted: its sizes are then there
  /// the moment the id comes back. [sequential] does it one after the other, for the timing tests.
  @visibleForTesting
  static Future<VideoFormats?> lookUpMusicVideo(
    String songId, {
    required Future<String?> Function(String songId) findVideo,
    required Future<VideoFormats> Function(String videoId) formatsOf,
    Future<void> Function()? warm,
    bool sequential = false,
  }) async {
    if (sequential) {
      final id = await findVideo(songId);
      if (id == null) return null;
      await warm?.call();
      final formats = await formatsOf(id);
      return formats.isEmpty ? null : formats;
    }
    final own = formatsOf(songId);
    own.ignore(); // only awaited when the song is its own video
    final found = findVideo(songId);
    if (warm != null) {
      // Not waited for: it only has to be under way while the id is looked up.
      warm().then<void>((_) {}, onError: (Object _) {});
    }
    final id = await found;
    if (id == null) return null;
    final formats = await (id == songId ? own : formatsOf(id));
    return formats.isEmpty ? null : formats;
  }

  static Future<_VideoLookup> _videoLookup(String songId) {
    final cached = _videoLookups[songId];
    if (cached != null) {
      return cached.then(
        (l) => listingFresh(l.at, l.urls, DateTime.now()) ? l : _fetchVideoLookup(songId),
        onError: (Object _) => _fetchVideoLookup(songId),
      );
    }
    return _fetchVideoLookup(songId);
  }

  static Future<_VideoLookup> _fetchVideoLookup(String songId) {
    final find = musicVideoIdLookup;
    final future = find == null
        ? Future.value(_VideoLookup(null, DateTime.now()))
        : lookUpMusicVideo(
            songId,
            findVideo: find,
            formatsOf: videoFormats,
            warm: () => _visitorData(songId),
          ).then((f) => _VideoLookup(f, DateTime.now()));
    _videoLookups
      ..remove(songId)
      ..[songId] = future;
    while (_videoLookups.length > _listingCap) {
      _videoLookups.remove(_videoLookups.keys.first);
    }
    future.then<void>(
      (_) {},
      onError: (Object _) {
        if (identical(_videoLookups[songId], future)) _videoLookups.remove(songId);
      },
    );
    return future;
  }

  /// Whether to look formats up ahead without being asked. A phone does only on Wi-Fi or ethernet (the lookup
  /// costs data and battery); anything else always does. [batterySaver] is false when it can't be told.
  static bool shouldPrefetchAhead({required bool phone, required bool unmetered, bool batterySaver = false}) =>
      !batterySaver && (!phone || unmetered);

  /// [shouldPrefetchAhead] for this device right now; unknown connectivity counts as metered on a phone.
  static Future<bool> prefetchAllowed() async {
    final phone = Host.isAndroid || Host.isIOS;
    if (!phone) return true;
    try {
      final now = await Connectivity().checkConnectivity();
      return shouldPrefetchAhead(
        phone: phone,
        unmetered: now.any((c) => c == ConnectivityResult.wifi || c == ConnectivityResult.ethernet),
      );
    } catch (_) {
      return false;
    }
  }

  /// The automatic lookup after a song starts: only where [prefetchAllowed]. Never throws.
  static Future<void> prefetchDownloadCandidatesIfAllowed(String videoId) async {
    if (await prefetchAllowed()) prefetchDownloadCandidates(videoId);
  }

  /// Looks [videoId]'s formats up ahead, so the picker opens ready. Never throws.
  static void prefetchDownloadCandidates(String videoId) {
    try {
      downloadCandidates(videoId).then<void>((_) {}, onError: (Object e) => debugPrint('format prefetch failed: $e'));
      // The music video's formats too, so the Video sizes of the picker are there as it opens.
      if (musicVideoIdLookup != null) {
        musicVideoFormats(videoId)
            .then<void>((_) {}, onError: (Object e) => debugPrint('music video prefetch failed: $e'));
      }
    } catch (_) {}
  }

  static Future<_Listing> _listing(String videoId) {
    final cached = _listings[videoId];
    if (cached != null) {
      return cached.then(
        (l) => listingFresh(l.at, l.urls, DateTime.now()) ? l : _fetchListing(videoId),
        onError: (Object _) => _fetchListing(videoId),
      );
    }
    return _fetchListing(videoId);
  }

  static Future<_Listing> _fetchListing(String videoId) {
    final future = _loadListing(videoId);
    // Re-inserted, so the map stays oldest first; the oldest go when it grows.
    _listings
      ..remove(videoId)
      ..[videoId] = future;
    while (_listings.length > _listingCap) {
      _listings.remove(_listings.keys.first);
    }
    // Failures aren't cached.
    future.then<void>(
      (_) {},
      onError: (Object _) {
        if (identical(_listings[videoId], future)) _listings.remove(videoId);
      },
    );
    return future;
  }

  static Future<_Listing> _loadListing(String videoId) async {
    try {
      Map<String, dynamic> j;
      try {
        j = await _playerResponse(videoId);
      } catch (_) {
        j = await _playerResponse(videoId, freshVisitor: true);
      }
      final candidates = [for (final f in _adaptiveFormats(j)) ?AudioCandidate.fromPlayer(f)];
      if (candidates.every((c) => c.processed)) throw StateError('No audio stream for this song.');
      final single = ((j['streamingData'] as Map<String, dynamic>?)?['formats'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      final videos = [
        for (final f in [..._adaptiveFormats(j), ...single]) ?VideoCandidate.fromPlayer(f),
      ];
      // Only the loudness block of the response is kept, not all of it.
      return _Listing(candidates, DateTime.now(), {'playerConfig': j['playerConfig']}, videos);
    } catch (e) {
      if (!YtDlp.supported) rethrow;
      debugPrint('YouTube player API failed for $videoId, using yt-dlp: $e');
      final all = await YtDlp.listAllFormats(videoId);
      return _Listing(all.audio, DateTime.now(), null, all.video);
    }
  }

  /// The stream a download of [choice] fetches (the player API, then yt-dlp
  /// where there is one), and what to convert it into afterwards (null keeps it as is).
  /// Reuses the formats [downloadCandidates] listed while they are fresh.
  static Future<({ResolvedAudio audio, Conversion? convert})> forDownload(
    String videoId,
    DownloadChoice choice, {
    required bool canReencode,
  }) async {
    final listing = await _listing(videoId);
    final pick = pickForDownload(listing.candidates, choice, canReencode: canReencode);
    if (pick == null) throw StateError('No audio stream for this song.');
    final player = listing.player;
    final audio = player != null
        ? _resolvedFrom(pick.candidate.ref! as Map<String, dynamic>, player)
        : YtDlp.resolvedFrom(pick.candidate);
    return (audio: audio, convert: pick.convert);
  }

  static Future<Map<String, dynamic>> _playerResponse(String videoId, {bool freshVisitor = false}) async {
    final visitor = await _visitorData(videoId, fresh: freshVisitor);
    final res = await _http
        .post(
          YoutubePlayerApi.playerUrl,
          headers: YoutubePlayerApi.playerHeaders(visitor),
          body: jsonEncode(YoutubePlayerApi.playerBody(videoId, visitor)),
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw StateError('YouTube replied ${res.statusCode}');
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (YoutubePlayerApi.unplayable(j) case final reason?) throw StateError(reason);
    return j;
  }

  /// A video-only stream of [videoId] no taller than [maxHeight] (the player
  /// API, then yt-dlp where there is one), for Video mode. Not cached: it is
  /// asked for once each time Video is turned on.
  static Future<ResolvedVideo> video(String videoId, {required int maxHeight}) async {
    try {
      Map<String, dynamic> j;
      try {
        j = await _playerResponse(videoId);
      } catch (_) {
        j = await _playerResponse(videoId, freshVisitor: true);
      }
      final best = pickVideo(_adaptiveFormats(j), maxHeight: maxHeight);
      if (best == null) throw StateError('No video stream for this song.');
      return ResolvedVideo(
        url: Uri.parse(best['url'] as String),
        height: (best['height'] as num?)?.toInt() ?? 0,
        codec: RegExp(r'codecs="([^"]+)"').firstMatch(best['mimeType'] as String)?.group(1) ?? '',
      );
    } catch (e) {
      if (!YtDlp.supported) rethrow;
      debugPrint('YouTube player API failed for the video of $videoId, using yt-dlp: $e');
      return YtDlp.resolveVideo(videoId, maxHeight: maxHeight);
    }
  }

  /// The tallest video-only stream up to [maxHeight]. H.264 first: phones and
  /// most computers decode it in hardware, so it costs the least battery;
  /// then VP9. AV1 only when there is nothing else (software decoding is heavy).
  static Map<String, dynamic>? pickVideo(List<Map<String, dynamic>> formats, {required int maxHeight}) {
    int codec(String mime) => mime.contains('avc1')
        ? 2
        : mime.contains('vp9') || mime.contains('vp09')
        ? 1
        : 0;
    final candidates = [
      for (final f in formats)
        if ((f['mimeType'] as String? ?? '').startsWith('video/') &&
            f['url'] is String &&
            ((f['height'] as num?)?.toInt() ?? 1 << 20) <= maxHeight)
          f,
    ];
    int score(Map<String, dynamic> f) => (f['height'] as num).toInt() * 4 + codec(f['mimeType'] as String);
    candidates.sort((a, b) => score(b).compareTo(score(a)));
    return candidates.firstOrNull;
  }

  /// Highest-bitrate original audio (see [YoutubePlayerApi.pickBest]).
  static Map<String, dynamic>? pickBest(List<Map<String, dynamic>> formats, {required bool aacOnly}) =>
      YoutubePlayerApi.pickBest(formats, aacOnly: aacOnly);
}

/// What was listed for one video, and when.
class _Listing {
  _Listing(this.candidates, this.at, this.player, [this.videos = const []]);

  final List<AudioCandidate> candidates;

  /// The picture streams (video only, and the single-file ones).
  final List<VideoCandidate> videos;
  final DateTime at;

  /// The player API's loudness block when the player API listed it; null for yt-dlp.
  final Map<String, dynamic>? player;

  Iterable<Uri> get urls => [
    for (final c in [...candidates.map((c) => c.ref), ...videos.map((v) => v.ref)])
      if (c is Map && c['url'] is String) Uri.parse(c['url'] as String),
  ];
}

/// What the music video of one song offers, and when it was looked up; [formats] is null when it has no video.
class _VideoLookup {
  _VideoLookup(this.formats, this.at);

  final VideoFormats? formats;
  final DateTime at;

  Iterable<Uri> get urls => [
    for (final c in [...?formats?.videos.map((v) => v.ref), ...?formats?.audios.map((a) => a.ref)])
      if (c is Map && c['url'] is String) Uri.parse(c['url'] as String),
  ];
}

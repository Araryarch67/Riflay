/// YouTube's player API as Riflay asks it: the request shapes and how the audio stream is picked from the answer.
///
/// Plain Dart with no imports: `youtube_stream.dart` sends these requests in the app, and the web proxy
/// (`tool/web_proxy`) sends the same ones when a browser asks it for a song's audio.
///
/// Asks as the Apple Vision Pro app (`VISIONOS`), the client yt-dlp itself uses when it can't run JavaScript: its
/// stream URLs need no signature deciphering and no PO token. The request needs a visitor id ([visitorUrl]), or
/// YouTube answers LOGIN_REQUIRED ("confirm you're not a bot").
library;

abstract final class YoutubePlayerApi {
  static const userAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15';

  /// A desktop browser, for the visitor id and the watch page.
  static const pageUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

  // Kept in step with yt-dlp's INNERTUBE_CLIENTS['visionos'].
  static const client = {
    'clientName': 'VISIONOS',
    'clientVersion': '1.02',
    'deviceMake': 'Apple',
    'deviceModel': 'RealityDevice17,1',
    'userAgent': userAgent,
    'osName': 'visionOS',
    'osVersion': '26.5.23O471',
    'hl': 'en',
  };

  static final playerUrl = Uri.parse('https://www.youtube.com/youtubei/v1/player?prettyPrint=false');

  /// InnerTube's visitor_id endpoint (~1 KB), asked as the desktop web client.
  static final visitorUrl = Uri.parse('https://www.youtube.com/youtubei/v1/visitor_id?prettyPrint=false');

  static const visitorHeaders = {'content-type': 'application/json', 'user-agent': pageUserAgent};

  static const visitorBody = {
    'context': {
      'client': {'clientName': 'WEB', 'clientVersion': '2.20251001.00.00', 'hl': 'en'},
    },
  };

  /// The visitor id in a visitor_id answer, or null.
  static String? visitorFrom(Object? json) {
    if (json is! Map) return null;
    final id = (json['responseContext'] as Map?)?['visitorData'];
    return id is String && id.isNotEmpty ? id : null;
  }

  static Map<String, String> playerHeaders(String? visitor) => {
    'content-type': 'application/json',
    'user-agent': userAgent,
    'origin': 'https://www.youtube.com',
    'x-youtube-client-name': '101',
    'x-youtube-client-version': '1.02',
    'x-goog-visitor-id': ?visitor,
  };

  static Map<String, Object?> playerBody(String videoId, String? visitor) => {
    'context': {
      'client': {...client, 'visitorData': ?visitor},
    },
    'videoId': videoId,
    'contentCheckOk': true,
    'racyCheckOk': true,
  };

  /// Why a player answer can't be played, or null when it can.
  static String? unplayable(Map<String, dynamic> j) {
    final playability = j['playabilityStatus'] as Map<String, dynamic>?;
    if (playability?['status'] == 'OK') return null;
    return (playability?['reason'] as String?) ?? 'This song can\'t be played (${playability?['status']}).';
  }

  static List<Map<String, dynamic>> adaptiveFormats(Map<String, dynamic> j) =>
      ((j['streamingData'] as Map<String, dynamic>?)?['adaptiveFormats'] as List? ?? const [])
          .cast<Map<String, dynamic>>();

  /// Highest-bitrate original audio: Opus wins near-ties (better per bit),
  /// unless [aacOnly] (for TVs and speakers). Leaves out "stable volume" (DRC)
  /// and dubbed tracks, and streams needing a signature.
  static Map<String, dynamic>? pickBest(List<Map<String, dynamic>> formats, {required bool aacOnly}) {
    bool usable(Map<String, dynamic> f) {
      final mime = f['mimeType'] as String? ?? '';
      if (!mime.startsWith('audio/') || f['url'] is! String) return false;
      if (aacOnly && !mime.startsWith('audio/mp4')) return false;
      if (f['isDrc'] == true || (f['xtags'] as String? ?? '').contains('drc')) return false;
      final track = f['audioTrack'] as Map<String, dynamic>?;
      return track == null || track['audioIsDefault'] != false;
    }

    int score(Map<String, dynamic> f) =>
        ((f['averageBitrate'] ?? f['bitrate']) as num? ?? 0).toInt() +
        ((f['mimeType'] as String).contains('opus') ? 16000 : 0);
    final candidates = formats.where(usable).toList()..sort((a, b) => score(b).compareTo(score(a)));
    return candidates.firstOrNull;
  }

  /// When a googlevideo stream URL stops working (its `expire` parameter, seconds since the epoch); null if it has none.
  static DateTime? urlExpiry(Uri url) {
    final s = int.tryParse(url.queryParameters['expire'] ?? '');
    return s == null ? null : DateTime.fromMillisecondsSinceEpoch(s * 1000);
  }
}

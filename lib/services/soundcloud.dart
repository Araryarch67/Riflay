import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';

/// SoundCloud, through api-v2: the API soundcloud.com's own web player calls. It wants the web player's public
/// `client_id`, which isn't a secret (every visitor's browser gets it) but changes now and then, so it is read from
/// soundcloud.com's scripts, kept, and read again when SoundCloud stops taking it.
///
/// Only what the web player plays to a signed-out visitor: full, unencrypted HLS streams. Go+ tracks (a 30 second
/// preview, `policy: SNIP`), blocked ones and encrypted streams are left out, never worked around.
class SoundcloudClient {
  SoundcloudClient({http.Client? client, this._prefs}) : _http = client ?? http.Client();

  static final instance = SoundcloudClient();

  final http.Client _http;
  final SharedPreferences? _prefs;

  static const _api = 'https://api-v2.soundcloud.com';
  static const _clientIdKey = 'soundcloud.clientId.v1';

  /// Off with `RIFLAY_NO_SOUNDCLOUD_CACHE`: the client id is read from soundcloud.com every start, searches and
  /// stream playlists are fetched every time they are asked for.
  static const _cache = !bool.fromEnvironment('RIFLAY_NO_SOUNDCLOUD_CACHE');

  static const _headers = {
    'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36',
    'Accept': 'application/json',
  };

  Future<String>? _clientId;

  Future<String> _id({bool fresh = false}) {
    if (fresh) _clientId = null;
    return _clientId ??= _loadClientId(fresh: fresh).catchError((Object e) {
      _clientId = null;
      throw e;
    });
  }

  Future<String> _loadClientId({required bool fresh}) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    if (_cache && !fresh) {
      if (prefs.getString(_clientIdKey) case final saved? when saved.isNotEmpty) return saved;
    }
    final page = await _http.get(Uri.parse('https://soundcloud.com/'), headers: _headers);
    if (page.statusCode != 200) throw SoundcloudException('soundcloud.com answered ${page.statusCode}');
    // The id sits in one of the last bundles; read from the end.
    for (final url in scriptUrls(page.body).reversed) {
      final js = await _http.get(Uri.parse(url), headers: _headers);
      if (js.statusCode != 200) continue;
      if (clientIdIn(js.body) case final id?) {
        if (_cache) await prefs.setString(_clientIdKey, id);
        return id;
      }
    }
    throw const SoundcloudException('No client_id in soundcloud.com\'s scripts');
  }

  /// GETs [path] (or a full api-v2 [url]) with the client id; a refused id is read again once.
  Future<Object?> _get(String pathOrUrl, [Map<String, String> query = const {}]) async {
    for (var attempt = 0; ; attempt++) {
      final id = await _id(fresh: attempt > 0);
      final base = Uri.parse(pathOrUrl.startsWith('http') ? pathOrUrl : '$_api$pathOrUrl');
      final uri = base.replace(queryParameters: {...base.queryParameters, ...query, 'client_id': id});
      final r = await _http.get(uri, headers: _headers);
      if ((r.statusCode == 401 || r.statusCode == 403) && attempt == 0) continue;
      if (r.statusCode != 200) throw SoundcloudException('${base.path} answered ${r.statusCode}');
      return jsonDecode(utf8.decode(r.bodyBytes));
    }
  }

  /// Tracks matching [query] that play in full.
  Future<List<Track>> search(String query, {int limit = 30}) async {
    final json = await _get('/search/tracks', {'q': query, 'limit': '$limit', 'linked_partitioning': '1'});
    return [for (final t in _list(json is Map ? json['collection'] : null)) ?parseTrack(t)];
  }

  /// Tracks like track [trackId] (SoundCloud's "Related tracks"), for autoplay.
  Future<List<Track>> related(String trackId, {int limit = 25}) async {
    final json = await _get('/tracks/$trackId/related', {'limit': '$limit', 'linked_partitioning': '1'});
    return [for (final t in _list(json is Map ? json['collection'] : null)) ?parseTrack(t)];
  }

  /// What a soundcloud.com link is: one track, or a playlist's / profile's tracks (the playable ones, in order).
  Future<SoundcloudPage> resolve(SoundcloudLink link) async {
    var url = link.url;
    if (link.short) url = await _expand(url);
    final json = await _get('/resolve', {'url': url.toString()});
    if (json is! Map) throw const SoundcloudException('Nothing at that link');
    switch (json['kind']) {
      case 'track':
        final track = parseTrack(json);
        if (track == null) throw const SoundcloudUnplayable();
        return SoundcloudPage(
          title: track.title,
          subtitle: track.artist,
          tracks: [track],
          artworkUrl: track.artworkUrl,
        );
      case 'playlist':
        final stubs = _list(json['tracks']);
        final tracks = await _fullTracks(stubs);
        return SoundcloudPage(
          title: '${json['title'] ?? ''}',
          subtitle: _userName(json['user']),
          tracks: tracks,
          artworkUrl: largeArtwork(json['artwork_url'] as String?) ?? tracks.firstOrNull?.artworkUrl,
          isPlaylist: true,
        );
      case 'user':
        final page = await _get('/users/${json['id']}/tracks', {'limit': '50', 'linked_partitioning': '1'});
        final tracks = [for (final t in _list(page is Map ? page['collection'] : null)) ?parseTrack(t)];
        return SoundcloudPage(
          title: _userName(json),
          subtitle: '',
          tracks: tracks,
          artworkUrl: largeArtwork(json['avatar_url'] as String?),
          isPlaylist: true,
        );
    }
    throw SoundcloudException('Unknown kind ${json['kind']}');
  }

  /// A playlist's first tracks come whole, the rest as ids only: those are fetched, 50 at a time, in order.
  Future<List<Track>> _fullTracks(List<Map<String, dynamic>> stubs) async {
    final full = <String, Track?>{};
    final missing = <String>[];
    for (final s in stubs) {
      final id = '${s['id']}';
      if (s['title'] != null) {
        full[id] = parseTrack(s);
      } else {
        missing.add(id);
      }
    }
    for (var i = 0; i < missing.length; i += 50) {
      final ids = missing.sublist(i, (i + 50).clamp(0, missing.length));
      for (final t in _list(await _get('/tracks', {'ids': ids.join(',')}))) {
        full['${t['id']}'] = parseTrack(t);
      }
    }
    return [for (final s in stubs) ?full['${s['id']}']];
  }

  /// on.soundcloud.com and the app's share links redirect to the real page.
  Future<Uri> _expand(Uri url) async {
    var at = url;
    for (var hop = 0; hop < 4; hop++) {
      final request = http.Request('GET', at)
        ..followRedirects = false
        ..headers.addAll(_headers);
      final r = await _http.send(request);
      await r.stream.drain<void>();
      final location = r.headers['location'];
      if (r.statusCode < 300 || r.statusCode >= 400 || location == null) return at;
      at = at.resolve(location);
      if (at.host == 'soundcloud.com' || at.host == 'm.soundcloud.com') return at.replace(query: '');
    }
    return at;
  }

  final _playlists = <String, ({DateTime at, String text})>{};

  /// The HLS playlist of track [trackId], ready for mpv: SoundCloud signs its address for a few minutes, so it is
  /// looked up when the player asks, and kept a moment for mpv's second request (it probes, then opens).
  Future<String> playlistFor(String trackId) async {
    final kept = _playlists[trackId];
    if (_cache && kept != null && DateTime.now().difference(kept.at) < const Duration(minutes: 2)) return kept.text;
    final json = await _get('/tracks/$trackId');
    if (json is! Map) throw const SoundcloudException('No such track');
    final pick = pickTranscoding(_list((json['media'] as Map?)?['transcodings']));
    if (pick == null || !isPlayable(json)) throw const SoundcloudUnplayable();
    final auth = json['track_authorization'] as String?;
    final stream = await _get(pick, {'track_authorization': ?auth});
    final address = stream is Map ? stream['url'] as String? : null;
    if (address == null) throw const SoundcloudException('No stream address');
    final r = await _http.get(Uri.parse(address), headers: _headers);
    if (r.statusCode != 200) throw SoundcloudException('The stream playlist answered ${r.statusCode}');
    final text = absolutePlaylist(utf8.decode(r.bodyBytes), Uri.parse(address));
    if (_cache) {
      _playlists.removeWhere((_, v) => DateTime.now().difference(v.at) >= const Duration(minutes: 2));
      // A few at most: the current song and the one after it, plus a skip back.
      if (_playlists.length >= 4) _playlists.remove(_playlists.keys.first);
      _playlists[trackId] = (at: DateTime.now(), text: text);
    }
    return text;
  }

  // ── Reading api-v2's answers (pure, tested) ──────────────────────────────

  /// A track as Riflay plays it, or null when it doesn't play in full here (Go+, blocked, no open stream).
  static Track? parseTrack(Object? json) {
    if (json is! Map || json['kind'] != 'track' || json['id'] == null) return null;
    if (!isPlayable(json)) return null;
    if (pickTranscoding(_list((json['media'] as Map?)?['transcodings'])) == null) return null;
    final user = json['user'];
    final meta = json['publisher_metadata'];
    final artist = switch (meta is Map ? meta['artist'] : null) {
      final String a when a.trim().isNotEmpty => a.trim(),
      _ => _userName(user),
    };
    final ms = json['duration'];
    return Track.soundcloud(
      trackId: '${json['id']}',
      title: '${json['title'] ?? ''}'.trim(),
      artist: artist.isEmpty ? Track.unknownArtist : artist,
      permalink: json['permalink_url'] as String?,
      duration: ms is int && ms > 0 ? Duration(milliseconds: ms) : null,
      artworkUrl:
          largeArtwork(json['artwork_url'] as String?) ??
          (user is Map ? largeArtwork(user['avatar_url'] as String?) : null),
    );
  }

  /// Whether SoundCloud lets a signed-out listener hear the whole track: Go+ tracks only give a preview.
  static bool isPlayable(Map json) {
    if (json['streamable'] == false) return false;
    final policy = json['policy'];
    return policy == null || policy == 'ALLOW' || policy == 'MONETIZE';
  }

  /// The api-v2 address of the stream to play, or null when there's none Riflay may: HLS only (mpv reads it,
  /// seeking included), never a preview (`snipped`) or an encrypted (DRM) stream. AAC first, the best bitrate,
  /// then MP3 and Opus, then the adaptive master playlist.
  static String? pickTranscoding(List<Map<String, dynamic>> transcodings) {
    int? rank(Map<String, dynamic> t) {
      final format = t['format'];
      final protocol = format is Map ? format['protocol'] : null;
      final mime = format is Map ? '${format['mime_type'] ?? ''}' : '';
      if (t['snipped'] == true || protocol != 'hls' || t['url'] is! String) return null;
      final kbps = int.tryParse(RegExp(r'(\d+)k').firstMatch('${t['preset'] ?? ''}')?.group(1) ?? '') ?? 0;
      // Checked first: 'audio/mpegurl' also starts with 'audio/mpeg'.
      if (mime.contains('mpegurl')) return 1000;
      if (mime.startsWith('audio/mp4')) return 4000 + kbps;
      if (mime.startsWith('audio/mpeg')) return 3000 + kbps;
      if (mime.startsWith('audio/ogg')) return 2000 + kbps;
      return null;
    }

    String? best;
    var bestRank = -1;
    for (final t in transcodings) {
      final r = rank(t);
      if (r != null && r > bestRank) {
        best = t['url'] as String;
        bestRank = r;
      }
    }
    return best;
  }

  /// SoundCloud's 100 px `-large` cover as its 500 px one.
  static String? largeArtwork(String? url) => url?.replaceFirst(RegExp(r'-large(?=\.\w+$)'), '-t500x500');

  /// The script bundles soundcloud.com loads, in page order.
  static List<String> scriptUrls(String html) => [
    for (final m in RegExp(
      r'''<script[^>]+src=["'](https://a-v2\.sndcdn\.com/assets/[^"']+\.js)["']''',
    ).allMatches(html))
      m.group(1)!,
  ];

  /// The web player's client id in one of its bundles.
  static String? clientIdIn(String js) =>
      RegExp(r'''client_id\s*[:=]\s*["']([A-Za-z0-9]{32})["']''').firstMatch(js)?.group(1);

  /// [text] with every relative address made absolute against [base]: mpv reads the playlist from Riflay's own
  /// loopback address, where a relative segment would point back at Riflay.
  static String absolutePlaylist(String text, Uri base) {
    String abs(String u) => Uri.tryParse(u)?.hasScheme ?? false ? u : base.resolve(u).toString();
    return [
      for (final line in const LineSplitter().convert(text))
        if (line.isEmpty)
          line
        else if (line.startsWith('#'))
          line.replaceAllMapped(RegExp(r'URI="([^"]*)"'), (m) => 'URI="${abs(m.group(1)!)}"')
        else
          abs(line.trim()),
    ].join('\n');
  }

  static String _userName(Object? user) => user is Map ? '${user['username'] ?? ''}'.trim() : '';

  static List<Map<String, dynamic>> _list(Object? v) => [
    if (v is List)
      for (final e in v)
        if (e is Map) e.cast<String, dynamic>(),
  ];
}

/// A link resolved: one track, or a playlist's or profile's tracks.
class SoundcloudPage {
  const SoundcloudPage({
    required this.title,
    required this.subtitle,
    required this.tracks,
    this.artworkUrl,
    this.isPlaylist = false,
  });

  final String title;
  final String subtitle;
  final List<Track> tracks;
  final String? artworkUrl;
  final bool isPlaylist;
}

class SoundcloudException implements Exception {
  const SoundcloudException(this.message);
  final String message;

  @override
  String toString() => 'SoundcloudException: $message';
}

/// The track exists but SoundCloud doesn't let it play in full here (Go+, blocked in this country).
class SoundcloudUnplayable extends SoundcloudException {
  const SoundcloudUnplayable() : super('Not playable in full');
}

/// A soundcloud.com link, found in pasted or shared text.
class SoundcloudLink {
  const SoundcloudLink(this.url, {this.short = false});

  /// https://soundcloud.com/… (m.soundcloud.com made plain, the query dropped); a short link as it was.
  final Uri url;

  /// on.soundcloud.com or the app's share link: it redirects to the page.
  final bool short;

  static const _shortHosts = {'on.soundcloud.com', 'soundcloud.app.goo.gl'};

  /// `soundcloud.com/<this>`: SoundCloud's own pages, not a profile.
  static const _notProfiles = {
    'discover', 'search', 'stream', 'upload', 'you', 'charts', 'pages', 'settings', 'messages', 'notifications', //
    'people', 'terms-of-use', 'imprint', 'jobs', 'mobile', 'pro', 'feed', 'signin', 'logout', 'popular', 'tags',
  };

  /// The first SoundCloud link in [text] (a shared message may wrap it in words), or null.
  static SoundcloudLink? parse(String text) {
    for (final m in RegExp(r'https?://[^\s<>"]+', caseSensitive: false).allMatches(text)) {
      final link = _of(m.group(0)!);
      if (link != null) return link;
    }
    // Pasted without the scheme: soundcloud.com/artist/track.
    final bare = RegExp(r'(?:^|\s)((?:m\.|on\.)?soundcloud\.com/\S+)', caseSensitive: false).firstMatch(text);
    return bare == null ? null : _of('https://${bare.group(1)}');
  }

  /// Whether [text] holds a SoundCloud link.
  static bool looksLikeLink(String text) => parse(text) != null;

  static SoundcloudLink? _of(String raw) {
    final u = Uri.tryParse(raw.replaceFirst(RegExp(r'[).,;!?]+$'), ''));
    if (u == null) return null;
    final host = u.host.toLowerCase();
    final path = u.pathSegments.where((s) => s.isNotEmpty).toList();
    if (_shortHosts.contains(host)) {
      return path.isEmpty ? null : SoundcloudLink(u.replace(scheme: 'https'), short: true);
    }
    if (host != 'soundcloud.com' && host != 'www.soundcloud.com' && host != 'm.soundcloud.com') return null;
    if (path.isEmpty || _notProfiles.contains(path.first.toLowerCase())) return null;
    return SoundcloudLink(Uri(scheme: 'https', host: 'soundcloud.com', pathSegments: path));
  }

  /// `soundcloud.com/<user>/sets/<name>`: a playlist or album.
  bool get isPlaylist => !short && url.pathSegments.length >= 3 && url.pathSegments[1] == 'sets';

  /// `soundcloud.com/<user>/<track>` (a private one adds its secret token).
  bool get isTrack =>
      !short && url.pathSegments.length >= 2 && !isPlaylist && !_profileTabs.contains(url.pathSegments[1]);

  static const _profileTabs = {
    'tracks', 'sets', 'albums', 'likes', 'reposts', 'popular-tracks', 'following', 'followers', 'comments', //
  };

  @override
  bool operator ==(Object other) => other is SoundcloudLink && other.url == url && other.short == short;

  @override
  int get hashCode => Object.hash(url, short);
}

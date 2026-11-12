import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/track.dart';
import 'language.dart';

/// A song as another app lists it, before it's found in YouTube Music.
class ForeignSong {
  const ForeignSong({required this.title, required this.artist, this.duration});

  final String title;

  /// All of its artists, comma separated.
  final String artist;
  final Duration? duration;

  @override
  String toString() => artist.isEmpty ? title : '$artist - $title';
}

/// A playlist (or album) read from another music app ([PlaylistTransfer.services]).
class ForeignPlaylist {
  const ForeignPlaylist({required this.title, required this.service, required this.songs, int? total})
    : total = total ?? songs.length;

  final String title;

  /// One of [PlaylistTransfer.services].
  final String service;
  final List<ForeignSong> songs;

  /// How many songs the playlist really has; more than [songs] when the
  /// service only shows part of it without signing in.
  final int total;
}

class PlaylistTransferError implements Exception {
  const PlaylistTransferError(this.message);
  final String message;

  @override
  String toString() => message;
}

/// What a link points at.
typedef _Source = ({String service, String kind, String id, Uri url});

/// Copies playlists from other music apps into YouTube Music: reads the
/// public playlist page (no sign-in, no API key), then looks every song up in
/// YouTube Music's own song search.
///
/// - Spotify: the embed player's page data; it lists the first 100 songs.
/// - Apple Music: the web page's server data.
/// - Deezer: its public API, every song.
/// - TIDAL: the embed player's page (the first 50 songs), and the playlist page's schema.org data for its name
///   and size. TIDAL's site sits behind bot protection; nothing here gets around it.
/// - NetEase Cloud Music: its public web API, every song.
class PlaylistTransfer {
  PlaylistTransfer({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;

  void close() => _http.close();

  static const _ua = 'Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0';

  /// Songs read from one playlist at most; YouTube Music playlists hold 5000.
  static const maxSongs = 1000;

  static const services = ['Spotify', 'Apple Music', 'Deezer', 'TIDAL', 'NetEase Cloud Music'];

  /// Whether [text] is a playlist or album link this can read (short share
  /// links included; those are resolved when reading).
  static bool looksLikeLink(String text) => _source(text) != null || _shortLink(text) != null;

  static _Source? _source(String text) {
    final t = text.trim();
    final uri = Uri.tryParse(t);
    // spotify:playlist:ID, as the desktop app copies it.
    final spotifyUri = RegExp(r'^spotify:(playlist|album):([A-Za-z0-9]{22})$').firstMatch(t);
    if (spotifyUri != null) {
      final (kind, id) = (spotifyUri.group(1)!, spotifyUri.group(2)!);
      return (service: 'Spotify', kind: kind, id: id, url: Uri.parse('https://open.spotify.com/$kind/$id'));
    }
    if (uri == null || !uri.hasScheme) return null;
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    // tidal.com/playlist/<uuid>, tidal.com/browse/playlist/<uuid>, listen.tidal.com/playlist/<uuid>.
    if (const {'tidal.com', 'www.tidal.com', 'listen.tidal.com'}.contains(uri.host)) {
      final at = segs.indexOf('playlist');
      final id = at >= 0 && at + 1 < segs.length ? segs[at + 1] : null;
      if (id != null && RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$').hasMatch(id)) {
        return (service: 'TIDAL', kind: 'playlist', id: id, url: Uri.https('tidal.com', '/playlist/$id'));
      }
    }
    // music.163.com/#/playlist?id=…, music.163.com/playlist?id=…, y.music.163.com/m/album?id=… (the web player
    // puts the page in the fragment).
    if (uri.host == 'music.163.com' || uri.host == 'y.music.163.com') {
      final inner = uri.fragment.startsWith('/') ? Uri.tryParse(uri.fragment) : null;
      final page = inner ?? uri;
      final kind = page.pathSegments.where((s) => s.isNotEmpty).lastOrNull;
      final id = page.queryParameters['id'] ?? uri.queryParameters['id'];
      if ((kind == 'playlist' || kind == 'album') && id != null && RegExp(r'^\d+$').hasMatch(id)) {
        return (
          service: 'NetEase Cloud Music',
          kind: kind!,
          id: id,
          url: Uri.parse('https://music.163.com/#/$kind?id=$id'),
        );
      }
    }
    int at(String kind) => segs.indexOf(kind);
    String? after(String kind) => at(kind) >= 0 && at(kind) + 1 < segs.length ? segs[at(kind) + 1] : null;
    for (final kind in const ['playlist', 'album']) {
      switch (uri.host) {
        case 'open.spotify.com':
          final id = after(kind);
          if (id != null && RegExp(r'^[A-Za-z0-9]{22}$').hasMatch(id)) {
            return (service: 'Spotify', kind: kind, id: id, url: Uri.parse('https://open.spotify.com/$kind/$id'));
          }
        case 'www.deezer.com' || 'deezer.com':
          final id = after(kind);
          if (id != null && RegExp(r'^\d+$').hasMatch(id)) {
            return (service: 'Deezer', kind: kind, id: id, url: Uri.parse('https://www.deezer.com/$kind/$id'));
          }
        case 'music.apple.com' || 'itunes.apple.com':
          // /us/playlist/todays-hits/pl.f4d1…; the id is the last segment.
          if (at(kind) >= 0 && segs.length > at(kind) + 1) {
            final id = segs.last;
            if (kind == 'playlist' ? id.startsWith('pl.') : RegExp(r'^\d+$').hasMatch(id)) {
              return (
                service: 'Apple Music',
                kind: kind,
                id: id,
                url: Uri.https('music.apple.com', '/${segs.join('/')}'),
              );
            }
          }
      }
    }
    return null;
  }

  static Uri? _shortLink(String text) {
    final uri = Uri.tryParse(text.trim());
    const hosts = {'spotify.link', 'spotify.app.link', 'link.deezer.com', 'deezer.page.link', 'tidal.link', '163cn.tv'};
    return uri != null && hosts.contains(uri.host) ? uri : null;
  }

  /// Reads the songs of a playlist or album link.
  Future<ForeignPlaylist> read(String link) async {
    final source = _source(link) ?? await _resolveShortLink(link);
    if (source == null) {
      throw PlaylistTransferError(tr.notPlaylistLinkFrom(services.join(', ')));
    }
    final list = await switch (source.service) {
      'Spotify' => _spotify(source),
      'Deezer' => _deezer(source),
      'TIDAL' => _tidal(source),
      'NetEase Cloud Music' => _netease(source),
      _ => _appleMusic(source),
    };
    if (list.songs.isEmpty) throw PlaylistTransferError(tr.playlistEmptyOrPrivate);
    return list;
  }

  /// Share links (spotify.link/…, link.deezer.com/s/…) redirect, sometimes
  /// through a page that names the real link.
  Future<_Source?> _resolveShortLink(String link) async {
    var url = _shortLink(link);
    for (var hop = 0; url != null && hop < 5; hop++) {
      final req = http.Request('GET', url)
        ..followRedirects = false
        ..headers['user-agent'] = _ua;
      final res = await http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 20)));
      final location = res.headers['location'];
      if (location != null) {
        final next = url.resolve(location);
        if (_source(next.toString()) case final s?) return s;
        url = next;
        continue;
      }
      for (final m in RegExp(r'https?://[^\s"<>]+').allMatches(res.body)) {
        if (_source(m.group(0)!.replaceAll('&amp;', '&')) case final s?) return s;
      }
      return null;
    }
    return null;
  }

  Future<String> _get(Uri url, {String ua = _ua}) async {
    final res = await _http
        .get(url, headers: {'user-agent': ua, 'accept-language': 'en-US,en;q=0.9'})
        .timeout(const Duration(seconds: 30));
    if (res.statusCode == 404) throw PlaylistTransferError(tr.playlistMissingOrPrivate);
    if (res.statusCode != 200) {
      throw const PlaylistTransferError('Couldn\'t open that link right now. Try again later.');
    }
    return utf8.decode(res.bodyBytes);
  }

  static Map<String, dynamic> _scriptJson(String html, String id, String service) {
    final m = RegExp('<script[^>]*id="$id"[^>]*>(.*?)</script>', dotAll: true).firstMatch(html);
    final data = m == null ? null : jsonDecode(m.group(1)!);
    if (data is! Map<String, dynamic>) {
      throw PlaylistTransferError('$service changed its page; this link can\'t be read right now.');
    }
    return data;
  }

  Future<ForeignPlaylist> _spotify(_Source s) async {
    final embed = _get(Uri.parse('https://open.spotify.com/embed/${s.kind}/${s.id}'));
    // The full page says how many songs there are; the embed stops at 100.
    // A bare user agent gets it rendered (a browser's gets an empty shell).
    final full = _get(s.url, ua: 'Mozilla/5.0').then<String?>((p) => p, onError: (Object _) => null);
    final data = _scriptJson(await embed, '__NEXT_DATA__', 'Spotify');
    final entity = _at(data, const ['props', 'pageProps', 'state', 'data', 'entity']);
    if (entity is! Map) {
      throw PlaylistTransferError(tr.spotifyPageChanged);
    }
    final songs = [
      for (final t in (entity['trackList'] as List? ?? const []).whereType<Map>())
        if (t['title'] is String && t['entityType'] != 'episode')
          ForeignSong(
            title: t['title'] as String,
            artist: ((t['subtitle'] as String?) ?? '').replaceAll(' ', ' '),
            duration: t['duration'] is int ? Duration(milliseconds: t['duration'] as int) : null,
          ),
    ];
    final count = RegExp(r'<meta name="music:song_count" content="(\d+)"').firstMatch(await full ?? '');
    return ForeignPlaylist(
      title: (entity['name'] ?? entity['title'] ?? tr.servicePlaylist('Spotify')) as String,
      service: 'Spotify',
      songs: songs,
      total: count == null ? null : int.parse(count.group(1)!),
    );
  }

  Future<ForeignPlaylist> _appleMusic(_Source s) async {
    final data = _scriptJson(await _get(s.url), 'serialized-server-data', 'Apple Music');
    final page = _at(data, const ['data', 0, 'data']) ?? data;
    final sections = (_at(page, const ['sections']) as List? ?? const []).whereType<Map>();
    final header = sections
        .where((x) => '${x['id']}'.contains('detail-header'))
        .map((x) => (x['items'] as List?)?.firstOrNull)
        .whereType<Map>()
        .firstOrNull;
    final songs = [
      for (final section in sections.where((x) => x['itemKind'] == 'trackLockup'))
        for (final t in (section['items'] as List? ?? const []).whereType<Map>())
          if (t['title'] is String)
            ForeignSong(
              title: t['title'] as String,
              artist: ((t['artistName'] as String?) ?? '').replaceAll(' & ', ', '),
              duration: t['duration'] is int ? Duration(milliseconds: t['duration'] as int) : null,
            ),
    ];
    return ForeignPlaylist(
      title: (header?['title'] as String?) ?? tr.servicePlaylist('Apple Music'),
      service: 'Apple Music',
      songs: songs,
      total: header?['trackCount'] as int?,
    );
  }

  Future<ForeignPlaylist> _deezer(_Source s) async {
    Future<Map<String, dynamic>> api(Uri url) async {
      final j = jsonDecode(await _get(url));
      if (j is! Map<String, dynamic>) throw PlaylistTransferError(tr.unexpectedDeezerReply);
      if (j['error'] is Map) throw PlaylistTransferError(tr.playlistMissingOrPrivate);
      return j;
    }

    final info = await api(Uri.parse('https://api.deezer.com/${s.kind}/${s.id}'));
    final songs = <ForeignSong>[];
    Uri? next = Uri.parse('https://api.deezer.com/${s.kind}/${s.id}/tracks?index=0&limit=100');
    while (next != null && songs.length < maxSongs) {
      final page = await api(next);
      for (final t in (page['data'] as List? ?? const []).whereType<Map>()) {
        if (t['title'] is! String) continue;
        songs.add(
          ForeignSong(
            title: t['title'] as String,
            artist: (_at(t, const ['artist', 'name']) as String?) ?? '',
            duration: t['duration'] is int ? Duration(seconds: t['duration'] as int) : null,
          ),
        );
      }
      next = page['next'] is String ? Uri.parse(page['next'] as String) : null;
    }
    return ForeignPlaylist(
      title: (info['title'] as String?) ?? tr.servicePlaylist('Deezer'),
      service: 'Deezer',
      songs: songs,
      total: (info['nb_tracks'] as int?) ?? songs.length,
    );
  }

  Future<ForeignPlaylist> _tidal(_Source s) async {
    // The playlist page names it and counts its songs; it may be held back by the site's bot check, so it is
    // only a nicety.
    final page = _get(s.url).then<String?>((p) => p, onError: (Object _) => null);
    final embed = await _get(Uri.https('embed.tidal.com', '/playlists/${s.id}'));
    final songs = tidalSongs(embed);
    final info = tidalInfo(await page ?? '');
    return ForeignPlaylist(
      title: info.name ?? tr.servicePlaylist('TIDAL'),
      service: 'TIDAL',
      songs: songs,
      total: info.total,
    );
  }

  /// The songs in a TIDAL embed page (`window.tidalMediaSessionMetadata`), in order.
  static List<ForeignSong> tidalSongs(String embed) {
    final m = RegExp(
      r'window\.tidalMediaSessionMetadata\s*=\s*(\{.*?\});\s*$',
      multiLine: true,
      dotAll: true,
    ).firstMatch(embed);
    final data = m == null ? null : jsonDecode(m.group(1)!);
    if (data is! Map) {
      throw const PlaylistTransferError('TIDAL changed its player; this link can\'t be read right now.');
    }
    return [
      for (final t in data.values.whereType<Map>())
        if (t['title'] is String) ForeignSong(title: t['title'] as String, artist: (t['artist'] as String?) ?? ''),
    ];
  }

  /// A TIDAL playlist page's name and size, from its schema.org data.
  static ({String? name, int? total}) tidalInfo(String page) {
    for (final m in RegExp(r'<script type="application/ld\+json">(.*?)</script>', dotAll: true).allMatches(page)) {
      try {
        final j = jsonDecode(m.group(1)!);
        if (j is Map && j['@type'] == 'MusicPlaylist') {
          return (name: j['name'] as String?, total: j['numTracks'] as int?);
        }
      } on FormatException {
        // Another block.
      }
    }
    return (name: null, total: null);
  }

  Future<ForeignPlaylist> _netease(_Source s) async {
    final url = s.kind == 'album'
        ? Uri.https('music.163.com', '/api/album/${s.id}')
        : Uri.https('music.163.com', '/api/v6/playlist/detail', {'id': s.id, 'n': '$maxSongs'});
    final j = jsonDecode(await _get(url));
    if (j is! Map || j['code'] != 200) throw PlaylistTransferError(tr.playlistMissingOrPrivate);
    return neteasePlaylist(j, s.kind);
  }

  /// NetEase Cloud Music's answer for a playlist (`/api/v6/playlist/detail`) or album (`/api/album/<id>`).
  static ForeignPlaylist neteasePlaylist(Map j, String kind) {
    final list = (kind == 'album' ? j['album'] : j['playlist']) as Map? ?? const {};
    final tracks = (kind == 'album' ? list['songs'] : list['tracks']) as List? ?? const [];
    String artists(Map t) => [
      for (final a in ((t['ar'] ?? t['artists']) as List? ?? const []).whereType<Map>())
        if (a['name'] is String) a['name'] as String,
    ].join(', ');
    final songs = [
      for (final t in tracks.whereType<Map>())
        if (t['name'] is String)
          ForeignSong(
            title: t['name'] as String,
            artist: artists(t),
            duration: switch (t['dt'] ?? t['duration']) {
              final int ms => Duration(milliseconds: ms),
              _ => null,
            },
          ),
    ];
    return ForeignPlaylist(
      title: (list['name'] as String?) ?? tr.servicePlaylist('NetEase Cloud Music'),
      service: 'NetEase Cloud Music',
      songs: songs,
      total: (list['trackCount'] ?? list['size']) as int?,
    );
  }

  static Object? _at(Object? node, List<Object> path) {
    for (final key in path) {
      node = switch ((node, key)) {
        (final Map m, final String k) => m[k],
        (final List l, final int i) when i < l.length => l[i],
        _ => null,
      };
    }
    return node;
  }

  // ── Finding the songs in YouTube Music ──────────────────────────────────

  /// Looks every song up with [search] (YouTube Music's song search), a few
  /// at a time, then with [videos] for the ones it doesn't have. Returns the
  /// matches in playlist order (each video once) and the songs that weren't
  /// found. [onProgress] gets how many are done.
  static Future<({List<Track> found, List<ForeignSong> missing})> match(
    List<ForeignSong> songs,
    Future<List<Track>> Function(String query) search, {
    Future<List<Track>> Function(String query)? videos,
    void Function(int done)? onProgress,
    bool Function()? cancelled,
    int parallel = 6,
  }) async {
    final picks = List<Track?>.filled(songs.length, null);
    var next = 0, done = 0;
    Future<void> worker() async {
      while (next < songs.length && !(cancelled?.call() ?? false)) {
        final i = next++;
        final s = songs[i];
        final query = '${s.title} ${s.artist.replaceAll(',', '')}';
        try {
          picks[i] = best(s, await search(query));
          if (picks[i] == null && videos != null) {
            // Uploaders name videos loosely; the song keeps its own names.
            if (best(s, await videos(query)) case final v?) {
              picks[i] = Track.youtube(
                videoId: v.videoId!,
                title: s.title,
                artist: s.artist,
                duration: v.duration,
                artworkUrl: v.artworkUrl,
              );
            }
          }
        } catch (_) {
          // One failed lookup leaves that song out, not the whole playlist.
        }
        onProgress?.call(++done);
      }
    }

    await Future.wait([for (var w = 0; w < parallel; w++) worker()]);
    final seen = <String>{};
    return (
      found: [
        for (final t in picks)
          if (t != null && seen.add(t.id)) t,
      ],
      missing: [
        for (var i = 0; i < songs.length; i++)
          if (picks[i] == null) songs[i],
      ],
    );
  }

  /// The search hit that is this song: the title and an artist agree, and the
  /// length is about the same. Hits higher up win ties. Null when none fits.
  static Track? best(ForeignSong song, List<Track> hits) {
    final title = _norm(_bareTitle(song.title));
    final artists = [for (final a in song.artist.split(',')) ?_normOrNull(a)];
    Track? pick;
    var top = 0;
    for (final hit in hits.take(8)) {
      var score = 0;
      final t = _norm(_bareTitle(hit.title));
      if (t == title) {
        score += 4;
      } else if (t.isNotEmpty && title.isNotEmpty && (t.contains(title) || title.contains(t))) {
        score += 2;
      }
      final hitArtist = _norm(hit.artist);
      if (artists.any(hitArtist.contains)) score += 3;
      if (song.duration != null && hit.duration != null) {
        final diff = (song.duration! - hit.duration!).abs().inSeconds;
        score += diff <= 3 ? 3 : (diff <= 10 ? 1 : (diff > 30 ? -4 : 0));
      }
      if (score > top) (pick, top) = (hit, score);
    }
    // Title alone (4) isn't enough; it needs the artist or the length too.
    return top >= 5 ? pick : null;
  }

  /// "Song (feat. X) - Remastered 2011" → "Song".
  static String _bareTitle(String s) => s
      .replaceAll(RegExp(r'\s*[(\[](feat|ft|with|from)\.?\s[^)\]]*[)\]]', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s+-\s+.*(remaster|version|edit|mix|live|mono|stereo).*$', caseSensitive: false), '');

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  static String? _normOrNull(String s) {
    final n = _norm(s);
    return n.isEmpty ? null : n;
  }
}

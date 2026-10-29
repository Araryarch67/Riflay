import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'playlist_transfer.dart';

/// What Spotify's web player sends with every request, from its own sign-in.
typedef SpotifyAuth = ({String accessToken, String clientToken, String appVersion});

/// What a [SpotifyItem] is.
enum SpotifyItemKind { liked, playlist, album, artist }

/// One thing in the user's Spotify library: Liked Songs, a playlist, a saved
/// album or a followed artist.
class SpotifyItem {
  const SpotifyItem({
    required this.kind,
    required this.uri,
    required this.name,
    this.subtitle,
    this.imageUrl,
    this.count,
  });

  final SpotifyItemKind kind;

  /// `spotify:playlist:…`, `spotify:album:…`, `spotify:artist:…` or `spotify:collection:tracks`.
  final String uri;
  final String name;

  /// The owner of a playlist, the artists of an album.
  final String? subtitle;
  final String? imageUrl;

  /// How many songs it holds, when Spotify says.
  final int? count;
}

/// The Spotify sign-in is no longer valid and a fresh one didn't help.
class SpotifySignedOut implements Exception {
  const SpotifySignedOut();

  static const message = 'Your Spotify sign-in has expired. Sign in again.';

  @override
  String toString() => message;
}

/// Reads the signed-in user's library through the web player's own GraphQL
/// ("pathfinder") API. Unofficial: Spotify can change it without notice, so
/// everything is parsed defensively and failures end as one calm sentence.
class SpotifyLibraryClient {
  SpotifyLibraryClient({required this.auth, http.Client? client})
    : _http = client ?? http.Client(),
      _ownsClient = client == null;

  /// Gives the current tokens; `force` asks for fresh ones after a 401.
  final Future<SpotifyAuth> Function({bool force}) auth;
  final http.Client _http;
  final bool _ownsClient;

  static const _ua = 'Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0';
  static const _endpoint = 'https://api-partner.spotify.com/pathfinder/v2/query';
  static const _timeout = Duration(seconds: 30);
  static const _failure = PlaylistTransferError('Couldn\'t read your Spotify library right now. Try again later.');

  /// The query hashes of the web player at the time of writing; used when its
  /// bundle can't be read. profileAttributes has none: the name is optional.
  static const _fallbackHashes = {
    'libraryV3': '390c78e5b951029bad359785e69b07b536a509c581cbcd0aded5e5067f187455',
    'fetchLibraryTracks': '087278b20b743578a6262c2b0b4bcd20d879c503cc359a2285baf083ef944240',
    'fetchPlaylist': '21ea11a6ac75a5f3e01fd365d29c18e0a4a8b7dc09f89bbb5d73910190c6acaf',
    'getAlbum': '0b6ce3511e1b02e4a40fa95440f992acbe85080eb308af9194322d708fc1914f',
  };

  Future<Map<String, String>>? _hashes;

  void close() {
    if (_ownsClient) _http.close();
  }

  // ── Library ─────────────────────────────────────────────────────────────

  /// The account's display name, or null when it can't be read.
  Future<String?> profileName() async {
    final data = await _query('profileAttributes', const {}, optional: true);
    if (data == null) return null;
    final name = _at(data, const ['data', 'me', 'profile', 'name']);
    return name is String && name.trim().isNotEmpty ? name.trim() : null;
  }

  /// Liked Songs first, then the playlists (folders are flattened away).
  Future<List<SpotifyItem>> playlists() async {
    final items = await _library('Playlists');
    final liked = items.where((i) => i.kind == SpotifyItemKind.liked);
    return [...liked, ...items.where((i) => i.kind == SpotifyItemKind.playlist)];
  }

  Future<List<SpotifyItem>> albums() => _library('Albums');

  Future<List<SpotifyItem>> artists() => _library('Artists');

  Future<List<SpotifyItem>> _library(String filter) async {
    final out = <SpotifyItem>[];
    final seen = <String>{};
    var offset = 0;
    int? total;
    while (total == null || offset < total) {
      final data = await _query('libraryV3', {
        'filters': [filter],
        'order': null,
        'textFilter': null,
        'features': const ['LIKED_SONGS'],
        'limit': 50,
        'offset': offset,
        'flatten': true,
        'includeFoldersWhenFlattening': true,
        'folderUri': null,
      });
      final page = _at(data, const ['data', 'me', 'libraryV3']);
      final raw = _at(page, const ['items']);
      if (raw is! List) throw _bad('libraryV3 had no items');
      total = _at(page, const ['totalCount']) as int? ?? raw.length;
      for (final entry in raw) {
        final item = _libraryItem(_at(entry, const ['item']), filter);
        if (item != null && seen.add(item.uri)) out.add(item);
      }
      // Advance by what Spotify sent, not by what parsed, so pages stay aligned.
      if (raw.isEmpty) break;
      offset += raw.length;
    }
    return out;
  }

  static SpotifyItem? _libraryItem(Object? item, String filter) {
    if (item is! Map) return null;
    final data = _at(item, const ['data']);
    final type = _at(data, const ['__typename']) as String? ?? '';
    final uri = (item['_uri'] ?? _at(data, const ['uri'])) as Object?;
    if (uri is! String || uri.isEmpty || type.contains('Folder') || uri.contains(':folder:')) return null;
    String? text(List<Object> path) {
      final v = _at(data, path);
      return v is String && v.trim().isNotEmpty ? v.trim() : null;
    }

    String? image(List<Object> path) => text([...path, 'sources', 0, 'url']);
    String names(List<Object> path) => _names(_at(data, path));

    if (uri == 'spotify:collection:tracks') {
      if (filter != 'Playlists') return null;
      return SpotifyItem(
        kind: SpotifyItemKind.liked,
        uri: uri,
        name: text(const ['name']) ?? 'Liked Songs',
        count: _at(data, const ['count']) as int?,
      );
    }
    final name = text(const ['name']) ?? text(const ['profile', 'name']);
    if (name == null) return null;
    switch (filter) {
      case 'Playlists':
        if (!uri.startsWith('spotify:playlist:')) return null;
        return SpotifyItem(
          kind: SpotifyItemKind.playlist,
          uri: uri,
          name: name,
          subtitle: text(const ['ownerV2', 'data', 'name']),
          imageUrl: image(const ['images', 'items', 0]),
          count: _at(data, const ['content', 'totalCount']) as int?,
        );
      case 'Albums':
        if (!uri.startsWith('spotify:album:')) return null;
        final artists = names(const ['artists', 'items']);
        return SpotifyItem(
          kind: SpotifyItemKind.album,
          uri: uri,
          name: name,
          subtitle: artists.isEmpty ? null : artists,
          imageUrl: image(const ['coverArt']),
        );
      default:
        if (!uri.startsWith('spotify:artist:')) return null;
        return SpotifyItem(
          kind: SpotifyItemKind.artist,
          uri: uri,
          name: name,
          imageUrl: image(const ['visuals', 'avatarImage']),
        );
    }
  }

  // ── Songs ───────────────────────────────────────────────────────────────

  /// The songs of Liked Songs, a playlist or an album, at most [max]. The
  /// result's `total` is the real size. Artists aren't imported as songs.
  Future<ForeignPlaylist> songs(SpotifyItem item, {int max = 5000}) async {
    if (item.kind == SpotifyItemKind.artist) throw ArgumentError('Artists have no songs to import.');
    final (operation, pageSize) = switch (item.kind) {
      SpotifyItemKind.liked => ('fetchLibraryTracks', 50),
      SpotifyItemKind.playlist => ('fetchPlaylist', 100),
      _ => ('getAlbum', 50),
    };
    final songs = <ForeignSong>[];
    var offset = 0;
    int? total;
    while (songs.length < max && (total == null || offset < total)) {
      final data = await _query(operation, switch (item.kind) {
        SpotifyItemKind.liked => {'offset': offset, 'limit': pageSize},
        SpotifyItemKind.playlist => {
          'uri': item.uri,
          'offset': offset,
          'limit': pageSize,
          'enableWatchFeedEntrypoint': false,
        },
        _ => {'uri': item.uri, 'locale': '', 'offset': offset, 'limit': pageSize},
      });
      final (page, tracks) = switch (item.kind) {
        SpotifyItemKind.liked => _pair(data, const ['data', 'me', 'library', 'tracks'], (e) => _at(e, const ['track'])),
        SpotifyItemKind.playlist => _pair(
          data,
          const ['data', 'playlistV2', 'content'],
          (e) => _at(e, const ['itemV2', 'data']),
          tracksOnly: true,
        ),
        _ => _pair(data, const ['data', 'albumUnion', 'tracksV2'], (e) => _at(e, const ['track'])),
      };
      final raw = _at(page, const ['items']);
      if (raw is! List) throw _bad('$operation had no items');
      total = _at(page, const ['totalCount']) as int? ?? raw.length;
      for (final t in tracks) {
        if (songs.length >= max) break;
        songs.add(t);
      }
      if (raw.isEmpty) break;
      offset += raw.length;
    }
    return ForeignPlaylist(title: item.name, service: 'Spotify', songs: songs, total: total ?? songs.length);
  }

  /// A page of [path] in [data] and the songs on it. Liked Songs wrap the
  /// track one level deeper (`track.data`), so [pick] may return either shape.
  static (Object?, List<ForeignSong>) _pair(
    Object? data,
    List<Object> path,
    Object? Function(Object?) pick, {
    bool tracksOnly = false,
  }) {
    final page = _at(data, path);
    final raw = _at(page, const ['items']);
    final out = <ForeignSong>[];
    if (raw is List) {
      for (final entry in raw) {
        var t = pick(entry);
        // Liked Songs: track{_uri, data{…}}.
        if (t is Map && t['data'] is Map && t['name'] == null) t = t['data'];
        final song = _song(t, tracksOnly: tracksOnly);
        if (song != null) out.add(song);
      }
    }
    return (page, out);
  }

  /// Skips episodes, local files and anything without a name.
  static ForeignSong? _song(Object? t, {bool tracksOnly = false}) {
    if (t is! Map) return null;
    final type = t['__typename'];
    if (tracksOnly ? type != 'Track' : (type != null && type != 'Track')) return null;
    final title = t['name'];
    if (title is! String || title.trim().isEmpty) return null;
    final ms = _at(t, const ['trackDuration', 'totalMilliseconds']) ?? _at(t, const ['duration', 'totalMilliseconds']);
    return ForeignSong(
      title: title.trim(),
      artist: _names(_at(t, const ['artists', 'items'])),
      duration: ms is int && ms > 0 ? Duration(milliseconds: ms) : null,
    );
  }

  static String _names(Object? artists) {
    if (artists is! List) return '';
    return [
      for (final a in artists)
        if (_at(a, const ['profile', 'name']) case final String n when n.trim().isNotEmpty) n.trim(),
    ].join(', ');
  }

  // ── Talking to Spotify ──────────────────────────────────────────────────

  /// The persisted-query hashes of the live web player, scanned once.
  Future<Map<String, String>> _operationHashes({bool rescan = false}) {
    if (rescan) _hashes = null;
    return _hashes ??= _scanHashes();
  }

  Future<Map<String, String>> _scanHashes() async {
    try {
      final headers = {'user-agent': _ua, 'accept-language': 'en'};
      final page = await _http.get(Uri.parse('https://open.spotify.com/'), headers: headers).timeout(_timeout);
      if (page.statusCode != 200) throw 'web player page answered ${page.statusCode}';
      // The main bundle only; vendor~ and encore~ bundles carry no queries.
      final bundle = RegExp(r'https://open\.spotifycdn\.com/cdn/build/web-player/web-player\.[0-9a-f]+\.js');
      final url = bundle.firstMatch(page.body)?.group(0);
      if (url == null) throw 'no web player bundle in the page';
      final js = await _http.get(Uri.parse(url), headers: headers).timeout(_timeout);
      if (js.statusCode != 200) throw 'bundle answered ${js.statusCode}';
      final found = <String, String>{};
      for (final m in RegExp(r'"(\w+)","(?:query|mutation)","([0-9a-f]{64})"').allMatches(js.body)) {
        found[m.group(1)!] = m.group(2)!;
      }
      if (!_fallbackHashes.keys.every(found.containsKey)) throw 'bundle lacks some library queries';
      return found;
    } catch (e) {
      debugPrint('Spotify: reading the query hashes failed, using the built-in ones: $e');
      return _fallbackHashes;
    }
  }

  /// Runs a persisted query and returns the decoded body. With [optional], a
  /// missing hash or a failure gives null instead of an error.
  Future<Map<String, Object?>?> _query(
    String operation,
    Map<String, Object?> variables, {
    bool optional = false,
  }) async {
    var refreshed = false;
    var rescanned = false;
    var throttled = 0;
    var forceAuth = false;
    while (true) {
      final hash = (await _operationHashes())[operation];
      if (hash == null) {
        if (optional) return null;
        throw _bad('no hash for $operation');
      }
      final http.Response res;
      try {
        final tokens = await auth(force: forceAuth);
        forceAuth = false;
        res = await _http
            .post(
              Uri.parse(_endpoint),
              headers: {
                'authorization': 'Bearer ${tokens.accessToken}',
                'client-token': tokens.clientToken,
                'app-platform': 'WebPlayer',
                if (tokens.appVersion.isNotEmpty) 'spotify-app-version': tokens.appVersion,
                'content-type': 'application/json;charset=UTF-8',
                'accept': 'application/json',
                'accept-language': 'en',
                // Spotify answers 403 to a non-browser user agent.
                'user-agent': _ua,
              },
              body: jsonEncode({
                'variables': variables,
                'operationName': operation,
                'extensions': {
                  'persistedQuery': {'version': 1, 'sha256Hash': hash},
                },
              }),
            )
            .timeout(_timeout);
      } on SpotifySignedOut {
        rethrow;
      } catch (e) {
        if (optional) return null;
        throw _bad('$operation request failed: $e');
      }
      if (res.statusCode == 401) {
        if (refreshed) throw const SpotifySignedOut();
        refreshed = true;
        forceAuth = true;
        continue;
      }
      if (res.statusCode == 429 && throttled < 3) {
        throttled++;
        final secs = int.tryParse(res.headers['retry-after'] ?? '') ?? 2;
        await Future<void>.delayed(Duration(seconds: secs.clamp(0, 10)));
        continue;
      }
      Object? body;
      try {
        body = jsonDecode(utf8.decode(res.bodyBytes));
      } catch (_) {}
      // Spotify answers an unknown hash with an error, whatever the status.
      if (!rescanned && res.body.contains('PersistedQueryNotFound')) {
        rescanned = true;
        await _operationHashes(rescan: true);
        continue;
      }
      if (res.statusCode != 200 || body is! Map<String, Object?> || body['data'] == null) {
        if (optional) return null;
        throw _bad(
          '$operation answered ${res.statusCode}: ${res.body.length > 300 ? res.body.substring(0, 300) : res.body}',
        );
      }
      return body;
    }
  }

  static PlaylistTransferError _bad(String why) {
    debugPrint('Spotify library: $why');
    return _failure;
  }

  static Object? _at(Object? node, List<Object> path) {
    for (final key in path) {
      node = switch ((node, key)) {
        (final Map m, final String k) => m[k],
        (final List l, final int i) when i >= 0 && i < l.length => l[i],
        _ => null,
      };
    }
    return node;
  }
}

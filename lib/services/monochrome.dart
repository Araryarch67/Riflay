import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/track.dart';
import 'merged_download.dart';
import 'sources/song_source.dart';

/// Official Monochrome share URLs. Provider prefixes are part of the id.
class MonochromeLink {
  const MonochromeLink(this.kind, this.id);
  final String kind;
  final String id;

  static MonochromeLink? parse(String text) {
    for (final match in RegExp(r'https?://[^\s<>"\u0027]+').allMatches(text)) {
      final uri = Uri.tryParse(match.group(0)!.replaceFirst(RegExp(r'[).,;]+$'), ''));
      if (uri == null ||
          !const {'monochrome.st', 'www.monochrome.st', 'monochrome.tf', 'www.monochrome.tf'}.contains(uri.host)) {
        continue;
      }
      final parts = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (parts.length != 2 || !const {'track', 'album', 'playlist', 'userplaylist'}.contains(parts[0])) continue;
      if (!RegExp(r'^[A-Za-z0-9:_-]{1,200}$').hasMatch(parts[1])) continue;
      return MonochromeLink(parts[0], parts[1]);
    }
    return null;
  }
}

class MonochromeCollection {
  const MonochromeCollection(this.title, this.tracks);
  final String title;
  final List<Track> tracks;
}

/// Monochrome's current public Tracks API, plus the HiFi API for older shares.
/// No Origin/Referer impersonation: a refusing service remains unavailable.
class Monochrome extends SongSource {
  Monochrome({http.Client? client}) : super(client: client ?? _sharedClient);
  // Reuse TLS connections across catalogue queries instead of creating and
  // closing a new connection for every title and artist search.
  static final _sharedClient = _SharedClient();
  static final instance = Monochrome();
  static const tracksBase = 'https://tracks.monochrome.st';
  static const hifiBase = String.fromEnvironment('RIFLAY_MONOCHROME_API', defaultValue: 'https://arran.monochrome.tf');
  @override
  String get name => 'Monochrome';
  @override
  String get prefix => 'monochrome:';

  Future<dynamic> _json(String base, String path, [Map<String, String>? query]) async {
    final url = Uri.parse('$base$path').replace(queryParameters: query);
    final data = jsonDecode((await get(url)).body);
    return data is Map && data['data'] != null ? data['data'] : data;
  }

  static bool _native(String id) =>
      id.startsWith('tracks:') || id.startsWith('mono:') || RegExp(r'^\d{15,}$').hasMatch(id);
  static String _clean(String id) => id.replaceFirst(RegExp(r'^(tracks|mono):(?:(track|album):)?'), '');

  /// Keeps stable ids in the library; native Tracks URLs resolve when played.
  static Track? track(Map data, {bool native = false}) {
    final rawId = data['trackId'] ?? data['id'];
    final title = SongSource.text(data['title']);
    if (rawId == null || title == null || data['playable'] == false) return null;
    final id = rawId.toString();
    native = native || data['provider'] == 'tracks' || data['tracksTrackId'] != null || _native(id);
    final clean = _clean((data['tracksTrackId'] ?? id).toString());
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(clean)) return null;
    final shareId = native ? 'tracks:track:$clean' : clean;
    final artists = data['artistNames'] ?? data['artists'];
    final artist = artists is List
        ? artists
              .map((a) => a is Map ? a['name'] ?? a['displayName'] ?? '' : a)
              .where((a) => a.toString().isNotEmpty)
              .join(', ')
        : data['artist'] is Map
        ? data['artist']['name']?.toString()
        : SongSource.text(data['artist']);
    final album = data['album'];
    final cover = data['artwork'] ?? data['artworkUrl'] ?? (album is Map ? album['cover'] : null);
    final coverUrl =
        SongSource.webUrl(cover) ??
        (cover is String && RegExp(r'^[a-fA-F0-9-]{36}$').hasMatch(cover)
            ? 'https://resources.tidal.com/images/${cover.replaceAll('-', '/')}/640x640.jpg'
            : null);
    final duration = data['duration'];
    return Track(
      id: 'monochrome:$shareId',
      uri: Uri.parse(native ? '$tracksBase/track/$clean' : 'https://monochrome.st/track/$shareId'),
      sourceUrl: 'https://monochrome.st/track/$shareId',
      title: title,
      artist: artist == null || artist.isEmpty ? Track.unknownArtist : artist,
      album: album is Map ? SongSource.text(album['title']) : SongSource.text(data['albumTitle']),
      artworkUrl: coverUrl,
      duration: duration is num && duration > 0
          ? Duration(milliseconds: (native && duration > 1000 ? duration : duration * 1000).round())
          : null,
      tagged: true,
    );
  }

  static List<Track> _tracks(dynamic items, {bool native = false}) => items is List
      ? [
          for (final item in items)
            if (item is Map) ?track(item['item'] is Map ? item['item'] : item, native: native),
        ]
      : [];

  @override
  Future<List<Track>> search(String query, {int limit = 12}) async {
    if (query.trim().isEmpty || limit <= 0) return [];
    final data = await _json(tracksBase, '/search/tracks', {'q': query.trim(), 'limit': '${limit.clamp(1, 100)}'});
    if (data is! Map || data['tracks'] is! List) throw const FormatException('Invalid Monochrome search');
    return _tracks(data['tracks'], native: true).take(limit).toList();
  }

  Future<MonochromeCollection> resolve(MonochromeLink link) async {
    if (link.kind == 'userplaylist') {
      final data = await _json('https://auth.monochrome.st', '/api/public/playlists/${Uri.encodeComponent(link.id)}');
      if (data is! Map) throw const FormatException('Invalid Monochrome playlist');
      var items = data['tracks'];
      if (items is String) items = jsonDecode(items);
      if (items is List) {
        items = [
          for (final item in items)
            if (item is Map) item['metadata'] is Map ? {...item['metadata'] as Map, 'id': item['item_id']} : item,
        ];
      }
      return MonochromeCollection(SongSource.text(data['name'] ?? data['title']) ?? name, _tracks(items));
    }
    if (_native(link.id)) {
      final id = _clean(link.id);
      if (link.kind == 'track') {
        // The native API has no metadata-by-id endpoint; the website uses the same stub.
        final t = track({'id': id, 'title': 'Monochrome · $id'}, native: true)!;
        return MonochromeCollection(t.title, [t]);
      }
      if (link.kind == 'album') {
        final data = await _json(tracksBase, '/releases/${Uri.encodeComponent(id)}');
        if (data is! Map || data['tracks'] is! List) throw const FormatException('Invalid Monochrome album');
        return MonochromeCollection(
          SongSource.text(data['title']) ?? name,
          _tracks([
            for (final t in data['tracks'])
              if (t is Map) {...t, 'albumTitle': data['title'], 'artwork': t['artwork'] ?? data['artwork']},
          ], native: true),
        );
      }
    }
    if (link.kind == 'track') {
      final data = await _json(hifiBase, '/info/', {'id': link.id});
      final entries = data is List ? data : [data];
      final found = _tracks(entries);
      if (found.isEmpty) throw const FormatException('Monochrome track unavailable');
      return MonochromeCollection(found.first.title, found);
    }
    final kind = link.kind == 'album' ? 'album' : 'playlist';
    final result = <Track>[];
    var title = name;
    var offset = 0;
    int? total;
    while (offset < 10000) {
      final data = await _json(hifiBase, '/$kind/', {'id': link.id, 'offset': '$offset'});
      final entries = data is List ? data : [data];
      List? items;
      for (final entry in entries) {
        if (entry is! Map) continue;
        final meta = entry[kind] is Map ? entry[kind] as Map : entry;
        title = SongSource.text(meta['title']) ?? title;
        if (meta['numberOfTracks'] is num) total = (meta['numberOfTracks'] as num).toInt();
        if (entry['items'] is List) items = entry['items'];
      }
      if (items == null) throw const FormatException('Invalid Monochrome collection');
      if (items.isEmpty) {
        if (total != null && offset < total) throw const FormatException('Incomplete Monochrome collection');
        break;
      }
      final page = _tracks(items);
      // A server ignoring offset must not duplicate the first page or silently import a partial list.
      if (offset > 0 && page.isNotEmpty && result.isNotEmpty && page.first.id == result.first.id) {
        throw const FormatException('Monochrome pagination unavailable');
      }
      result.addAll(page);
      offset += items.length;
      if (total == null || offset >= total) break;
    }
    if (total != null && offset < total) throw const FormatException('Monochrome collection too large');
    return MonochromeCollection(title, result);
  }

  /// Whether [stream] (an address or a DASH manifest from [manifest]) is lossless: a manifest that names FLAC, or
  /// a file that starts as one. Some songs are only on the service as AAC, which is no better than YouTube's own.
  Future<bool> lossless(String stream) async {
    if (stream.trimLeft().startsWith('<')) {
      final codecs = RegExp(
        r'codecs="([^"]*)"',
        caseSensitive: false,
      ).allMatches(stream).map((m) => m[1]!.toLowerCase());
      return codecs.isNotEmpty && codecs.every((c) => c.contains('flac') || c.contains('alac'));
    }
    final url = Uri.tryParse(stream);
    if (url == null || !url.hasScheme) return false;
    // The first bytes of the download the song will play from: no request of its own.
    final download = MergedDownload.of(stream, client: client);
    final head = await download.head(4).timeout(const Duration(seconds: 20));
    final flac = head.length >= 4 && String.fromCharCodes(head.take(4)) == 'fLaC';
    if (!flac) download.dispose();
    return flac;
  }

  /// Legacy HiFi shares resolve to a fresh direct URL or a DASH manifest.
  Future<String> manifest(String id) async {
    final data = await _json(hifiBase, '/track/', {'id': id, 'quality': 'LOSSLESS'});
    final entries = data is List ? data : [data];
    for (final entry in entries) {
      if (entry is! Map || entry['manifest'] is! String) continue;
      final decoded = utf8.decode(base64Decode(entry['manifest']));
      if (decoded.trimLeft().startsWith('<')) return decoded;
      final json = jsonDecode(decoded);
      final urls = json is Map ? json['urls'] : null;
      if (urls is List && urls.isNotEmpty) {
        if (SongSource.webUrl(urls.first) case final url?) return url;
      }
    }
    throw const FormatException('Monochrome stream unavailable');
  }
}

/// One connection pool for every Monochrome request, opened on the first one: not when Smart merge or a test merely
/// creates [Monochrome.instance]. Shared, so it is never closed.
class _SharedClient extends http.BaseClient {
  http.Client? _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => (_inner ??= http.Client()).send(request);

  @override
  void close() {}
}

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/track.dart';

/// One recording on the Internet Archive that has FLAC files: a concert of the Live Music Archive, a netlabel
/// album, a public-domain record.
@immutable
class ArchiveItem {
  const ArchiveItem({required this.id, required this.title, required this.creator, this.year});

  /// The item's identifier (`archive.org/details/<id>`).
  final String id;
  final String title;
  final String creator;
  final int? year;

  Uri get page => Uri.https('archive.org', '/details/$id');
  String get artworkUrl => 'https://archive.org/services/img/$id';

  /// A stand-in for cards: the item's cover and names.
  Track get cover => Track(
    id: '${InternetArchive.prefix}$id',
    uri: page,
    title: title,
    artist: creator,
    album: title,
    artworkUrl: artworkUrl,
  );

  @override
  bool operator ==(Object other) => other is ArchiveItem && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// The Internet Archive (archive.org), its two curated music collections only: the Live Music Archive (`etree`:
/// concerts of bands that allow taping and sharing) and Netlabels (labels releasing under free licenses). Anyone
/// can upload to the rest of the archive and label it as they like (paid voice packs and CD rips sit there marked
/// Creative Commons), so it is left out. Its public search and metadata APIs need no account or key. A song plays straight from
/// `archive.org/download/…` (mpv streams it as it would any FLAC on the web).
class InternetArchive {
  InternetArchive({this.client});

  static final instance = InternetArchive();

  /// Ids of songs and items from here start with this.
  static const prefix = 'ia:';

  /// Tests answer for archive.org.
  final http.Client? client;

  Future<http.Response> _get(Uri url) =>
      (client?.get ?? http.get)(url, headers: const {'User-Agent': 'Riflay'}).timeout(const Duration(seconds: 20));

  /// What Lucene would read as syntax, taken out of what was typed.
  static String _clean(String query) =>
      query.replaceAll(RegExp(r'[():"\[\]{}^~*?\\/!+\-&|]'), ' ').trim().replaceAll(RegExp(r'\s+'), ' ');

  /// Recordings matching [query] that hold FLAC files, the most downloaded first.
  Future<List<ArchiveItem>> search(String query, {int rows = 12}) async {
    final q = _clean(query);
    if (q.isEmpty) return const [];
    final url = Uri.https('archive.org', '/advancedsearch.php', {
      'q': '($q) AND mediatype:(audio OR etree) AND format:(Flac OR "24bit Flac") AND collection:(etree OR netlabels)',
      'fl[]': ['identifier', 'title', 'creator', 'year'],
      'sort[]': 'downloads desc',
      'rows': '$rows',
      'output': 'json',
    });
    final r = await _get(url);
    if (r.statusCode != 200) throw http.ClientException('Internet Archive search: HTTP ${r.statusCode}', url);
    return parseSearch(r.body);
  }

  @visibleForTesting
  static List<ArchiveItem> parseSearch(String body) {
    final docs = ((jsonDecode(body) as Map)['response'] as Map?)?['docs'] as List? ?? const [];
    String text(Object? v) => switch (v) {
      final List l => l.map((e) => '$e').join(', '),
      null => '',
      final v => '$v',
    };
    return [
      for (final d in docs.cast<Map>())
        if (text(d['identifier']).isNotEmpty)
          ArchiveItem(
            id: text(d['identifier']),
            title: text(d['title']).isEmpty ? text(d['identifier']) : text(d['title']),
            creator: text(d['creator']),
            year: int.tryParse(text(d['year']).split(RegExp(r'\D')).first),
          ),
    ];
  }

  /// [item]'s FLAC songs, in order. Files the item keeps private (some soundboard tapes stream only on the site)
  /// are left out.
  Future<List<Track>> tracks(ArchiveItem item) async {
    final url = Uri.https('archive.org', '/metadata/${item.id}');
    final r = await _get(url);
    if (r.statusCode != 200) throw http.ClientException('Internet Archive item: HTTP ${r.statusCode}', url);
    return parseFiles(item, jsonDecode(r.body) as Map);
  }

  /// "312.45" or "05:12" (or "1:02:03") as a length.
  static Duration? _length(Object? v) {
    final s = '${v ?? ''}';
    if (s.contains(':')) {
      var seconds = 0.0;
      for (final part in s.split(':')) {
        seconds = seconds * 60 + (double.tryParse(part) ?? 0);
      }
      return Duration(milliseconds: (seconds * 1000).round());
    }
    final seconds = double.tryParse(s);
    return seconds == null ? null : Duration(milliseconds: (seconds * 1000).round());
  }

  @visibleForTesting
  static List<Track> parseFiles(ArchiveItem item, Map json) {
    final meta = json['metadata'] as Map? ?? const {};
    if ('${meta['access-restricted-item']}' == 'true') return const [];
    final album = '${meta['title'] ?? item.title}';
    final creator = switch (meta['creator']) {
      final List l => l.join(', '),
      null => item.creator,
      final c => '$c',
    };
    final files = [
      for (final f in (json['files'] as List? ?? const []).cast<Map>())
        if (const {'Flac', '24bit Flac'}.contains(f['format']) && '${f['private']}' != 'true') f,
    ];
    int? number(Map f) => int.tryParse('${f['track'] ?? ''}'.split('/').first.trim());
    // Untagged files are named for their song after what every name of the item starts with ("Album_01_Song").
    final names = [
      for (final f in files) '${f['name']}'.split('/').last.replaceAll(RegExp(r'\.flac$', caseSensitive: false), ''),
    ];
    var shared = names.length < 2
        ? 0
        : names.reduce((a, b) {
            var i = 0;
            while (i < a.length && i < b.length && a[i] == b[i]) {
              i++;
            }
            return a.substring(0, i);
          }).length;
    // Back to a word boundary, so "Track 1" and "Track 12" keep their numbers.
    while (shared > 0 && names.isNotEmpty && !RegExp(r'[\s_\-.~～]').hasMatch(names.first[shared - 1])) {
      shared--;
    }
    String fallback(String name) {
      final base = name.split('/').last.replaceAll(RegExp(r'\.flac$', caseSensitive: false), '');
      final rest = base.length > shared ? base.substring(shared) : base;
      return rest.replaceAll('_', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    }

    files.sort((a, b) {
      final (x, y) = (number(a), number(b));
      if (x != null && y != null && x != y) return x.compareTo(y);
      return '${a['name']}'.compareTo('${b['name']}');
    });
    return [
      for (final f in files)
        () {
          final name = '${f['name']}';
          return Track(
            id: '$prefix${item.id}/$name',
            uri: Uri.https('archive.org', '/download/${item.id}/$name'),
            title: '${f['title'] ?? ''}'.trim().isEmpty ? fallback(name) : '${f['title']}'.trim(),
            artist: '${f['creator'] ?? f['artist'] ?? ''}'.trim().isEmpty ? creator : '${f['creator'] ?? f['artist']}',
            album: album,
            duration: _length(f['length']),
            trackNumber: number(f),
            sourceUrl: item.page.toString(),
            artworkUrl: item.artworkUrl,
          );
        }(),
    ];
  }
}

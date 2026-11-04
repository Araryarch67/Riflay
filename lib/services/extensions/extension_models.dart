import 'dart:convert';

import '../../models/track.dart';
import '../playlist_transfer.dart' show ForeignSong;

/// SpotiFLAC's extension format, as its registries and `.sflx` packages describe it.
///
/// A registry is a `registry.json` listing packages; a package is a ZIP holding `manifest.json` and `index.js`, a
/// plain (ES5/ES2015) script that calls the host's synchronous `http`, `storage`, `log` and `utils` objects and hands
/// its entry points to `registerExtension({...})`.

/// A repository the user added: where its `registry.json` is.
const officialRegistry = 'https://raw.githubusercontent.com/mornyeapp/Mornye-Extension/main/registry.json';
const communityRegistry = 'https://raw.githubusercontent.com/zarzet/spotiflac-extension/main/registry.json';

/// The repositories offered before any is added (the user still adds each one).
const suggestedRegistries = [
  (name: 'Mornye (official)', url: officialRegistry),
  (name: 'zarzet (community)', url: communityRegistry),
];

/// An id used as a folder name: lower case letters, digits, dots, dashes and underscores.
final _safeId = RegExp(r'^[a-z0-9][a-z0-9._-]{0,63}$');

bool isSafeExtensionId(String id) => _safeId.hasMatch(id) && !id.contains('..');

/// One package a registry offers.
class RegistryEntry {
  const RegistryEntry({
    required this.id,
    required this.displayName,
    required this.version,
    required this.downloadUrl,
    this.description = '',
    this.sha256,
    this.category = '',
    this.tags = const [],
    this.iconUrl,
    this.minAppVersion,
    this.registry = '',
  });

  final String id;
  final String displayName;
  final String version;
  final String description;
  final Uri downloadUrl;

  /// Lower-case hex; when given, the download must match it.
  final String? sha256;

  /// "download", "integration", "lyrics"…
  final String category;
  final List<String> tags;
  final String? iconUrl;

  /// The SpotiFLAC version it was written for (Riflay's own version is unrelated, so this is shown, not enforced).
  final String? minAppVersion;

  /// The registry URL it came from.
  final String registry;

  static RegistryEntry? tryParse(Object? json, {String registry = ''}) {
    if (json is! Map) return null;
    final id = json['id'] ?? json['name'];
    final version = json['version'];
    final url = Uri.tryParse('${json['download_url'] ?? json['downloadUrl'] ?? ''}');
    if (id is! String || !isSafeExtensionId(id) || version is! String || url == null) return null;
    if (url.scheme != 'https' && url.scheme != 'http') return null;
    final sha = json['sha256'];
    return RegistryEntry(
      id: id,
      displayName: _string(json['display_name'] ?? json['displayName']) ?? id,
      version: version,
      downloadUrl: url,
      description: _string(json['description']) ?? '',
      sha256: sha is String && RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(sha) ? sha.toLowerCase() : null,
      category: _string(json['category']) ?? '',
      tags: [
        for (final t in json['tags'] is List ? json['tags'] as List : const [])
          if (t is String) t,
      ],
      iconUrl: _string(json['icon_url'] ?? json['iconUrl']),
      minAppVersion: _string(json['min_app_version'] ?? json['minAppVersion']),
      registry: registry,
    );
  }
}

/// A parsed `registry.json`: `{"version": 1, "extensions": [...]}`. Entries that can't be used are skipped.
class ExtensionRegistry {
  const ExtensionRegistry({required this.url, required this.entries, this.updatedAt});

  final String url;
  final List<RegistryEntry> entries;
  final DateTime? updatedAt;

  /// Throws [FormatException] when [body] isn't a registry at all.
  factory ExtensionRegistry.parse(String body, {required String url}) {
    final Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException {
      throw const FormatException('Not a registry: the file isn\'t JSON');
    }
    final list = switch (json) {
      {'extensions': final List l} => l,
      final List l => l,
      _ => throw const FormatException('Not a registry: no "extensions" list'),
    };
    final seen = <String>{};
    return ExtensionRegistry(
      url: url,
      updatedAt: json is Map ? DateTime.tryParse('${json['updated_at']}') : null,
      entries: [
        for (final e in list)
          if (RegistryEntry.tryParse(e, registry: url) case final entry? when seen.add(entry.id)) entry,
      ],
    );
  }
}

/// A setting the extension asks the user for (`manifest.settings`).
class ExtensionSetting {
  const ExtensionSetting({required this.key, required this.label, this.type = 'string', this.defaultValue});

  final String key;
  final String label;
  final String type;
  final Object? defaultValue;
}

/// An installed package's `manifest.json`.
class ExtensionManifest {
  const ExtensionManifest({
    required this.id,
    required this.displayName,
    required this.version,
    this.description = '',
    this.types = const [],
    this.networkHosts = const [],
    this.searchEnabled = false,
    this.searchPlaceholder,
    this.requiredRuntimeFeatures = const [],
    this.settings = const [],
    this.networkTimeout = const Duration(seconds: 20),
  });

  /// `name` in the manifest, the same as the registry's `id`.
  final String id;
  final String displayName;
  final String version;
  final String description;

  /// "metadata_provider", "download_provider", "lyrics_provider".
  final List<String> types;

  /// `permissions.network`: the only hosts its requests may reach ("api.example.com", "*.example.com").
  final List<String> networkHosts;
  final bool searchEnabled;
  final String? searchPlaceholder;

  /// SpotiFLAC runtime features it needs ("signedSession@1"…); Riflay has none of them yet.
  final List<String> requiredRuntimeFeatures;
  final List<ExtensionSetting> settings;
  final Duration networkTimeout;

  bool get isMetadataProvider => types.contains('metadata_provider');
  bool get isDownloadProvider => types.contains('download_provider');
  bool get isLyricsProvider => types.contains('lyrics_provider');

  /// Whether Riflay can ask it for songs: it says it searches.
  bool get canSearch => searchEnabled || isMetadataProvider;

  /// Throws [FormatException] when [body] isn't a usable manifest.
  factory ExtensionManifest.parse(String body) {
    final Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException {
      throw const FormatException('manifest.json isn\'t JSON');
    }
    if (json is! Map) throw const FormatException('manifest.json isn\'t an object');
    final id = json['name'] ?? json['id'];
    final version = json['version'];
    if (id is! String || !isSafeExtensionId(id)) throw const FormatException('manifest.json has no usable name');
    if (version is! String) throw const FormatException('manifest.json has no version');
    final type = json['type'];
    final permissions = json['permissions'];
    final search = json['searchBehavior'];
    final capabilities = json['capabilities'];
    final timeout = capabilities is Map ? capabilities['networkTimeoutSeconds'] : null;
    return ExtensionManifest(
      id: id,
      displayName: _string(json['displayName'] ?? json['display_name']) ?? id,
      version: version,
      description: _string(json['description']) ?? '',
      types: [
        if (type is String) type,
        if (type is List)
          for (final t in type)
            if (t is String) t,
      ],
      networkHosts: [
        if (permissions is Map && permissions['network'] is List)
          for (final h in permissions['network'] as List)
            if (h is String && h.trim().isNotEmpty) h.trim().toLowerCase(),
      ],
      searchEnabled: search is Map && search['enabled'] == true,
      searchPlaceholder: search is Map ? _string(search['placeholder']) : null,
      requiredRuntimeFeatures: [
        if (json['requiredRuntimeFeatures'] is List)
          for (final f in json['requiredRuntimeFeatures'] as List)
            if (f is String) f,
      ],
      settings: [
        if (json['settings'] is List)
          for (final s in json['settings'] as List)
            if (s is Map && s['key'] is String)
              ExtensionSetting(
                key: s['key'] as String,
                label: _string(s['label']) ?? s['key'] as String,
                type: _string(s['type']) ?? 'string',
                defaultValue: s['default'],
              ),
      ],
      networkTimeout: timeout is num && timeout > 0 ? Duration(seconds: timeout.clamp(1, 120).toInt()) : const Duration(seconds: 20),
    );
  }

  /// Whether a request to [url] is allowed by [networkHosts]. An extension that lists none may reach nothing.
  bool allows(Uri url) {
    if (url.scheme != 'https' && url.scheme != 'http') return false;
    final host = url.host.toLowerCase();
    for (final pattern in networkHosts) {
      if (pattern == '*') return true;
      if (pattern.startsWith('*.')) {
        final base = pattern.substring(2);
        if (host == base || host.endsWith('.$base')) return true;
      } else if (host == pattern) {
        return true;
      }
    }
    return false;
  }

  /// The settings' defaults, given to `initialize(config)`.
  Map<String, Object?> get defaultConfig => {
    for (final s in settings)
      if (s.defaultValue != null) s.key: s.defaultValue,
  };
}

/// One search result from an extension's `customSearch` / `searchTracks`.
class ExtensionSearchHit {
  const ExtensionSearchHit({
    required this.id,
    required this.title,
    required this.artist,
    required this.extensionId,
    this.album,
    this.duration,
    this.coverUrl,
    this.kind = 'track',
    this.isrc,
  });

  final String id;
  final String title;

  /// All of its artists, comma separated.
  final String artist;
  final String? album;
  final Duration? duration;
  final String? coverUrl;

  /// "track", "album", "artist" or "playlist".
  final String kind;
  final String? isrc;
  final String extensionId;

  bool get isTrack => kind == 'track';

  static ExtensionSearchHit? tryParse(Object? json, {required String extensionId}) {
    if (json is! Map) return null;
    final id = json['id'];
    final title = _string(json['name'] ?? json['title']);
    if (id == null || title == null) return null;
    final artists = json['artists'] ?? json['artist'];
    final ms = json['duration_ms'] ?? json['durationMs'];
    final cover = json['cover_url'] ?? json['images'] ?? json['coverUrl'];
    return ExtensionSearchHit(
      id: '$id',
      title: title,
      artist: switch (artists) {
        final String s => s,
        final List l => l
            .map((a) => a is Map ? '${a['name'] ?? ''}' : '$a')
            .where((a) => a.isNotEmpty)
            .join(', '),
        _ => '',
      },
      album: _string(json['album_name'] ?? json['album']),
      duration: ms is num && ms > 0 ? Duration(milliseconds: ms.toInt()) : null,
      coverUrl: switch (cover) {
        final String s when s.startsWith('http') => s,
        final List l when l.isNotEmpty && l.first is String => l.first as String,
        _ => null,
      },
      kind: _string(json['item_type'] ?? json['type']) ?? 'track',
      isrc: _string(json['isrc']),
      extensionId: extensionId,
    );
  }

  /// A search reply: a list of hits, or `{tracks: [...]}` / `{results: [...]}`.
  static List<ExtensionSearchHit> parseList(Object? json, {required String extensionId}) {
    final list = switch (json) {
      final List l => l,
      {'tracks': final List l} => l,
      {'results': final List l} => l,
      {'items': final List l} => l,
      _ => const [],
    };
    return [
      for (final e in list) ?tryParse(e, extensionId: extensionId),
    ];
  }

  /// The song as another service lists it, to be found in YouTube Music.
  ForeignSong get foreign => ForeignSong(title: title, artist: artist, duration: duration);

  /// A placeholder row for the song (no stream of its own): its cover, names and length.
  Track get previewTrack => Track(
    id: 'ext:$extensionId:$id',
    uri: Uri.parse('riflay-extension://$extensionId/$id'),
    title: title,
    artist: artist.isEmpty ? Track.unknownArtist : artist,
    album: album,
    duration: duration,
    artworkUrl: coverUrl,
    tagged: true,
  );
}

/// Compares dotted versions ("1.10.6" > "1.9.0"); non-numeric parts compare as text.
int compareVersions(String a, String b) {
  final x = a.split(RegExp(r'[.+-]')), y = b.split(RegExp(r'[.+-]'));
  for (var i = 0; i < x.length || i < y.length; i++) {
    final p = i < x.length ? x[i] : '0', q = i < y.length ? y[i] : '0';
    final n = int.tryParse(p), m = int.tryParse(q);
    final c = n != null && m != null ? n.compareTo(m) : p.compareTo(q);
    if (c != 0) return c;
  }
  return 0;
}

String? _string(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;

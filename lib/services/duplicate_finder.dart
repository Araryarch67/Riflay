import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../models/track.dart';
import 'flac_convert.dart';

/// Songs that are the same recording in more than one file: a FLAC and an MP3 of it, a YouTube download and
/// the file the person already had. Everything here is a pure rule over a list of songs (sizes come in as
/// numbers), so it can be tested without files.

const _lossless = {'flac', 'wav', 'aiff', 'aif', 'aifc', 'wv', 'ape', 'tta', 'dsf', 'dff', 'caf', 'w64'};

/// How much more sound a lossy codec fits in the same bitrate than MP3 does (Opus at 128 kbps is about MP3 at 192).
double _codecFactor(String ext) => switch (ext) {
  'opus' => 1.5,
  'ogg' || 'oga' || 'webm' => 1.3,
  'm4a' || 'aac' || 'm4b' || 'mka' => 1.25,
  _ => 1.0,
};

// ── Matching titles and artists ─────────────────────────────────────────────────────────────────────────────

const _accents = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a', 'ç': 'c', 'è': 'e', 'é': 'e', 'ê': 'e', //
  'ë': 'e', 'ē': 'e', 'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i', 'ñ': 'n', 'ò': 'o', 'ó': 'o', 'ô': 'o',
  'õ': 'o', 'ö': 'o', 'ø': 'o', 'ō': 'o', 'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u', 'ý': 'y', 'ÿ': 'y',
  'ß': 'ss', 'æ': 'ae', 'œ': 'oe', 'ł': 'l', 'š': 's', 'ž': 'z', 'č': 'c',
};

String _plain(String s) {
  final b = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    final c = String.fromCharCode(r);
    b.write(_accents[c] ?? c);
  }
  return b.toString();
}

/// Words that describe the upload, not the song: "(Official Video)", "[Lyrics]", "- Topic". Things that make a
/// different recording ("Live", "Remix", "Acoustic", "Instrumental", "Demo") are deliberately not here.
final _noise = RegExp(
  r'^(official( music)?( video| audio| lyric video| visualizer| mv)?|lyrics?( video)?|lyric video|audio( only)?|'
  r'video|music video|mv|m/v|hd|hq|4k|1080p|visuali[sz]er|explicit|full song|remaster(ed)?( \d{4})?|'
  r'\d{4} remaster(ed)?|topic)$',
);

final _bracket = RegExp(r'[\(\[\{]([^\)\]\}]*)[\)\]\}]');
final _featuring = RegExp(r'\b(feat|ft|featuring)\b\.?.*$');

String _squash(String s) => s
    .replaceAll(RegExp("['\u2019\u2018`\u00b4]"), '') // "Don't" is "dont", not "don t"
    .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String _stripNoise(String s) {
  var out = s.replaceAllMapped(_bracket, (m) {
    final inside = _squash(m[1]!.replaceAll('/', ''));
    final raw = m[1]!.trim();
    // "(feat. X)" is a credit, not part of the title.
    if (_noise.hasMatch(inside) || _noise.hasMatch(raw) || _featuring.hasMatch(raw)) return ' ';
    return m[0]!;
  });
  // "Song - Official Video" / "Song | Lyrics"
  out = out.replaceAllMapped(RegExp(r'\s[-–—|]\s*([^-–—|]+)$'), (m) => _noise.hasMatch(_squash(m[1]!)) ? '' : m[0]!);
  return out;
}

/// A title as compared: lower case, no accents, no punctuation, no upload noise and no featured artist.
/// [artist] lets "Artist - Title" uploads (a YouTube title that repeats the channel) match the plain title.
String normalizeTitle(String title, {String artist = ''}) {
  var t = _plain(title).trim();
  final a = _plain(artist).trim();
  if (a.isNotEmpty && a != _plain(Track.unknownArtist)) {
    for (final dash in const [' - ', ' – ', ' — ']) {
      if (t.startsWith('$a$dash')) t = t.substring(a.length + dash.length);
    }
  }
  t = _stripNoise(t);
  t = t.replaceAll('&', ' and ').replaceAll(_featuring, '');
  return _squash(t);
}

/// The main artist as compared: "Artist - Topic", "ArtistVEVO", "A feat. B", "A & B" all become "a" / "artist".
String normalizeArtist(String artist) {
  var a = _plain(artist);
  a = a.replaceAll(_featuring, '');
  a = a.split(RegExp(r'\s*(,|&|/|;|\bx\b|\band\b|\bwith\b)\s*')).first;
  a = a
      .replaceAll(RegExp(r'\s*-\s*topic$'), '')
      .replaceAll(RegExp(r'vevo$'), '')
      .replaceAll(RegExp(r'\s+official$'), '');
  return _squash(a);
}

bool _unknownArtist(String normalized) => normalized.isEmpty || normalized == normalizeArtist(Track.unknownArtist);

// ── One song of a group ─────────────────────────────────────────────────────────────────────────────────────

/// A song with what it takes to compare it: its file's size and where it came from.
class DuplicateItem {
  const DuplicateItem({required this.track, required this.bytes, required this.madeByRiflay});

  /// Reads the file facts of [track]. [bytes] is the file's size (null: not known / not readable);
  /// [downloadsDir] tells a download Riflay made from a file the person added.
  factory DuplicateItem.of(Track track, {int? bytes, String? downloadsDir}) => DuplicateItem(
    track: track,
    bytes: bytes,
    madeByRiflay: downloadsDir == null ? track.sourceUrl != null : FlacConvert.replacesOriginal(track, downloadsDir),
  );

  final Track track;
  final int? bytes;

  /// A download Riflay saved (a YouTube song), as opposed to a file the person put there.
  final bool madeByRiflay;

  String get path => track.path ?? '';

  String get extension => p.extension(path).replaceFirst('.', '').toLowerCase();

  /// "FLAC", "MP3", "M4A"…
  String get format => extension.toUpperCase();

  bool get isLossless => _lossless.contains(extension);

  /// Average bitrate worked out from the file's size and the song's length (tags and cover included).
  int? get kbps {
    final seconds = track.duration?.inMilliseconds;
    final size = bytes;
    if (seconds == null || seconds <= 0 || size == null) return null;
    return (size * 8 / seconds).round(); // bits / ms == kbit / s
  }

  /// How much of the usual tags the song has (title always): artist, album, track number and "read from the file".
  int get tagScore =>
      (track.tagged ? 1 : 0) +
      (track.artist != Track.unknownArtist ? 1 : 0) +
      (track.album != null ? 1 : 0) +
      (track.trackNumber != null ? 1 : 0) +
      (track.artworkUrl != null ? 1 : 0);

  /// What the sound is worth for comparing lossy files with each other (Opus 128 kbps ~ MP3 192).
  double get effectiveKbps => (kbps ?? 0) * _codecFactor(extension);

  /// "FLAC, lossless" or "MP3, 320 kbps".
  String get qualityLabel {
    if (isLossless) return '$format, lossless';
    final k = kbps;
    return k == null ? format : '$format, about $k kbps';
  }
}

/// Which of two copies is the better one to keep: negative when [a] is. Lossless first, then more sound per
/// second (within a small step), then fuller tags, then a file the person added over a download Riflay made
/// (a download can be fetched again), then the bigger file, then the older entry.
int compareQuality(DuplicateItem a, DuplicateItem b) {
  if (a.isLossless != b.isLossless) return a.isLossless ? -1 : 1;
  // Lossless: a bigger file is a deeper bit depth or rate; lossy: weigh the codec. Steps of 16 kbps count as equal.
  int step(DuplicateItem i) => ((i.isLossless ? (i.kbps ?? 0).toDouble() : i.effectiveKbps) / 16).round();
  final byQuality = step(b).compareTo(step(a));
  if (byQuality != 0) return byQuality;
  final byTags = b.tagScore.compareTo(a.tagScore);
  if (byTags != 0) return byTags;
  if (a.madeByRiflay != b.madeByRiflay) return a.madeByRiflay ? 1 : -1;
  final bySize = (b.bytes ?? 0).compareTo(a.bytes ?? 0);
  if (bySize != 0) return bySize;
  final byAge = a.track.addedAt.compareTo(b.track.addedAt);
  return byAge != 0 ? byAge : a.track.id.compareTo(b.track.id);
}

/// The same recording in two or more files, best copy first.
class DuplicateGroup {
  const DuplicateGroup(this.items);

  /// Best first: [best] is the one to keep unless the person picks another.
  final List<DuplicateItem> items;

  DuplicateItem get best => items.first;

  String get title => best.track.title;
  String get artist => best.track.artist;
}

// ── Finding groups ──────────────────────────────────────────────────────────────────────────────────────────

/// Songs worth comparing: a file of its own with a known length. Slices of a cue sheet, SACD songs and
/// streamed-only songs are not separate files.
bool canCompare(Track t) =>
    t.path != null && !t.isRemote && !t.isCueTrack && t.id == t.uri.toString() && (t.duration?.inMilliseconds ?? 0) > 0;

/// Groups [items] that are the same recording: the same normalized title and main artist, lengths within
/// [tolerance]. With [matchAlbum] two copies that both name an album must name the same one. A song with no
/// artist joins a group only when exactly one artist's songs fit (and its title is long enough not to be "Intro").
List<DuplicateGroup> findDuplicates(
  Iterable<DuplicateItem> items, {
  bool matchAlbum = false,
  Duration tolerance = const Duration(seconds: 2),
}) {
  final all = items.where((i) => canCompare(i.track)).toList();
  final titles = [for (final i in all) normalizeTitle(i.track.title, artist: i.track.artist)];
  final artists = [for (final i in all) normalizeArtist(i.track.artist)];
  final albums = [for (final i in all) i.track.album == null ? '' : normalizeTitle(i.track.album!)];

  final byTitle = <String, List<int>>{};
  for (var n = 0; n < all.length; n++) {
    if (titles[n].isEmpty) continue;
    byTitle.putIfAbsent(titles[n], () => []).add(n);
  }

  final parent = List<int>.generate(all.length, (i) => i);
  int find(int i) => parent[i] == i ? i : parent[i] = find(parent[i]);
  void union(int a, int b) => parent[find(a)] = find(b);

  bool near(int a, int b) =>
      (all[a].track.duration! - all[b].track.duration!).abs() <= tolerance &&
      (!matchAlbum || albums[a].isEmpty || albums[b].isEmpty || albums[a] == albums[b]);

  for (final entry in byTitle.entries) {
    final ids = entry.value;
    if (ids.length < 2) continue;
    final known = [
      for (final n in ids)
        if (!_unknownArtist(artists[n])) n,
    ];
    final unknown = [
      for (final n in ids)
        if (_unknownArtist(artists[n])) n,
    ];
    for (var i = 0; i < known.length; i++) {
      for (var j = i + 1; j < known.length; j++) {
        if (artists[known[i]] == artists[known[j]] && near(known[i], known[j])) union(known[i], known[j]);
      }
    }
    if (entry.key.length < 8 && unknown.isNotEmpty) {
      // "Intro", "Home": too common to say a file without an artist is the same song as one with an artist.
      for (var i = 0; i < unknown.length; i++) {
        for (var j = i + 1; j < unknown.length; j++) {
          if (near(unknown[i], unknown[j])) union(unknown[i], unknown[j]);
        }
      }
      continue;
    }
    for (final u in unknown) {
      final roots = {
        for (final k in known)
          if (near(u, k)) find(k),
      };
      if (roots.length == 1) {
        union(u, roots.single);
      } else if (roots.isEmpty) {
        for (final other in unknown) {
          if (other != u && near(u, other)) union(u, other);
        }
      }
    }
  }

  final groups = <int, List<DuplicateItem>>{};
  for (var n = 0; n < all.length; n++) {
    groups.putIfAbsent(find(n), () => []).add(all[n]);
  }
  return [
    for (final g in groups.values)
      if (g.length > 1) DuplicateGroup(g..sort(compareQuality)),
  ]..sort((a, b) {
    final byTitle = a.title.toLowerCase().compareTo(b.title.toLowerCase());
    return byTitle != 0 ? byTitle : a.best.track.id.compareTo(b.best.track.id);
  });
}

/// File sizes, read on a background isolate. A path that can't be read has no entry.
Future<Map<String, int>> readFileSizes(Iterable<String> paths) {
  final list = paths.toList();
  return Isolate.run(() {
    final sizes = <String, int>{};
    for (final path in list) {
      try {
        sizes[path] = File(path).lengthSync();
      } on FileSystemException {
        // missing: no entry
      }
    }
    return sizes;
  });
}

// ── Removing the extra copies ───────────────────────────────────────────────────────────────────────────────

/// A group and the copy the person keeps.
class RemovalChoice {
  const RemovalChoice(this.group, this.keepId);

  final DuplicateGroup group;
  final String keepId;
}

/// What removing the extra copies will do, worked out before anything is touched.
class RemovalPlan {
  const RemovalPlan({
    required this.removeFromLibrary,
    required this.keptInstead,
    required this.filesToDelete,
    required this.bytesFreed,
    required this.skippedFiles,
  });

  /// Songs that leave the library.
  final List<Track> removeFromLibrary;

  /// Removed song id -> the copy kept in its place (playlists and history follow it).
  final Map<String, Track> keptInstead;

  /// Files that will be deleted (empty unless asked for).
  final List<DuplicateItem> filesToDelete;

  /// Space the deleted files free up.
  final int bytesFreed;

  /// Files that stay although the person asked to delete: another song of the library still uses them.
  final int skippedFiles;

  int get downloadsToDelete => filesToDelete.where((i) => i.madeByRiflay).length;
  int get ownFilesToDelete => filesToDelete.length - downloadsToDelete;

  bool get isEmpty => removeFromLibrary.isEmpty;
}

/// Works out what to remove for [choices]. The rules, which never bend:
/// - the copy kept in a group is never removed and its file is never deleted;
/// - a choice whose kept copy is not in its group is ignored;
/// - only files of songs the person marked can be deleted, and only when [deleteFiles] is on;
/// - a file that any other song of [library] (one not being removed) still plays from is never deleted;
/// - every file is deleted at most once.
RemovalPlan planRemoval(List<RemovalChoice> choices, {required bool deleteFiles, required Iterable<Track> library}) {
  final removing = <DuplicateItem>[];
  final keptPaths = <String>{};
  final replacement = <String, Track>{};
  for (final c in choices) {
    final keep = c.group.items.where((i) => i.track.id == c.keepId).firstOrNull;
    if (keep == null) continue;
    keptPaths.add(p.normalize(keep.path));
    for (final i in c.group.items) {
      if (i.track.id == keep.track.id) continue;
      removing.add(i);
      replacement[i.track.id] = keep.track;
    }
  }
  // A song that is the kept copy in one group can't be removed through another.
  final keptIds = {
    for (final c in choices)
      if (c.group.items.any((i) => i.track.id == c.keepId)) c.keepId,
  };
  removing.removeWhere((i) => keptIds.contains(i.track.id));
  final removeIds = {for (final i in removing) i.track.id};
  final stillUsed = {
    for (final t in library)
      if (t.path != null && !removeIds.contains(t.id)) p.normalize(t.path!),
  };

  final files = <DuplicateItem>[];
  final seen = <String>{};
  var skipped = 0;
  if (deleteFiles) {
    for (final i in removing) {
      final path = i.track.path;
      if (path == null) continue;
      final key = p.normalize(path);
      if (keptPaths.contains(key) || stillUsed.contains(key)) {
        skipped++;
        continue;
      }
      if (seen.add(key)) files.add(i);
    }
  }
  return RemovalPlan(
    removeFromLibrary: [for (final i in removing) i.track],
    keptInstead: {for (final i in removing) i.track.id: ?replacement[i.track.id]},
    filesToDelete: files,
    bytesFreed: files.fold(0, (sum, i) => sum + (i.bytes ?? 0)),
    skippedFiles: skipped,
  );
}

/// Deletes the files of [plan] (one by one; a file that can't be deleted is left). Returns how many went.
Future<({int deleted, int failed})> deletePlannedFiles(RemovalPlan plan) async {
  var deleted = 0;
  var failed = 0;
  for (final i in plan.filesToDelete) {
    final path = i.track.path;
    if (path == null) continue;
    try {
      if (FileSystemEntity.typeSync(path, followLinks: false) != FileSystemEntityType.file) continue;
      await File(path).delete();
      deleted++;
    } on FileSystemException {
      failed++;
    }
  }
  return (deleted: deleted, failed: failed);
}

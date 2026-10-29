import 'package:path/path.dart' as p;

import '../models/track.dart';
import 'play_history.dart';
import 'player_controller.dart';

/// The built-in, self-updating lists in Library. Worked out, never edited.
enum SmartList {
  mostPlayed('smart:most-played', 'Most played'),
  notPlayedForAWhile('smart:not-played', 'Not played for a while'),
  recentlyAdded('smart:recently-added', 'Recently added'),
  recentlyPlayed('smart:recently-played', 'Recently played'),
  lossless('smart:lossless', 'Lossless');

  const SmartList(this.id, this.title);
  final String id;
  final String title;

  static SmartList? byId(String? id) => values.where((l) => l.id == id).firstOrNull;
}

abstract final class SmartPlaylists {
  /// Songs per list at most.
  static const limit = 100;

  /// "Not played for a while": nothing heard or added for this long.
  static const stale = Duration(days: 90);

  /// Formats that keep every sample. An ALAC song inside an .m4a can't be told from AAC by its name, so only
  /// the `.alac` extension counts.
  static const losslessExtensions = {
    'flac',
    'alac',
    'wav',
    'w64',
    'aiff',
    'aif',
    'aifc',
    'wv',
    'ape',
    'tta',
    'caf',
    'dsf',
    'dff',
  };

  static bool isLossless(Track t) {
    final path = t.path;
    if (path == null || t.isRemote) return false;
    return losslessExtensions.contains(p.extension(path).replaceFirst('.', '').toLowerCase());
  }

  /// Every list that has songs, keyed by [SmartList], for [library] and [history] as of [now].
  static Map<SmartList, Collection> compute(List<Track> library, PlayHistory history, {DateTime? now}) {
    now ??= DateTime.now();
    final nowSec = now.millisecondsSinceEpoch ~/ 1000;
    final byId = {for (final t in library) t.id: t};
    Track trackFor(SongInfo s) => byId[s.key] ?? s.toTrack();

    final played = history.songs.toList();
    final lists = <SmartList, List<Track>>{
      SmartList.mostPlayed: [
        for (final (s, _, _)
            in (played.where((e) => e.$2 > 0).toList()..sort((a, b) {
                  final byPlays = b.$2.compareTo(a.$2);
                  return byPlays != 0 ? byPlays : b.$3.compareTo(a.$3);
                }))
                .take(limit))
          trackFor(s),
      ],
      SmartList.recentlyPlayed: [
        for (final (s, _, _) in (played.where((e) => e.$2 > 0).toList()..sort((a, b) => b.$3.compareTo(a.$3))).take(
          limit,
        ))
          trackFor(s),
      ],
      SmartList.notPlayedForAWhile: _notPlayed(library, history, nowSec),
      SmartList.recentlyAdded: [
        for (final t
            in (library.where((t) => t.addedAt > 0).toList()..sort((a, b) => b.addedAt.compareTo(a.addedAt))).take(
              limit,
            ))
          t,
      ],
      SmartList.lossless: [
        for (final t in library)
          if (isLossless(t)) t,
      ],
    };
    return {
      for (final e in lists.entries)
        if (e.value.isNotEmpty)
          e.key: Collection(
            kind: CollectionKind.smart,
            id: e.key.id,
            title: e.key.title,
            subtitle: '${e.value.length} ${e.value.length == 1 ? 'song' : 'songs'}',
            tracks: e.value,
          ),
    };
  }

  /// Library songs whose latest sign of life (last play, or when added) is over [stale] ago, the longest idle first.
  static List<Track> _notPlayed(List<Track> library, PlayHistory history, int nowSec) {
    final cutoff = nowSec - stale.inSeconds;
    final idle = <(Track, int)>[];
    for (final t in library) {
      final last = history.lastPlayedSec(t.id) ?? 0;
      final added = t.addedAt ~/ 1000;
      final seen = last > added ? last : added;
      if (seen < cutoff) idle.add((t, seen));
    }
    idle.sort((a, b) => a.$2.compareTo(b.$2));
    return [for (final e in idle) e.$1];
  }

  static (int, int, Map<SmartList, Collection>)? _cache;

  /// [compute] for the live app, redone only when the library, the history or the day changed.
  static Map<SmartList, Collection> of(PlayerController c, PlayHistory history) {
    final day = DateTime.now().millisecondsSinceEpoch ~/ 86400000;
    final key = Object.hash(c.libraryRevision.value, history.revision, day, identityHashCode(c));
    final cached = _cache;
    if (cached != null && cached.$1 == key && cached.$2 == history.revision) return cached.$3;
    final value = compute(c.library, history);
    _cache = (key, history.revision, value);
    return value;
  }
}

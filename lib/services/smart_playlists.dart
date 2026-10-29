import 'package:flutter/foundation.dart' show visibleForTesting;
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
  static Map<SmartList, Collection> compute(List<Track> library, PlayHistory history, {DateTime? now}) =>
      _build(library, history, now ?? DateTime.now(), {...SmartList.values});

  /// The lists named in [which].
  static Map<SmartList, Collection> _build(
    List<Track> library,
    PlayHistory? history,
    DateTime now,
    Set<SmartList> which,
  ) {
    final nowSec = now.millisecondsSinceEpoch ~/ 1000;
    final byId = which.contains(SmartList.mostPlayed) || which.contains(SmartList.recentlyPlayed)
        ? {for (final t in library) t.id: t}
        : const <String, Track>{};
    Track trackFor(SongInfo s) => byId[s.key] ?? s.toTrack();

    final played = history == null ? const <(SongInfo, int, int)>[] : history.songs.toList();
    final lists = <SmartList, List<Track>>{
      if (which.contains(SmartList.mostPlayed))
        SmartList.mostPlayed: [
          for (final (s, _, _)
              in (played.where((e) => e.$2 > 0).toList()..sort((a, b) {
                    final byPlays = b.$2.compareTo(a.$2);
                    return byPlays != 0 ? byPlays : b.$3.compareTo(a.$3);
                  }))
                  .take(limit))
            trackFor(s),
        ],
      if (which.contains(SmartList.recentlyPlayed))
        SmartList.recentlyPlayed: [
          for (final (s, _, _) in (played.where((e) => e.$2 > 0).toList()..sort((a, b) => b.$3.compareTo(a.$3))).take(
            limit,
          ))
            trackFor(s),
        ],
      if (which.contains(SmartList.notPlayedForAWhile) && history != null)
        SmartList.notPlayedForAWhile: _notPlayed(library, history, nowSec),
      if (which.contains(SmartList.recentlyAdded))
        SmartList.recentlyAdded: [
          for (final t
              in (library.where((t) => t.addedAt > 0).toList()..sort((a, b) => b.addedAt.compareTo(a.addedAt))).take(
                limit,
              ))
            t,
        ],
      if (which.contains(SmartList.lossless))
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

  /// How many times a list was worked out (tests count these to see cache hits).
  @visibleForTesting
  static int computations = 0;

  // Two caches: the lists made from the library alone (a play doesn't touch them) and the ones that also
  // read the listening history (a library change only swaps song versions, but they are cheap to redo).
  static (int, Map<SmartList, Collection>)? _libraryPart;
  static (int, Map<SmartList, Collection>)? _historyPart;
  static Map<SmartList, Collection>? _merged;
  static (int, int)? _mergedKey;

  /// [compute] for the live app, redone only when the library, the history or the day changed. A play redoes
  /// only the lists that read the history; lists whose songs came out the same are handed back as they were,
  /// so what shows them can tell nothing changed.
  static Map<SmartList, Collection> of(PlayerController c, PlayHistory history) {
    final day = DateTime.now().millisecondsSinceEpoch ~/ 86400000;
    final libKey = Object.hash(c.libraryRevision.value, day, identityHashCode(c));
    final histKey = Object.hash(libKey, history.revision);
    if (_mergedKey == (libKey, histKey) && _merged != null) return _merged!;
    var lib = _libraryPart;
    if (lib == null || lib.$1 != libKey) {
      final fresh = _libraryLists(c.library);
      lib = (libKey, _reuse(lib?.$2, fresh));
      _libraryPart = lib;
    }
    var hist = _historyPart;
    if (hist == null || hist.$1 != histKey) {
      computations++;
      final fresh = _historyLists(c.library, history, DateTime.now());
      hist = (histKey, _reuse(hist?.$2, fresh));
      _historyPart = hist;
    }
    final merged = {for (final l in SmartList.values) l: ?(lib.$2[l] ?? hist.$2[l])};
    _mergedKey = (libKey, histKey);
    return _merged = merged;
  }

  /// Forgets what was worked out (a test starting afresh).
  @visibleForTesting
  static void resetCache() {
    _libraryPart = _historyPart = null;
    _merged = null;
    _mergedKey = null;
    computations = 0;
  }

  static Map<SmartList, Collection> _libraryLists(List<Track> library) {
    computations++;
    return _build(library, null, DateTime.now(), {SmartList.recentlyAdded, SmartList.lossless});
  }

  static Map<SmartList, Collection> _historyLists(List<Track> library, PlayHistory history, DateTime now) {
    return _build(library, history, now, {
      SmartList.mostPlayed,
      SmartList.recentlyPlayed,
      SmartList.notPlayedForAWhile,
    });
  }

  /// [next], but a list with exactly the songs (same objects, same order) the [prev] one had stays [prev]'s.
  static Map<SmartList, Collection> _reuse(Map<SmartList, Collection>? prev, Map<SmartList, Collection> next) {
    if (prev == null) return next;
    return {
      for (final e in next.entries)
        e.key: switch (prev[e.key]) {
          final old? when old.subtitle == e.value.subtitle && _sameSongs(old.tracks, e.value.tracks) => old,
          _ => e.value,
        },
    };
  }

  static bool _sameSongs(List<Track> a, List<Track> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }
}

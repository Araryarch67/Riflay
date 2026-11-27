import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A note at a moment of a book: "the part about the harbour", at 1:12:40.
class Bookmark {
  const Bookmark(this.at, this.note);

  final Duration at;
  final String note;

  Map<String, dynamic> toJson() => {'at': at.inMilliseconds, 'note': note};

  static Bookmark? fromJson(Object? j) {
    if (j is! Map || j['at'] is! num) return null;
    return Bookmark(Duration(milliseconds: (j['at'] as num).toInt()), '${j['note'] ?? ''}');
  }
}

/// What is kept for one book: where the listener stopped, how fast they like it, and their bookmarks.
class SpokenBook {
  SpokenBook({this.position = Duration.zero, this.tempo = 1, List<Bookmark>? bookmarks}) : bookmarks = bookmarks ?? [];

  Duration position;
  double tempo;
  final List<Bookmark> bookmarks;

  Map<String, dynamic> toJson() => {
    'pos': position.inMilliseconds,
    'tempo': tempo,
    'marks': [for (final b in bookmarks) b.toJson()],
  };

  static SpokenBook fromJson(Map j) => SpokenBook(
    position: Duration(milliseconds: (j['pos'] as num?)?.toInt() ?? 0),
    tempo: ((j['tempo'] as num?)?.toDouble() ?? 1).clamp(0.5, 2.0),
    bookmarks: [for (final b in (j['marks'] as List? ?? const [])) ?Bookmark.fromJson(b)],
  );
}

/// Audiobooks and podcast episodes: a song the listener marked as one is remembered per book, so it picks up where
/// it stopped, at its own speed (the listener's pace for a narrator is not their pace for music).
///
/// Keyed by the track's id. Marking a track is what makes it a book; music is left alone.
class SpokenWord extends ChangeNotifier {
  SpokenWord();
  static final instance = SpokenWord();

  static const _key = 'spoken.books';

  /// Before this a book counts as not started; within [finishedWithin] of the end it counts as finished.
  /// Resuming 3 seconds in, or 4 seconds before the credits, would only be annoying.
  static const startedAfter = Duration(seconds: 5);
  static const finishedWithin = Duration(seconds: 15);

  /// How much each jump button moves: the phone's usual back-15 / forward-30 for spoken word.
  static const jumpBack = Duration(seconds: 15);
  static const jumpForward = Duration(seconds: 30);

  final Map<String, SpokenBook> _books = {};
  SharedPreferences? _prefs;

  Future<void> load([SharedPreferences? prefs]) async {
    final p = _prefs = prefs ?? await SharedPreferences.getInstance();
    _books.clear();
    try {
      final saved = jsonDecode(p.getString(_key) ?? '{}') as Map;
      for (final e in saved.entries) {
        if (e.value is Map) _books['${e.key}'] = SpokenBook.fromJson(e.value as Map);
      }
    } catch (e) {
      debugPrint('Audiobooks unreadable: $e');
    }
    notifyListeners();
  }

  Future<void> _store() async {
    notifyListeners();
    final p = _prefs ??= await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode({for (final e in _books.entries) e.key: e.value.toJson()}));
  }

  /// Writes what is held in memory (the positions between the disk writes).
  Future<void> flush() => _store();

  bool isBook(String? id) => id != null && _books.containsKey(id);

  /// Marks a track as a book, or takes the mark off (its position, speed and bookmarks go with it).
  Future<void> setBook(String id, bool on) {
    if (on) {
      _books.putIfAbsent(id, SpokenBook.new);
    } else {
      _books.remove(id);
    }
    return _store();
  }

  /// Where to resume a book, or null to start from the beginning.
  Duration? resumeAt(String id) {
    final p = _books[id]?.position;
    return p == null || p < startedAfter ? null : p;
  }

  double tempoOf(String id) => _books[id]?.tempo ?? 1;

  /// Keeps [position] for a book. A book played out to its end starts over next time, and an unstarted one stays so.
  /// [persist] false keeps it in memory only (positions arrive every second; the disk need not).
  Future<void> savePosition(String id, Duration position, Duration? total, {bool persist = true}) {
    final book = _books[id];
    if (book == null) return Future.value();
    final finished = total != null && total > finishedWithin && position >= total - finishedWithin;
    book.position = finished ? Duration.zero : position;
    return persist ? _store() : Future.value();
  }

  Future<void> setTempo(String id, double tempo) {
    final book = _books[id];
    if (book == null || book.tempo == tempo) return Future.value();
    book.tempo = tempo.clamp(0.5, 2.0);
    return _store();
  }

  /// Bookmarks of a book, in the order they fall in it.
  List<Bookmark> bookmarks(String id) => List.unmodifiable(_books[id]?.bookmarks ?? const []);

  Future<void> addBookmark(String id, Duration at, String note) {
    final marks = _books[id]?.bookmarks;
    if (marks == null) return Future.value();
    marks
      ..add(Bookmark(at, note.trim()))
      ..sort((a, b) => a.at.compareTo(b.at));
    return _store();
  }

  Future<void> removeBookmark(String id, Bookmark mark) {
    _books[id]?.bookmarks.remove(mark);
    return _store();
  }
}

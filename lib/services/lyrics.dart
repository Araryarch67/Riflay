import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

import '../models/track.dart';
import 'beta_features.dart';
import 'lyrics_sources.dart';
import 'ytmusic_web.dart';

/// One word (or syllable) of a word-timed line, sung from [start] to [end].
/// [text] keeps its own trailing space, so a line's words joined give its text.
class LyricWord {
  const LyricWord(this.start, this.end, this.text);

  final Duration start;
  final Duration end;
  final String text;
}

/// One timed line of synced lyrics. [words] is empty unless the source times
/// each word (karaoke); [end] is when the line stops, when the source says.
class LyricLine {
  const LyricLine(this.time, this.text, {this.end, this.words = const []});

  final Duration time;
  final String text;
  final Duration? end;
  final List<LyricWord> words;
}

/// What [Lyrics.check] found.
class LrcCheck {
  const LrcCheck.timed() : timed = true, problem = null;
  const LrcCheck.plain() : timed = false, problem = null;
  const LrcCheck.invalid(String this.problem) : timed = false;

  final bool timed;

  /// One calm sentence for the person, null when the lyrics are fine.
  final String? problem;

  bool get ok => problem == null;
}

/// Lyrics for a song: timed lines when available, plain text otherwise.
class Lyrics {
  const Lyrics({
    this.lines = const [],
    this.plain,
    this.instrumental = false,
    required this.source,
    this.otherVersion = false,
  });

  final List<LyricLine> lines;
  final String? plain;
  final bool instrumental;

  /// Timed for another recording of the song (a different length, such as a
  /// music video with an intro): the lines may come early or late.
  final bool otherVersion;

  /// Where they came from, shown under the lyrics ("LRCLIB", "Embedded in the file"...).
  final String source;

  bool get synced => lines.isNotEmpty;

  /// Some lines are timed word by word.
  bool get wordSynced => lines.any((l) => l.words.isNotEmpty);

  /// Nothing found anywhere.
  bool get isEmpty => lines.isEmpty && plain == null && !instrumental;

  static const none = Lyrics(source: '');

  /// Index of the line being sung at [position], or -1 before the first one.
  int lineAt(Duration position) {
    var lo = 0, hi = lines.length - 1, found = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (lines[mid].time <= position) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return found;
  }

  static final _stamp = RegExp(r'\[(\d+):(\d+(?:[.:]\d+)?)\]');

  /// A word tag of enhanced LRC: `<mm:ss.xx>`.
  static final _wordTag = RegExp(r'<(\d+):(\d+(?:[.:]\d+)?)>');

  static Duration _clock(RegExpMatch m) {
    final seconds = double.parse(m[2]!.replaceFirst(':', '.'));
    return Duration(milliseconds: (int.parse(m[1]!) * 60000 + seconds * 1000).round());
  }

  static Duration _atLeastZero(Duration d) => d < Duration.zero ? Duration.zero : d;

  /// Whether timed [lines] can be followed on screen. Some sources stamp every
  /// line with the same time (all `[00:00.00]`), or barely vary it: lyrics like
  /// that are only text, and [lineAt] would call every line sung at once.
  /// A few repeated stamps (a chorus sung twice) are fine.
  static bool _followable(List<LyricLine> lines) {
    final sung = [
      for (final l in lines)
        if (l.text.isNotEmpty) l.time,
    ];
    if (sung.isEmpty) return true;
    if (sung.reduce((a, b) => a > b ? a : b) == Duration.zero) return false;
    final distinct = sung.toSet().length;
    if (sung.length > 1 && distinct == 1) return false;
    return distinct * 2 >= sung.length;
  }

  /// Timed [lines] when they can be followed, otherwise the same words as plain text.
  static Lyrics _timedOrPlain(List<LyricLine> lines, {String? plain, required String source}) {
    if (_followable(lines)) return Lyrics(lines: lines, plain: plain, source: source);
    final text = plain ?? [for (final l in lines) l.text].join('\n').trim();
    return Lyrics(plain: text.isEmpty ? null : text, source: source);
  }

  /// [l] with timings nobody could follow turned into plain text.
  static Lyrics _checked(Lyrics l) =>
      l.synced && !_followable(l.lines) ? _timedOrPlain(l.lines, plain: l.plain, source: l.source) : l;

  /// Parses LRC text, with enhanced word tags (`<mm:ss.xx>`) when it has them.
  /// Returns plain lyrics if it has no timestamps, or if every line has the
  /// same time.
  static Lyrics parse(String text, {required String source}) {
    final pending = <_Pending>[];
    var offset = Duration.zero;
    for (final raw in const LineSplitter().convert(text)) {
      final off = RegExp(r'^\[offset:\s*([+-]?\d+)\]', caseSensitive: false).firstMatch(raw.trim());
      if (off != null) {
        // Positive offsets make lyrics appear sooner.
        offset = Duration(milliseconds: -int.parse(off[1]!));
        continue;
      }
      final stamps = _stamp.allMatches(raw).toList();
      if (stamps.isEmpty) continue;
      final first = _clock(stamps.first);
      final line = _lineWords(raw.substring(stamps.last.end), first);
      for (final s in stamps) {
        final t = _atLeastZero(_clock(s) + offset);
        // Another stamp on the same line (a repeated chorus) moves its words along.
        final shift = t - first;
        pending.add(
          _Pending(t, line.text, [
            for (final w in line.words)
              _Word(_atLeastZero(w.start + shift), w.end == null ? null : _atLeastZero(w.end! + shift), w.text),
          ]),
        );
      }
    }
    if (pending.isEmpty) {
      final plain = text.trim();
      return Lyrics(plain: plain.isEmpty ? null : plain, source: source);
    }
    final order = [for (var i = 0; i < pending.length; i++) i]
      ..sort((a, b) {
        final c = pending[a].time.compareTo(pending[b].time);
        return c != 0 ? c : a.compareTo(b);
      });
    final sorted = [for (final i in order) pending[i]];
    final lines = <LyricLine>[];
    for (final (i, line) in sorted.indexed) {
      if (line.words.isEmpty) {
        lines.add(LyricLine(line.time, line.text));
        continue;
      }
      // The last word ends where its closing tag says, else where the next line starts.
      final last = line.words.last;
      if (last.end == null) {
        final next = i + 1 < sorted.length ? sorted[i + 1].time : null;
        last.end = next != null && next > last.start ? next : last.start + const Duration(seconds: 1);
      }
      lines.add(_wordLine(line.time, line.text, line.words));
    }
    return _timedOrPlain(lines, source: source);
  }

  /// A line from its words, each one ending where the next starts when it doesn't say.
  static LyricLine _wordLine(Duration time, String text, List<_Word> words) {
    final out = <LyricWord>[];
    for (final (i, w) in words.indexed) {
      var end = w.end ?? (i + 1 < words.length ? words[i + 1].start : w.start);
      if (end < w.start) end = w.start;
      out.add(LyricWord(w.start, end, w.text));
    }
    return LyricLine(time, text, end: out.last.end, words: out);
  }

  /// The text after a line's time stamp, and its words when it has word tags:
  /// `<00:12.00>Hello <00:12.50>world<00:13.20>`, or `Hello <00:12.50>world`
  /// (the first word then starts with the line). A trailing tag ends the last word.
  static ({String text, List<_Word> words}) _lineWords(String rest, Duration lineStart) {
    final tags = _wordTag.allMatches(rest).toList();
    if (tags.isEmpty) return (text: rest.trim(), words: const []);
    final words = <_Word>[];
    final head = rest.substring(0, tags.first.start);
    if (head.trim().isNotEmpty) words.add(_Word(lineStart, null, head));
    for (final (i, tag) in tags.indexed) {
      final at = _clock(tag);
      final chunk = rest.substring(tag.end, i + 1 < tags.length ? tags[i + 1].start : rest.length);
      if (chunk.trim().isNotEmpty) {
        words.add(_Word(at, null, chunk));
        continue;
      }
      // Only a space, or nothing: it closes the word before it.
      if (words.isEmpty) continue;
      if (chunk.isNotEmpty) words.last.text += ' ';
      words.last.end ??= at;
    }
    if (words.isEmpty) return (text: '', words: const []);
    words.first.text = words.first.text.trimLeft();
    words.last.text = words.last.text.trimRight();
    for (final (i, w) in words.indexed) {
      if (i + 1 < words.length) w.end ??= words[i + 1].start;
    }
    return (text: words.map((w) => w.text).join(), words: words);
  }

  /// The lyrics as the text of an `.lrc` file: `[mm:ss.xx]line`, with enhanced
  /// word tags (`[mm:ss.xx]<mm:ss.xx>Hello <mm:ss.xx>world<mm:ss.xx>`) when a
  /// line is timed word by word, so [parse] reads them back. Plain lyrics are
  /// their text; null when there are none (or the song is instrumental).
  String? toLrc() {
    if (lines.isEmpty) {
      final text = plain?.trim();
      return text == null || text.isEmpty ? null : text;
    }
    String tag(Duration d) {
      final cs = (d.inMilliseconds / 10).round();
      String two(int n) => n.toString().padLeft(2, '0');
      return '${two(cs ~/ 6000)}:${two(cs ~/ 100 % 60)}.${two(cs % 100)}';
    }

    final out = StringBuffer();
    for (final line in lines) {
      out.write('[${tag(line.time)}]');
      if (line.words.isEmpty) {
        out.writeln(line.text);
        continue;
      }
      for (final (i, w) in line.words.indexed) {
        out.write('<${tag(w.start)}>${w.text}');
        // A gap before the next word needs its own end tag.
        final next = i + 1 < line.words.length ? line.words[i + 1].start : null;
        if (next == null || (next - w.end).inMilliseconds.abs() > 10) out.write('<${tag(w.end)}>');
      }
      out.writeln();
    }
    return out.toString().trimRight();
  }

  /// Checks lyrics a person typed or loaded before they are kept. Text with
  /// no timestamps is fine (plain lyrics); timestamps must be written as
  /// `[mm:ss.xx]` with seconds under 60, and, when the song's [length] is
  /// known, can't all fall long after it ends.
  static LrcCheck check(String text, {Duration? length}) {
    if (text.trim().isEmpty) return const LrcCheck.invalid('Add some lyrics first.');
    const bad = LrcCheck.invalid(
      'Some of the times in these lyrics aren\'t written correctly. Start each line with a time like [01:23.45].',
    );
    final full = RegExp(r'^(\[\d+:\d+(?:[.:]\d+)?\])+');
    var stamps = 0;
    var latest = Duration.zero;
    for (final raw in const LineSplitter().convert(text)) {
      final line = raw.trim();
      // [ar:Artist], [ti:Title] and friends are not times.
      if (!RegExp(r'^\[\d').hasMatch(line)) continue;
      final lead = full.firstMatch(line);
      if (lead == null) return bad;
      for (final m in _stamp.allMatches(lead[0]!)) {
        final seconds = double.parse(m[2]!.replaceFirst(':', '.'));
        if (seconds >= 60) return bad;
        final t = Duration(milliseconds: (int.parse(m[1]!) * 60000 + seconds * 1000).round());
        if (t > latest) latest = t;
        stamps++;
      }
    }
    if (stamps == 0) return const LrcCheck.plain();
    if (length != null && length > Duration.zero && latest > length + const Duration(seconds: 15)) {
      return const LrcCheck.invalid('These times run past the end of the song. Check that the lyrics belong to it.');
    }
    return const LrcCheck.timed();
  }

  /// Parses TTML (Apple Music style, as Better Lyrics serves it): one `<p>` per
  /// line, with word or syllable `<span>`s. Background vocals and
  /// translations are left out.
  static Lyrics parseTtml(String ttml, {required String source}) {
    final lines = <LyricLine>[];
    for (final p in XmlDocument.parse(ttml).findAllElements('p')) {
      final begin = _ttmlTime(p.getAttribute('begin'));
      if (begin == null) continue;
      final text = _ttmlText(p).replaceAll(RegExp(r'\s+'), ' ').trim();
      final end = _ttmlTime(p.getAttribute('end'));
      final words = _ttmlWords(p, text, end);
      lines.add(LyricLine(begin, text, end: words.isEmpty ? end : (end ?? words.last.end), words: words));
    }
    lines.sort((a, b) => a.time.compareTo(b.time));
    return _timedOrPlain(lines, source: source);
  }

  /// The timed spans of a main-vocal line as words. The space between two
  /// spans ends the first one; syllables of one word have none between them.
  /// Empty when the line has no timed spans, or text outside them.
  static List<LyricWord> _ttmlWords(XmlElement p, String text, Duration? lineEnd) {
    final parts = <({String text, Duration? start, Duration? end})>[];
    var loose = false;
    void walk(XmlElement element) {
      for (final node in element.children) {
        if (node is XmlText) {
          if (node.value.trim().isNotEmpty) loose = true;
          parts.add((text: node.value, start: null, end: null));
        } else if (node is XmlElement) {
          final role = node.attributes.where((a) => a.localName == 'role').map((a) => a.value).firstOrNull;
          if (role != null && role.startsWith('x-')) continue;
          final start = _ttmlTime(node.getAttribute('begin'));
          if (start != null && !node.descendantElements.any((e) => e.getAttribute('begin') != null)) {
            parts.add((text: _ttmlText(node), start: start, end: _ttmlTime(node.getAttribute('end'))));
          } else {
            walk(node);
          }
        }
      }
    }

    walk(p);
    // Text outside every span isn't timed: the words wouldn't add up to the line.
    if (loose || parts.every((x) => x.start == null)) return const [];
    final words = <_Word>[];
    for (final part in parts) {
      final flat = part.text.replaceAll(RegExp(r'\s+'), ' ');
      if (part.start == null || flat.trim().isEmpty) {
        if (words.isNotEmpty && flat.isNotEmpty && !words.last.text.endsWith(' ')) words.last.text += ' ';
        continue;
      }
      if (flat.startsWith(' ') && words.isNotEmpty && !words.last.text.endsWith(' ')) words.last.text += ' ';
      words.add(_Word(part.start!, part.end, flat.trimLeft()));
    }
    if (words.isEmpty) return const [];
    words.last.text = words.last.text.trimRight();
    if (words.map((w) => w.text).join() != text) return const [];
    words.last.end ??= lineEnd != null && lineEnd > words.last.start
        ? lineEnd
        : words.last.start + const Duration(seconds: 1);
    return _wordLine(Duration.zero, text, words).words;
  }

  static String _ttmlText(XmlElement element) {
    final out = StringBuffer();
    for (final node in element.children) {
      if (node is XmlText) {
        out.write(node.value);
      } else if (node is XmlElement) {
        final role = node.attributes.where((a) => a.localName == 'role').map((a) => a.value).firstOrNull;
        if (role != null && role.startsWith('x-')) continue; // x-bg, x-translation, x-roman
        out.write(_ttmlText(node));
      }
    }
    return out.toString();
  }

  /// "13.274", "1:02.500", "00:00:18.234" or "18.2s".
  static Duration? _ttmlTime(String? value) {
    if (value == null) return null;
    final parts = value.trim().replaceFirst(RegExp(r's$'), '').split(':');
    var seconds = 0.0;
    for (final part in parts) {
      final n = double.tryParse(part);
      if (n == null) return null;
      seconds = seconds * 60 + n;
    }
    return Duration(milliseconds: (seconds * 1000).round());
  }
}

/// A word being read from LRC or TTML; the end may not be known yet.
class _Word {
  _Word(this.start, this.end, this.text);

  Duration start;
  Duration? end;
  String text;
}

/// A line read from LRC, before the lines are put in order.
class _Pending {
  _Pending(this.time, this.text, this.words);

  final Duration time;
  final String text;
  final List<_Word> words;
}

/// Finds lyrics: the person's own, then a `.lrc` next to the file or the tags,
/// then a copy kept from an earlier look, then online. Online, word-timed
/// lyrics win over line-timed ones, and those over plain text. First, all at
/// once: YouTube Music (its own Lyrics tab), LRCLIB, Better Lyrics, Kugou,
/// NetEase Cloud Music and QQ Music. Without word timing, Musixmatch is asked
/// next, then Megalobiz for timed lines. Plain text comes from the above, then
/// Genius, then lyrics.ovh. A source that takes over 8 seconds is skipped.
abstract final class LyricsService {
  static final _cache = <String, Future<Lyrics>>{};

  /// Forget what was found for [track], so the next look reads its lyrics again.
  static void forget(Track track) => _cache.remove(track.id);

  /// [Lyrics.none] when there are none; throws when no source could be
  /// reached (that isn't cached, so the next try asks again).
  static Future<Lyrics> forTrack(Track track) {
    final cached = _cache.remove(track.id);
    final future =
        _cache[track.id] = // newest last
            cached ??
            _find(track).then((r) {
              // A source that couldn't be asked (offline, rate limited) may have them:
              // "none" isn't remembered then, so the next look asks again.
              if (r.missed) _cache.remove(track.id);
              return r.lyrics;
            });
    // A long session plays thousands of songs: keep the lyrics of the last few dozen.
    while (_cache.length > 48) {
      _cache.remove(_cache.keys.first);
    }
    future.ignore();
    return future.catchError((Object e) {
      _cache.remove(track.id);
      throw e;
    });
  }

  /// How long one site gets to answer before the others' answers are used.
  @visibleForTesting
  static Duration sourceTimeout = const Duration(seconds: 8);

  static Future<({Lyrics lyrics, bool missed})> _find(Track track) async {
    // Lyrics the person added to a song always win over any other source.
    if (await UserLyrics.read(track) case final text?) {
      final mine = Lyrics.parse(text, source: 'Your lyrics');
      if (!mine.isEmpty) return (lyrics: mine, missed: false);
    }
    final path = track.path;
    if (path != null) {
      final local = await Isolate.run(() => _local(path));
      if (local != null && !local.isEmpty) return (lyrics: local, missed: false);
    }
    if (await LyricsCache.read(track) case final kept?) return (lyrics: kept, missed: false);
    final r = await _online(track);
    if (!r.missed && !r.lyrics.isEmpty) await LyricsCache.write(track, r.lyrics);
    return r;
  }

  static Future<({Lyrics lyrics, bool missed})> _online(Track track) async {
    final errors = <Object>[];
    var asked = 0;
    Future<Lyrics?> attempt(Future<Lyrics?> Function() source) async {
      asked++;
      try {
        final l = await source().timeout(sourceTimeout);
        return l == null ? null : Lyrics._checked(l);
      } catch (e) {
        debugPrint('Lyrics source failed: $e');
        errors.add(e);
        return null;
      }
    }

    // In the order the sources are preferred for word timing.
    final found = <Lyrics?>[];
    Lyrics? timed() => found.firstWhere(_timed, orElse: () => null);
    Lyrics? wordTimed() => found.firstWhere((l) => _timed(l) && l!.wordSynced, orElse: () => null);

    Future<Lyrics?> search(Track t) async {
      found.addAll(
        await Future.wait([
          attempt(() => _youtube(t)),
          attempt(() => _lrclib(t)),
          attempt(() => _betterLyrics(t)),
          attempt(() => MoreLyrics.kugou(t)),
          attempt(() => netease(t)),
          attempt(() => MoreLyrics.qqMusic(t)),
        ]),
      );
      if (wordTimed() case final l?) return l;
      // Timed lines are fine, but Musixmatch may time every word (Beta: it often
      // refuses, and then rests for a while without being asked).
      if (BetaFeatures.instance.isOn(BetaFeature.musixmatch)) found.add(await attempt(() => MoreLyrics.musixmatch(t)));
      if (wordTimed() case final l?) return l;
      if (timed() == null) found.add(await attempt(() => MoreLyrics.megalobiz(t)));
      return timed();
    }

    if (await search(track) case final l?) return (lyrics: l, missed: false);

    // Another upload of the same song (a fan's video, a lyric video, the music
    // video of an album track) has no Lyrics tab of its own, and its title and
    // uploader don't match the lyrics sites: ask again as the song YouTube
    // Music's catalogue has.
    Track? same;
    if (track.isRemote) {
      try {
        final match = await _catalogueSong(track);
        if (match != null) {
          same = match.song;
          // Timed lines only fit the same recording; another one gets the words alone.
          if (await search(match.song) case final l?) {
            return (lyrics: match.sameLength ? l : _otherVersion(l), missed: false);
          }
        }
      } catch (e) {
        debugPrint('Lyrics: no catalogue song: $e');
        errors.add(e);
      }
    }

    Lyrics? plain() {
      for (final l in found) {
        if (l == null) continue;
        if (l.plain != null || l.instrumental) return l.synced ? Lyrics(plain: l.plain, source: l.source) : l;
      }
      return null;
    }

    if (plain() case final l?) return (lyrics: l, missed: false);
    found.add(await attempt(() => MoreLyrics.genius(same ?? track)));
    if (plain() case final l?) return (lyrics: l, missed: false);
    found.add(await attempt(() => lyricsOvh(same ?? track)));
    if (plain() case final l?) return (lyrics: l, missed: false);
    if (errors.length >= asked) throw errors.first; // nothing could be asked
    return (lyrics: Lyrics.none, missed: errors.isNotEmpty);
  }

  /// Real timed lyrics. LRCLIB has junk entries with a line or two; from the
  /// others a song with only a few words (a beatbox track) is still lyrics.
  static bool _timed(Lyrics? l) =>
      l != null && l.lines.where((line) => line.text.isNotEmpty).length >= (l.source == 'LRCLIB' ? 4 : 1);

  /// Lines of another recording: still timed, marked so the person can nudge them into place.
  static Lyrics _otherVersion(Lyrics l) =>
      Lyrics(lines: l.lines, plain: l.plain, instrumental: l.instrumental, source: l.source, otherVersion: l.synced);

  /// The song YouTube Music's catalogue has under the upload's words: its
  /// title has to be in the upload's title, and the artist named there or the
  /// length the same. [sameLength]: within a few seconds, so timed lines fit.
  static Future<({Track song, bool sameLength})?> _catalogueSong(Track upload) async {
    final title = cleanTitle(upload.title);
    final uploader = upload.artist == Track.unknownArtist ? '' : upload.artist;
    final words = norm('$title $uploader');
    final web = YtMusicWeb.anonymous();
    try {
      // The upload's own words first, then only the song's part of them
      // ("Song - Artist Karaoke Lower Key" → "Song - Artist").
      for (final query in {'$title $uploader'.trim(), _core(upload.title)}) {
        if (query.isEmpty) continue;
        for (final hit in (await web.searchSongs(query)).take(8)) {
          if (hit.videoId == upload.videoId) continue; // asked already
          final name = norm(cleanTitle(hit.title));
          if (name.isEmpty || !norm(title).contains(name)) continue;
          final artist = norm(hit.artist.split(', ').first);
          final named = artist.isNotEmpty && words.contains(artist);
          final a = upload.duration, b = hit.duration;
          final sameLength = a != null && b != null && (a - b).abs() <= const Duration(seconds: 3);
          if (!named && !sameLength) continue;
          final song = Track.youtube(
            videoId: hit.videoId,
            title: hit.title,
            artist: hit.artist.isEmpty ? Track.unknownArtist : hit.artist,
            duration: hit.duration,
          );
          return (song: song, sameLength: sameLength);
        }
      }
      return null;
    } finally {
      web.close();
    }
  }

  /// Words in a video's title that say it's a version of the song, and all after them.
  static final _versionWords = RegExp(
    r'[\s|:,–—-]*\b(karaoke|cover|covered|live|remix|lyrics?|lirik|instrumental|reaction|acoustic|versi|version|'
    r'lower key|female key|male key|nada rendah|nada tinggi|slowed|reverb|sped up|nightcore|tiktok)\b.*$',
    caseSensitive: false,
  );

  /// The song's part of a video title: "Tulus - Hati Hati Di Jalan Karaoke Lower Key" → "Tulus - Hati Hati Di Jalan".
  static String _core(String title) => cleanTitle(title).replaceFirst(_versionWords, '').replaceAll('|', ' ').trim();

  /// The song's own lyrics on YouTube Music (YouTube songs only).
  static Future<Lyrics?> _youtube(Track track) async {
    final id = track.videoId;
    if (id == null) return null;
    final web = YtMusicWeb.anonymous();
    try {
      final l = await web.lyrics(id);
      if (l == null) return null;
      final source = l.source.isEmpty ? 'YouTube Music' : 'YouTube Music (${l.source})';
      if (l.lines.isNotEmpty) {
        return Lyrics._timedOrPlain([for (final line in l.lines) LyricLine(line.time, line.text)], source: source);
      }
      return Lyrics(plain: l.plain, source: source);
    } finally {
      web.close();
    }
  }

  /// The user's own Better Lyrics API key, if they have one: it lets Better
  /// Lyrics fetch songs it hasn't cached yet. Optional; keys aren't handed out
  /// to everyone.
  static String? betterLyricsKey;

  static Future<void> loadBetterLyricsKey() async {
    betterLyricsKey = (await SharedPreferences.getInstance()).getString('lyrics.betterLyricsKey');
  }

  /// Saves [key] (null removes it) after Better Lyrics accepts it. Returns
  /// false when Better Lyrics says the key isn't valid; throws when it can't
  /// be reached.
  static Future<bool> setBetterLyricsKey(String? key, {http.Client? client}) async {
    key = key?.trim();
    if (key != null && key.isEmpty) key = null;
    if (key != null) {
      // Better Lyrics only checks the key on a cache miss (a cached song is
      // served to anyone), so ask for a song that can't be cached.
      final res = await (client ?? _http).get(
        Uri.https('api.betterlyrics.org', '/getLyrics', {
          's': 'riflay key check ${DateTime.now().microsecondsSinceEpoch}',
          'a': 'riflay',
          'd': '1',
        }),
        headers: {..._headers, 'X-API-Key': key},
      );
      final mode = res.headers['x-auth-mode'];
      if (mode == 'invalid' || res.statusCode == 401 || res.statusCode == 403) return false;
      if (mode == null && res.statusCode >= 500) throw HttpException('Better Lyrics ${res.statusCode}');
    }
    final prefs = await SharedPreferences.getInstance();
    key == null ? await prefs.remove('lyrics.betterLyricsKey') : await prefs.setString('lyrics.betterLyricsKey', key);
    betterLyricsKey = key;
    // Songs that came up empty may have lyrics now.
    _cache.clear();
    return true;
  }

  /// Better Lyrics (api.betterlyrics.org): word-timed lyrics. Without an API
  /// key it only serves songs it has already cached; a miss is no lyrics.
  static Future<Lyrics?> _betterLyrics(Track track) async {
    final artist = track.artist == Track.unknownArtist ? '' : track.artist;
    if (artist.isEmpty) return null;
    final res = await http.get(
      Uri.https('api.betterlyrics.org', '/getLyrics', {
        's': cleanTitle(track.title),
        'a': artist,
        'al': ?track.album,
        if (track.duration case final d?) 'd': '${d.inSeconds}',
        'videoId': ?track.videoId,
      }),
      headers: {..._headers, 'X-API-Key': ?betterLyricsKey},
    );
    if (res.statusCode != 200) return null; // 401 (not cached), 404, 429...
    final ttml = (jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>)['ttml'];
    if (ttml is! String || ttml.trim().isEmpty) return null;
    final l = Lyrics.parseTtml(ttml, source: 'Better Lyrics');
    return l.synced ? l : null;
  }

  static final _http = http.Client();

  /// Lowercase letters and digits only, so "Hati-Hati di Jalan" matches "hati hati di jalan".
  static String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');

  /// NetEase's songwriter and producer credits, given as the first timed lines.
  static final _credit = RegExp(r'^\s*(\[[^\]]*\])*\s*(作词|作曲|编曲|制作人|监制|混音|录音|和声|母带|词|曲)\s*[:：]');

  /// NetEase Cloud Music: a large catalogue of timed lyrics, including many
  /// songs LRCLIB lacks. Free and keyless; the same endpoints open-source
  /// players (LyricsX, YesPlayMusic) use.
  @visibleForTesting
  static Future<Lyrics?> netease(Track track, {http.Client? client}) async {
    final artist = track.artist == Track.unknownArtist ? '' : track.artist;
    if (artist.isEmpty) return null;
    final c = client ?? _http;
    final title = cleanTitle(track.title);
    // Without the desktop client's cookie many songs come back with empty lyrics.
    const headers = {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://music.163.com', 'Cookie': 'os=pc'};
    final res = await c.get(
      Uri.https('music.163.com', '/api/cloudsearch/pc', {'s': '$artist $title', 'type': '1', 'limit': '10'}),
      headers: headers,
    );
    if (res.statusCode != 200) throw HttpException('NetEase ${res.statusCode}');
    final result = (jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>)['result'];
    final songs = ((result is Map ? result['songs'] : null) as List? ?? const []).cast<Map<String, dynamic>>();
    final want = norm(title), who = norm(artist), seconds = track.duration?.inSeconds;
    // Same title, a shared artist and the same length: covers and remixes share titles.
    // The same song is often listed more than once, not every copy with lyrics.
    final matches = songs.where((s) {
      final artists = [for (final a in (s['ar'] as List? ?? const [])) norm((a as Map)['name'] as String? ?? '')];
      final ms = (s['dt'] as num?)?.toInt();
      return norm(cleanTitle(s['name'] as String? ?? '')) == want &&
          artists.any((a) => a.isNotEmpty && (who.contains(a) || a.contains(who))) &&
          (seconds == null || ms == null || (ms / 1000 - seconds).abs() <= 3);
    });
    for (final song in matches.take(3)) {
      final lr = await c.get(
        Uri.https('music.163.com', '/api/song/lyric', {'id': '${song['id']}', 'lv': '-1'}),
        headers: headers,
      );
      if (lr.statusCode != 200) throw HttpException('NetEase ${lr.statusCode}');
      final text = ((jsonDecode(utf8.decode(lr.bodyBytes)) as Map<String, dynamic>)['lrc'] as Map?)?['lyric'];
      if (text is! String || text.trim().isEmpty) continue;
      if (text.contains('纯音乐')) return const Lyrics(instrumental: true, source: 'NetEase Cloud Music');
      final l = Lyrics.parse(
        text.split('\n').where((line) => !_credit.hasMatch(line)).join('\n'),
        source: 'NetEase Cloud Music',
      );
      if (!l.isEmpty) return l;
    }
    return null;
  }

  /// lyrics.ovh (open source): plain text only, so it is asked last.
  @visibleForTesting
  static Future<Lyrics?> lyricsOvh(Track track, {http.Client? client}) async {
    final artist = track.artist == Track.unknownArtist ? '' : track.artist;
    if (artist.isEmpty) return null;
    final res = await (client ?? _http)
        .get(
          Uri(scheme: 'https', host: 'api.lyrics.ovh', pathSegments: ['v1', artist, cleanTitle(track.title)]),
          headers: _headers,
        )
        // It is often slow; a lyrics view shouldn't wait on it for long.
        .timeout(const Duration(seconds: 8));
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) throw HttpException('lyrics.ovh ${res.statusCode}');
    final text = (jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>)['lyrics'];
    if (text is! String) return null;
    // Some entries start with a French "Paroles de la chanson … par …" heading.
    final plain = text.replaceFirst(RegExp(r'^Paroles de la chanson[^\n]*\n'), '').replaceAll('\r', '').trim();
    return plain.isEmpty ? null : Lyrics(plain: plain, source: 'lyrics.ovh');
  }

  static Lyrics? _local(String path) {
    final dot = path.lastIndexOf('.');
    final lrc = File('${dot < 0 ? path : path.substring(0, dot)}.lrc');
    if (lrc.existsSync()) {
      try {
        return Lyrics.parse(lrc.readAsStringSync(), source: 'Lyrics file');
      } catch (_) {}
    }
    try {
      final text = readMetadata(File(path)).lyrics;
      if (text != null && text.trim().isNotEmpty) return Lyrics.parse(text, source: 'Embedded in the file');
    } catch (_) {}
    return null;
  }

  static const _headers = {'User-Agent': 'Riflay (https://github.com/Araryarch67/Riflay)'};

  /// "Song (Official Video) [HD]" → "Song".
  static String cleanTitle(String t) => t
      .replaceAll(
        RegExp(
          r'\s*[\(\[][^\)\]]*(official|video|audio|lyric|visualizer|remaster|hd|4k|mv)[^\)\]]*[\)\]]',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(RegExp(r'\s+-\s+topic$', caseSensitive: false), '')
      .trim();

  static Future<Lyrics?> _lrclib(Track track) async {
    final title = cleanTitle(track.title);
    final artist = track.artist == Track.unknownArtist ? '' : track.artist;
    final seconds = track.duration?.inSeconds;

    // Exact match by title, artist and length first: fast and right most of the time.
    if (artist.isNotEmpty) {
      final res = await http.get(
        Uri.https('lrclib.net', '/api/get', {
          'track_name': title,
          'artist_name': artist,
          'album_name': ?track.album,
          if (seconds != null) 'duration': '$seconds',
        }),
        headers: _headers,
      );
      if (res.statusCode == 200) return _fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
      if (res.statusCode != 404) throw HttpException('lrclib ${res.statusCode}');
    }

    // Otherwise search and pick the closest length, preferring synced lyrics.
    final res = await http.get(
      Uri.https('lrclib.net', '/api/search', {'q': '$artist $title'.trim()}),
      headers: _headers,
    );
    if (res.statusCode != 200) throw HttpException('lrclib ${res.statusCode}');
    final results = (jsonDecode(utf8.decode(res.bodyBytes)) as List).cast<Map<String, dynamic>>();
    if (results.isEmpty) return null;
    double score(Map<String, dynamic> r) {
      final d = (r['duration'] as num?)?.toDouble();
      final off = seconds == null || d == null ? 10.0 : (d - seconds).abs();
      return off + (r['syncedLyrics'] == null ? 15 : 0);
    }

    final best = [...results]..sort((a, b) => score(a).compareTo(score(b)));
    // Way off in length is a different recording (or a different song).
    if (seconds != null && score(best.first) > 30) return null;
    return _fromJson(best.first);
  }

  static Lyrics? _fromJson(Map<String, dynamic> j) {
    if (j['instrumental'] == true) return const Lyrics(instrumental: true, source: 'LRCLIB');
    var plain = (j['plainLyrics'] as String?)?.trim();
    if (plain != null && plain.isEmpty) plain = null;
    final synced = j['syncedLyrics'] as String?;
    if (synced != null && synced.trim().isNotEmpty) {
      final l = Lyrics.parse(synced, source: 'LRCLIB');
      // The plain text too, in case the timed version turns out to be junk.
      if (l.synced) return Lyrics(lines: l.lines, plain: plain, source: 'LRCLIB');
    }
    if (plain == null) return null;
    return Lyrics(plain: plain, source: 'LRCLIB');
  }
}

/// Lyrics a person added to a downloaded song, kept in the app's own folder
/// (never inside the audio file, never touched by online sources). One file
/// per YouTube video, so the streamed and the downloaded copy of a song share them.
abstract final class UserLyrics {
  /// Tests point this at a folder of their own.
  @visibleForTesting
  static Directory? dirOverride;

  static Future<Directory> _dir() async {
    if (dirOverride case final dir?) return dir;
    final base = await getApplicationSupportDirectory();
    return Directory(p.join(base.path, 'my-lyrics'));
  }

  static final _videoUrl = RegExp(r'[?&]v=([A-Za-z0-9_-]{11})');

  /// The file's name stem for [track]: its video id, or a hash of its id.
  static String keyOf(Track track) {
    final id = track.videoId ?? _videoUrl.firstMatch(track.sourceUrl ?? '')?[1];
    return id ?? sha1.convert(utf8.encode(track.id)).toString();
  }

  static Future<File> _file(Track track) async => File(p.join((await _dir()).path, '${keyOf(track)}.lrc'));

  /// The text the person saved, null if there is none.
  static Future<String?> read(Track track) async {
    try {
      final file = await _file(track);
      if (!await file.exists()) return null;
      final text = await file.readAsString();
      return text.trim().isEmpty ? null : text;
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(Track track, String text) async {
    final file = await _file(track);
    await file.parent.create(recursive: true);
    // Aside and renamed: a write cut short never replaces good lyrics.
    final part = File('${file.path}.part');
    await part.writeAsString(text.trim());
    await part.rename(file.path);
    LyricsService.forget(track);
  }

  static Future<void> remove(Track track) async {
    final file = await _file(track);
    if (await file.exists()) await file.delete();
    LyricsService.forget(track);
  }
}

/// How much later (or, negative, earlier) the person wants a song's timed
/// lyrics, kept per song: another version of a song can start sooner or later.
abstract final class LyricsTiming {
  static final _shifts = <String, ValueNotifier<Duration>>{};

  static String _key(Track track) => 'lyrics.shift.${UserLyrics.keyOf(track)}';

  /// The shift for [track]; zero until the saved one is read.
  static ValueNotifier<Duration> of(Track track) {
    final key = _key(track);
    if (_shifts[key] case final known?) return known;
    final shift = _shifts[key] = ValueNotifier(Duration.zero);
    SharedPreferences.getInstance().then((prefs) {
      if (prefs.getInt(key) case final ms?) shift.value = Duration(milliseconds: ms);
    }, onError: (Object e) => debugPrint('Lyrics timing: could not read: $e'));
    return shift;
  }

  static Future<void> set(Track track, Duration shift) async {
    of(track).value = shift;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _key(track);
      shift == Duration.zero ? await prefs.remove(key) : await prefs.setInt(key, shift.inMilliseconds);
    } catch (e) {
      debugPrint('Lyrics timing: could not save: $e');
    }
  }
}

/// Lyrics found online, kept on disk so the next look (even after a restart)
/// doesn't ask the sites again. One JSON file per song; the newest few hundred stay.
abstract final class LyricsCache {
  /// Tests point this at a folder of their own.
  @visibleForTesting
  static Directory? dirOverride;

  static const _keep = 300;
  static const _maxAge = Duration(days: 30);

  static Future<Directory> _dir() async {
    if (dirOverride case final dir?) return dir;
    final base = await getApplicationSupportDirectory();
    return Directory(p.join(base.path, 'lyrics-cache'));
  }

  static int _ms(Duration d) => d.inMilliseconds;

  static Map<String, dynamic> _toJson(Lyrics l) => {
    'at': DateTime.now().millisecondsSinceEpoch,
    'source': l.source,
    'plain': l.plain,
    'instrumental': l.instrumental,
    if (l.otherVersion) 'otherVersion': true,
    'lines': [
      for (final line in l.lines)
        {
          't': _ms(line.time),
          'x': line.text,
          if (line.end != null) 'e': _ms(line.end!),
          if (line.words.isNotEmpty)
            'w': [
              for (final w in line.words) [_ms(w.start), _ms(w.end), w.text],
            ],
        },
    ],
  };

  static Lyrics _fromJson(Map<String, dynamic> j) => Lyrics(
    source: j['source'] as String? ?? '',
    plain: j['plain'] as String?,
    instrumental: j['instrumental'] == true,
    otherVersion: j['otherVersion'] == true,
    lines: [
      for (final line in (j['lines'] as List? ?? const []).cast<Map<String, dynamic>>())
        LyricLine(
          Duration(milliseconds: line['t'] as int),
          line['x'] as String,
          end: line['e'] == null ? null : Duration(milliseconds: line['e'] as int),
          words: [
            for (final w in (line['w'] as List? ?? const []).cast<List>())
              LyricWord(Duration(milliseconds: w[0] as int), Duration(milliseconds: w[1] as int), w[2] as String),
          ],
        ),
    ],
  );

  static Future<File> _file(Track track) async => File(p.join((await _dir()).path, '${UserLyrics.keyOf(track)}.json'));

  /// What was kept for [track], null when nothing (or it is old, or unreadable).
  static Future<Lyrics?> read(Track track) async {
    try {
      final file = await _file(track);
      if (!await file.exists()) return null;
      final j = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final at = DateTime.fromMillisecondsSinceEpoch(j['at'] as int);
      if (DateTime.now().difference(at) > _maxAge) return null;
      final l = _fromJson(j);
      return l.isEmpty ? null : l;
    } catch (e) {
      debugPrint('Lyrics cache: could not read: $e');
      return null;
    }
  }

  static Future<void> write(Track track, Lyrics lyrics) async {
    try {
      final file = await _file(track);
      await file.parent.create(recursive: true);
      // Aside and renamed: a write cut short never leaves a broken file.
      final part = File('${file.path}.part');
      await part.writeAsString(jsonEncode(_toJson(lyrics)));
      await part.rename(file.path);
      await _prune(file.parent);
    } catch (e) {
      debugPrint('Lyrics cache: could not write: $e');
    }
  }

  static Future<void> _prune(Directory dir) async {
    final files = [
      for (final f in await dir.list().toList())
        if (f is File && f.path.endsWith('.json')) (file: f, time: (await f.stat()).modified),
    ];
    if (files.length <= _keep) return;
    files.sort((a, b) => a.time.compareTo(b.time));
    for (final old in files.take(files.length - _keep)) {
      await old.file.delete();
    }
  }
}

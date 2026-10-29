import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';
import 'player_controller.dart';
import 'private_files.dart';
import 'ytmusic_play_report.dart';

/// What the history remembers about a song: enough to list it and play it again.
@immutable
class SongInfo {
  const SongInfo({
    required this.key,
    required this.title,
    required this.artist,
    this.album,
    this.videoId,
    this.artworkUrl,
  });

  /// [Track.id]: the file's address, or `yt:<videoId>` for a streamed song.
  final String key;
  final String title;
  final String artist;
  final String? album;
  final String? videoId;

  /// Only kept for a streamed song whose cover isn't YouTube's default for it.
  final String? artworkUrl;

  factory SongInfo.of(Track t) => SongInfo(
    key: t.id,
    title: t.title,
    artist: t.artist,
    album: t.album,
    videoId: t.videoId,
    artworkUrl: t.videoId != null && t.artworkUrl != _defaultArt(t.videoId!) ? t.artworkUrl : null,
  );

  static String _defaultArt(String videoId) => 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';

  /// A track to show and play this song with when the library no longer has it.
  Track toTrack() {
    final id = videoId;
    if (id != null) return Track.youtube(videoId: id, title: title, artist: artist, artworkUrl: artworkUrl);
    return Track(id: key, uri: Uri.parse(key), title: title, artist: artist, album: album, tagged: true);
  }

  @override
  bool operator ==(Object other) =>
      other is SongInfo &&
      other.key == key &&
      other.title == title &&
      other.artist == artist &&
      other.album == album &&
      other.videoId == videoId &&
      other.artworkUrl == artworkUrl;

  @override
  int get hashCode => Object.hash(key, title, artist, album, videoId, artworkUrl);
}

/// A play that counted: [heard] of [track] was listened to.
class PlayedSong {
  const PlayedSong(this.track, this.heard);
  final Track track;
  final Duration heard;
}

/// Decides when a play counts for the listening history: after 30 seconds of
/// listening, or when the song ends. Built on [PlayReportClock] (the same rule
/// YouTube Music's history uses), but a play is handed over when it is over
/// (the song changed, ended, looped or was paused), so the time heard is the
/// real time and not just the threshold.
///
/// Pure: feed it what the player says.
class PlayTracker {
  PlayTracker({Duration threshold = const Duration(seconds: 30)}) : _clock = PlayReportClock(threshold: threshold);

  final PlayReportClock _clock;
  String? _id;
  Track? _track;
  bool _counted = false;
  bool _handedOver = false;

  /// One look at the player; returns the plays that finished with it (usually none).
  List<PlayedSong> tick({
    required Track? track,
    required Duration position,
    required bool playing,
    required bool ended,
  }) {
    final out = <PlayedSong>[];
    if (track?.id != _id) {
      _finish(out);
      _id = track?.id;
      _track = track;
      _counted = false;
      _handedOver = false;
    }
    final before = _clock.heard;
    final due = _clock.tick(trackId: _id, position: position, playing: playing, ended: ended);
    if (_clock.heard < before) {
      // The clock started over: the song looped back (or repeated) after a pass worth counting.
      if (_counted && !_handedOver) out.add(PlayedSong(_track!, before));
      _counted = false;
      _handedOver = false;
    }
    if (due) _counted = true;
    // Over for now: the song ended, or it was paused after it had counted.
    if (_counted && !_handedOver && (ended || !playing)) {
      _handedOver = true;
      final heard = _clock.heard;
      out.add(PlayedSong(_track!, heard < const Duration(seconds: 1) ? const Duration(seconds: 1) : heard));
    }
    return out;
  }

  /// Hands over the play in progress, if it counts (the app is closing).
  List<PlayedSong> finish() {
    final out = <PlayedSong>[];
    _finish(out);
    return out;
  }

  void _finish(List<PlayedSong> out) {
    if (_counted && !_handedOver && _track != null) out.add(PlayedSong(_track!, _clock.heard));
    _counted = false;
    _handedOver = true;
  }
}

/// Everything read from the history file, as plain lists.
class HistoryData {
  /// Songs by index (the `i` of their line).
  final List<SongInfo> songs = [];

  /// One entry per play, oldest first: when (seconds since 1970), which song, seconds heard.
  final List<int> at = [];
  final List<int> song = [];
  final List<int> heard = [];

  int get plays => at.length;
}

/// The listening history file: a few bytes per play, on this device only.
///
/// JSON lines, appended to and never rewritten while the app runs:
///
/// ```
/// {"fmt":1}
/// {"i":0,"k":"file:///music/a.flac","t":"Title","a":"Artist","b":"Album"}   a song, once
/// [1735000000,0,214]                                                         a play: when, song, seconds heard
/// ```
///
/// A song's details are written once and plays refer to it by number, so a
/// play costs about 25 bytes (10,000 plays: roughly 250 KB, plus about 120
/// bytes for each different song). Past [maxPlays] the oldest plays are
/// dropped down to [keepPlays] and the file is rewritten without the songs
/// nothing refers to any more.
///
/// A play is written about [flushAfter] after it happened (or sooner in a
/// batch of 20), by the platform's file I/O, never on the UI thread. Nothing
/// here touches the network.
class PlayHistory extends ChangeNotifier {
  PlayHistory({File? file, this.flushAfter = const Duration(seconds: 15), this.maxPlays = 150000, int? keepPlays})
    : keepPlays = keepPlays ?? (maxPlays * 4 ~/ 5),
      _fileOverride = file,
      _useOverride = file != null;

  /// The app's history. Tests may swap it for one with a temporary file.
  static PlayHistory instance = PlayHistory();

  static const enabledKey = 'history.enabled.v1';
  static const _name = 'listening_history.jsonl';

  final Duration flushAfter;

  /// Plays kept before the oldest are dropped, and how many are kept when that happens.
  final int maxPlays;
  final int keepPlays;

  final File? _fileOverride;
  final bool _useOverride;

  final _songs = <SongInfo>[];
  final _index = <String, int>{};
  final _songPlays = <int>[];
  final _songLast = <int>[];
  final _at = <int>[];
  final _song = <int>[];
  final _heard = <int>[];

  bool _enabled = true;
  bool _loaded = false;
  int _revision = 0;
  File? _file;
  final _pending = <String>[];
  Timer? _timer;
  bool _needsNewline = false;
  bool _needsHeader = true;
  Future<void> _io = Future.value();

  PlayTracker _tracker = PlayTracker();
  PlayerController? _controller;
  final _subs = <StreamSubscription<dynamic>>[];

  /// Whether plays are being kept ("Keep a listening history on this device").
  bool get enabled => _enabled;

  /// Bumped with every change; derived views cache against it.
  int get revision => _revision;

  /// Plays kept.
  int get length => _at.length;

  /// Different songs played.
  int get songCount => _songs.length;

  bool get isEmpty => _at.isEmpty;

  // Reading ─────────────────────────────────────────────────────────────────

  /// When play [i] happened, in seconds since 1970.
  int atSec(int i) => _at[i];

  /// Which song play [i] was (an index for [songInfo]).
  int songIndex(int i) => _song[i];

  /// Seconds heard of play [i].
  int heardSec(int i) => _heard[i];

  SongInfo songInfo(int song) => _songs[song];

  /// How many plays song [key] has (0 when it was never played).
  int playsOf(String key) => switch (_index[key]) {
    final i? => _songPlays[i],
    _ => 0,
  };

  /// When song [key] was last played, in seconds since 1970 (null if never).
  int? lastPlayedSec(String key) => switch (_index[key]) {
    final i? => _songLast[i],
    _ => null,
  };

  /// Every song with its play count and last play time (seconds), in the order first played.
  Iterable<(SongInfo, int, int)> get songs sync* {
    for (var i = 0; i < _songs.length; i++) {
      yield (_songs[i], _songPlays[i], _songLast[i]);
    }
  }

  /// Years that have at least one play, newest first.
  List<int> get years {
    final out = <int>{};
    int? lastDay;
    for (final s in _at) {
      final day = s ~/ 86400; // a year changes at most once a day: skip the rest of a day
      if (day == lastDay) continue;
      lastDay = day;
      out.add(DateTime.fromMillisecondsSinceEpoch(s * 1000).year);
    }
    return out.toList()..sort((a, b) => b.compareTo(a));
  }

  // Recording ───────────────────────────────────────────────────────────────

  /// Keeps one play of [t]. [at] is for tests; it defaults to now.
  void record(Track t, Duration heard, {DateTime? at}) {
    if (!_enabled) return;
    final info = SongInfo.of(t);
    var i = _index[info.key];
    if (i == null) {
      i = _songs.length;
      _songs.add(info);
      _index[info.key] = i;
      _songPlays.add(0);
      _songLast.add(0);
      _pending.add(_encodeSong(i, info));
    } else if (_songs[i] != info) {
      // Retagged since: the latest details are the ones shown.
      _songs[i] = info;
      _pending.add(_encodeSong(i, info));
    }
    final sec = (at ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    final seconds = heard.inSeconds < 1 ? 1 : heard.inSeconds;
    _at.add(sec);
    _song.add(i);
    _heard.add(seconds);
    _songPlays[i]++;
    if (sec > _songLast[i]) _songLast[i] = sec;
    _pending.add('[$sec,$i,$seconds]');
    _revision++;
    notifyListeners();
    if (_pending.length >= 20) {
      unawaited(flush());
    } else {
      _timer ??= Timer(flushAfter, () => unawaited(flush()));
    }
  }

  /// Writes what is waiting. Safe to call at any time; calls queue up.
  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    if (_pending.isEmpty) return _io;
    final lines = List<String>.of(_pending);
    _pending.clear();
    final tooBig = _at.length > maxPlays;
    return _io = _io.then((_) async {
      if (tooBig) return _compact();
      await _append(lines);
    });
  }

  Future<void> _append(List<String> lines) async {
    final file = await _resolveFile();
    if (file == null) return;
    try {
      final b = StringBuffer();
      if (_needsHeader) b.writeln('{"fmt":1}');
      if (_needsNewline) b.writeln();
      for (final l in lines) {
        b.writeln(l);
      }
      await file.writeAsString(b.toString(), mode: FileMode.append, flush: true);
      _needsHeader = false;
      _needsNewline = false;
    } catch (e) {
      debugPrint('Saving the listening history failed: $e');
    }
  }

  /// Drops the oldest plays past [keepPlays] and rewrites the file.
  Future<void> _compact() async {
    final data = HistoryData()
      ..songs.addAll(_songs)
      ..at.addAll(_at)
      ..song.addAll(_song)
      ..heard.addAll(_heard);
    final kept = trimmed(data, keepPlays);
    _adopt(kept);
    final file = await _resolveFile();
    if (file == null) return;
    try {
      await _writeAll(file, kept);
      _needsHeader = false;
      _needsNewline = false;
    } catch (e) {
      debugPrint('Trimming the listening history failed: $e');
    }
    _revision++;
    notifyListeners();
  }

  // Loading ─────────────────────────────────────────────────────────────────

  /// Reads the setting and the file (once). Plays recorded before it finished are kept.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(enabledKey) ?? true;
    } catch (_) {
      // No preferences (a bare test): on by default.
    }
    final file = await _resolveFile();
    if (file != null) {
      try {
        final parsed = await _read(file);
        if (parsed != null) {
          _needsNewline = parsed.$2;
          _needsHeader = !parsed.$3;
          _mergeLoaded(parsed.$1);
        }
      } catch (e) {
        debugPrint('Listening history unreadable, starting empty: $e');
      }
    }
    _revision++;
    notifyListeners();
    if (_at.length > maxPlays) unawaited(flush());
    if (_at.length > maxPlays) {
      _io = _io.then((_) => _compact());
    }
  }

  // Static, so the isolate's closure doesn't carry the history (and its pending futures) with it.
  static Future<(HistoryData, bool, bool)?> _read(File file) => Isolate.run(() => _readFile(file));

  static (HistoryData, bool, bool)? _readFile(File file) {
    if (!file.existsSync()) return null;
    final text = file.readAsStringSync();
    return (parse(text), text.isNotEmpty && !text.endsWith('\n'), text.isNotEmpty);
  }

  static Future<void> _writeAll(File file, HistoryData data) =>
      Isolate.run(() => PrivateFiles.writeSync(file, encode(data)));

  void _mergeLoaded(HistoryData data) {
    // Whatever was recorded while the file was being read goes after what was in it.
    final mine = HistoryData()
      ..songs.addAll(_songs)
      ..at.addAll(_at)
      ..song.addAll(_song)
      ..heard.addAll(_heard);
    final fresh = _pending.isNotEmpty || mine.plays > 0;
    _adopt(data);
    if (fresh) {
      for (var p = 0; p < mine.plays; p++) {
        final info = mine.songs[mine.song[p]];
        var i = _index[info.key];
        if (i == null) {
          i = _songs.length;
          _songs.add(info);
          _index[info.key] = i;
          _songPlays.add(0);
          _songLast.add(0);
        }
        _at.add(mine.at[p]);
        _song.add(i);
        _heard.add(mine.heard[p]);
        _songPlays[i]++;
        if (mine.at[p] > _songLast[i]) _songLast[i] = mine.at[p];
      }
    }
  }

  void _adopt(HistoryData data) {
    _songs
      ..clear()
      ..addAll(data.songs);
    _index
      ..clear()
      ..addAll({for (final (i, s) in data.songs.indexed) s.key: i});
    _at
      ..clear()
      ..addAll(data.at);
    _song
      ..clear()
      ..addAll(data.song);
    _heard
      ..clear()
      ..addAll(data.heard);
    _songPlays
      ..clear()
      ..addAll(List.filled(_songs.length, 0));
    _songLast
      ..clear()
      ..addAll(List.filled(_songs.length, 0));
    for (var p = 0; p < _at.length; p++) {
      final i = _song[p];
      _songPlays[i]++;
      if (_at[p] > _songLast[i]) _songLast[i] = _at[p];
    }
  }

  Future<File?> _resolveFile() async {
    if (_useOverride) return _fileOverride;
    if (_file != null) return _file;
    try {
      return _file = await PrivateFiles.file(_name);
    } catch (_) {
      return null; // no app folder (widget tests): the history lives in memory only
    }
  }

  // Settings ────────────────────────────────────────────────────────────────

  /// Turns keeping the history on or off. Off stops recording; what is saved stays until [clear].
  Future<void> setEnabled(bool value) async {
    if (value == _enabled) return;
    _enabled = value;
    _tracker = PlayTracker();
    if (!value) await flush();
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setBool(enabledKey, value);
    } catch (e) {
      debugPrint('Saving the history setting failed: $e');
    }
  }

  /// Deletes the whole history, here and on disk.
  Future<void> clear() async {
    _timer?.cancel();
    _timer = null;
    _pending.clear();
    _adopt(HistoryData());
    _tracker = PlayTracker();
    _revision++;
    notifyListeners();
    final done = _io = _io.then((_) async {
      final file = await _resolveFile();
      try {
        if (file != null && file.existsSync()) await file.delete();
      } catch (e) {
        debugPrint('Deleting the listening history failed: $e');
      }
      _needsHeader = true;
      _needsNewline = false;
    });
    await done;
  }

  // Following the player ────────────────────────────────────────────────────

  /// Loads the history and starts keeping plays of [controller]'s player.
  Future<void> start(PlayerController controller) async {
    _controller = controller;
    await load();
    for (final s in _subs) {
      await s.cancel();
    }
    _subs
      ..clear()
      ..add(controller.player.positionStream.listen((_) => _pollThrottled()))
      ..add(controller.player.playerStateStream.listen((_) => _poll()))
      ..add(controller.player.sequenceStateStream.listen((_) => _poll()));
  }

  /// How often position ticks (several a second) are looked at; changes of song or state are not held back.
  static const pollEvery = Duration(seconds: 1);
  DateTime? _lastPoll;

  /// Clock for [pollEvery] (tests set their own).
  @visibleForTesting
  DateTime Function() clock = DateTime.now;

  void _pollThrottled() {
    final at = clock();
    final last = _lastPoll;
    if (last != null && at.difference(last) < pollEvery) return;
    _poll();
  }

  void _poll() {
    _lastPoll = clock();
    final c = _controller;
    if (c == null || !_enabled) return;
    final plays = _tracker.tick(
      track: c.currentTrack,
      position: c.position,
      playing: c.isPlaying,
      ended: c.player.processingState == ProcessingState.completed,
    );
    for (final p in plays) {
      record(p.track, p.heard);
    }
  }

  /// Stops following the player and writes what is waiting.
  Future<void> stop() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    if (_enabled) {
      for (final p in _tracker.finish()) {
        record(p.track, p.heard);
      }
    }
    _controller = null;
    await flush();
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  // The file's format ───────────────────────────────────────────────────────

  static String _encodeSong(int i, SongInfo s) => jsonEncode({
    'i': i,
    'k': s.key,
    't': s.title,
    'a': s.artist,
    if (s.album != null) 'b': s.album,
    if (s.videoId != null) 'v': s.videoId,
    if (s.artworkUrl != null) 'u': s.artworkUrl,
  });

  /// The whole file for [data].
  @visibleForTesting
  static String encode(HistoryData data) {
    final b = StringBuffer('{"fmt":1}\n');
    for (final (i, s) in data.songs.indexed) {
      b.writeln(_encodeSong(i, s));
    }
    for (var p = 0; p < data.plays; p++) {
      b.writeln('[${data.at[p]},${data.song[p]},${data.heard[p]}]');
    }
    return b.toString();
  }

  /// Reads a history file. A line that doesn't make sense (a write cut short) is skipped, not fatal.
  @visibleForTesting
  static HistoryData parse(String text) {
    final defs = <int, SongInfo>{};
    final at = <int>[];
    final song = <int>[];
    final heard = <int>[];
    for (final raw in LineSplitter.split(text)) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      try {
        if (line.codeUnitAt(0) == 0x5B) {
          // [
          if (!line.endsWith(']')) continue;
          final parts = line.substring(1, line.length - 1).split(',');
          if (parts.length != 3) continue;
          final a = int.parse(parts[0]);
          final s = int.parse(parts[1]);
          final h = int.parse(parts[2]);
          at.add(a);
          song.add(s);
          heard.add(h);
        } else if (line.codeUnitAt(0) == 0x7B) {
          // {
          final j = jsonDecode(line) as Map<String, dynamic>;
          if (j['i'] case final int i when j['k'] is String && j['t'] is String) {
            defs[i] = SongInfo(
              key: j['k'] as String,
              title: j['t'] as String,
              artist: j['a'] as String? ?? Track.unknownArtist,
              album: j['b'] as String?,
              videoId: j['v'] as String?,
              artworkUrl: j['u'] as String?,
            );
          }
        }
      } catch (_) {
        // Skipped: a cut-short last line.
      }
    }
    // Plays of a song with no line (damaged file) go; the rest are renumbered 0..n.
    final order = defs.keys.toList()..sort();
    final renumber = {for (final (n, i) in order.indexed) i: n};
    final out = HistoryData()..songs.addAll([for (final i in order) defs[i]!]);
    for (var p = 0; p < at.length; p++) {
      final n = renumber[song[p]];
      if (n == null) continue;
      out.at.add(at[p]);
      out.song.add(n);
      out.heard.add(heard[p]);
    }
    return out;
  }

  /// [data] with only its newest [keep] plays, and only the songs those refer to.
  @visibleForTesting
  static HistoryData trimmed(HistoryData data, int keep) {
    final from = data.plays > keep ? data.plays - keep : 0;
    final used = <int, int>{};
    final out = HistoryData();
    for (var p = from; p < data.plays; p++) {
      final i = used.putIfAbsent(data.song[p], () {
        out.songs.add(data.songs[data.song[p]]);
        return out.songs.length - 1;
      });
      out.at.add(data.at[p]);
      out.song.add(i);
      out.heard.add(data.heard[p]);
    }
    return out;
  }
}

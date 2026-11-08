import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';
import '../platform/host.dart';
import '../platform/network.dart';
import 'lyrics.dart';
import 'lyrics_translation.dart';
import 'metadata.dart';
import 'player_controller.dart';

/// The system's media controls: Android's notification and lock screen,
/// Control Center on iOS / macOS, and MPRIS on Linux (the desktop's media
/// widget, media keys, `playerctl`). Mirrors [PlayerController]; every button
/// goes back to it.
class MediaSession extends BaseAudioHandler with SeekHandler {
  MediaSession._(this._c) {
    final p = _c.player;
    // Clients extrapolate the position from the last update and the speed, so
    // state changes and seeks are enough; no per-tick updates.
    _subs.addAll([
      p.playerStateStream.listen((_) => _publishState()),
      p.positionDiscontinuityStream.listen((_) => _publishState()),
      p.durationStream.listen((_) => _publishItem()),
      // Where the song is decides the line shown: a seek, a pause or play moves it.
      p.playerStateStream.listen((_) => _followLyrics()),
      p.positionDiscontinuityStream.listen((_) => _followLyrics()),
    ]);
    showLyrics.addListener(_onShowLyrics);
    LyricsTranslation.romanize.addListener(_loadPronunciation);
    _c.addListener(_onController);
    _publishItem();
    _publishState();
  }

  /// Starts the session; null where the platform has none (Windows).
  static Future<MediaSession?> start(PlayerController c) async {
    if (Host.isWindows) return null;
    try {
      return await AudioService.init(
        builder: () => MediaSession._(c),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'dev.riflay.riflay.playback',
          // Also the player's name in MPRIS (Linux media widgets).
          androidNotificationChannelName: 'Riflay',
          androidNotificationIcon: 'mipmap/ic_launcher_monochrome',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
        ),
      );
    } catch (e) {
      debugPrint('Media controls unavailable: $e');
      return null;
    }
  }

  /// The line being sung in place of the artist, in the notification, on the lock screen and on a car's
  /// display (which reads the same fields). Phones only: on a computer the media widget names the artist. Saved.
  static final showLyrics = ValueNotifier(true);
  static bool get lyricsSupported => Host.isAndroid || Host.isIOS;

  static Future<void> loadLyricsSetting() async {
    final p = await SharedPreferences.getInstance();
    showLyrics.value = p.getBool(_lyricsKey) ?? true;
    showLyrics.addListener(() => p.setBool(_lyricsKey, showLyrics.value));
  }

  static const _lyricsKey = 'lyrics.lockScreen';

  final PlayerController _c;
  final _subs = <StreamSubscription<Object?>>[];

  /// The song as published, with its artist: the lyric line takes the artist's place over a copy of it.
  MediaItem? _item;
  Lyrics? _lyrics;
  String? _lyricsFor;

  /// Each line's pronunciation, fetched once per song while the lyrics page's Pronunciation is on.
  List<LineExtras>? _extras;
  Timer? _nextLine;
  String? _shownLine;
  String? _shownId;
  bool? _shownPlaying;

  /// Swiped away from Recents: the session is put away until something plays.
  bool _closed = false;

  /// Whether the session says "playing". At the end of the queue just_audio keeps `playing` on although
  /// nothing sounds; the system must then offer Play (which starts the queue over), not Pause.
  bool get _playing => _c.isPlaying && (_c.casting || _c.player.processingState != ProcessingState.completed);

  void _onController() {
    if (_c.currentTrack?.id != _shownId) {
      _publishItem();
      _loadLyrics();
    }
    if (_playing != _shownPlaying) _publishState();
  }

  Future<void> _publishItem() async {
    final t = _c.currentTrack;
    _shownId = t?.id;
    // The web build's tab is named after the song too (a no-op in native builds).
    pageTitle = t == null ? 'Riflay' : [t.title, if (t.artist.isNotEmpty) t.artist].join(' · ');
    if (t == null) return mediaItem.add(null);
    final item = MediaItem(
      id: t.id,
      title: t.title,
      artist: t.artist,
      album: t.album,
      duration: _c.duration ?? t.duration,
      artUri: t.streams && t.artworkUrl != null ? Uri.tryParse(t.artworkUrl!) : null,
    );
    _item = item;
    _shownLine = null;
    _publishLine();
    if (item.artUri == null) {
      // Local cover art lives in the file's tags; the system needs a file or URL.
      final art = await _artFile(t);
      if (art != null && _shownId == t.id) {
        _item = item.copyWith(artUri: art.uri);
        _publishLine(force: true);
      }
    }
  }

  void _onShowLyrics() {
    _loadLyrics();
    _followLyrics();
  }

  /// The current song's synced lyrics, when the line is to be shown.
  Future<void> _loadLyrics() async {
    final t = _c.currentTrack;
    _lyrics = null;
    _extras = null;
    _lyricsFor = t?.id;
    _followLyrics();
    if (t == null || !lyricsSupported || !showLyrics.value) return;
    try {
      final l = await LyricsService.forTrack(t);
      if (_lyricsFor != t.id || !l.synced) return;
      _lyrics = l;
      _followLyrics();
      _loadPronunciation();
    } catch (_) {
      // No lyrics site reachable: the artist stays.
    }
  }

  /// How the song's lines in another script are read (kanji, hangul, Cyrillic…), for the line shown. One request
  /// per song, the same one the lyrics page makes (and caches); the line ticks over without asking again.
  Future<void> _loadPronunciation() async {
    final l = _lyrics, id = _lyricsFor;
    if (!LyricsTranslation.romanize.value) {
      _extras = null;
      return _publishLine();
    }
    if (l == null || _extras != null) return;
    final lines = [for (final line in l.lines) line.text];
    if (!lines.any(LyricsTranslation.hasNonLatin)) return;
    try {
      final extras = await LyricsTranslation.of(lines);
      if (_lyricsFor != id || !identical(_lyrics, l) || !LyricsTranslation.romanize.value) return;
      _extras = extras;
      _publishLine();
    } catch (_) {
      // Unreachable: the line shows without it.
    }
  }

  /// Shows the line being sung, and wakes for the next one: one timer per line, not a clock ticking.
  void _followLyrics() {
    _nextLine?.cancel();
    final l = _lyrics, t = _c.currentTrack;
    if (l == null || t == null || !showLyrics.value || !lyricsSupported) return _publishLine();
    final at = _c.position - LyricsTiming.of(t).value;
    _publishLine();
    if (!_c.isPlaying) return;
    final next = nextLineAt(l, at);
    if (next != null) {
      // Tempo plays the song faster or slower than the clock.
      final speed = _c.player.speed <= 0 ? 1.0 : _c.player.speed;
      _nextLine = Timer(Duration(microseconds: ((next - at).inMicroseconds / speed).round()), _followLyrics);
    }
  }

  /// The song's item, with the line being sung (if any) as its artist.
  void _publishLine({bool force = false}) {
    final item = _item, t = _c.currentTrack, l = _lyrics;
    if (item == null || t == null) return;
    final line = l == null || !showLyrics.value || !lyricsSupported
        ? null
        : lineFor(l, _c.position - LyricsTiming.of(t).value, extras: _extras);
    if (!force && line == _shownLine && mediaItem.value?.id == item.id) return;
    _shownLine = line;
    mediaItem.add(line == null ? item : item.copyWith(artist: line, album: item.artist));
  }

  /// The words of the line sung at [position], or null between lines (an empty or ♪ line, or before the first).
  /// A little early, as the lyrics page lights it. A line in another script is followed by its pronunciation from
  /// [extras] (one per line of [lyrics]): "今日もまた始まる — kyō mo mata hajimaru", one field being all a phone's
  /// notification and lock screen show under the title.
  @visibleForTesting
  static String? lineFor(Lyrics lyrics, Duration position, {List<LineExtras>? extras}) {
    final i = lyrics.lineAt(position + _early);
    if (i < 0) return null;
    final line = lyrics.lines[i];
    if (line.end case final end? when position + _early >= end) return null;
    final text = line.text.trim();
    if (text.isEmpty || RegExp(r'^[♪♫\s]+$').hasMatch(text)) return null;
    final said = extras != null && i < extras.length && LyricsTranslation.hasNonLatin(text)
        ? extras[i].romanized
        : null;
    return said == null ? text : '$text — $said';
  }

  /// When the shown line next changes after [position]: the next line's start, or this one's end.
  @visibleForTesting
  static Duration? nextLineAt(Lyrics lyrics, Duration position) {
    final i = lyrics.lineAt(position + _early);
    final candidates = [
      if (i >= 0 && lyrics.lines[i].end != null) lyrics.lines[i].end!,
      if (i + 1 < lyrics.lines.length) lyrics.lines[i + 1].time,
    ].where((d) => d > position + _early).toList()..sort();
    return candidates.isEmpty ? null : candidates.first - _early;
  }

  static const _early = Duration(milliseconds: 150);

  void _publishState() {
    final p = _c.player;
    final playing = _playing;
    if (playing) _closed = false;
    // Android's service forgets the song when it's stopped and started again,
    // which left a notification with only the app's name. Starting to play
    // sends the song along every time.
    if (playing && _shownPlaying != true && mediaItem.value != null) mediaItem.add(mediaItem.value);
    _shownPlaying = playing;
    // Idle tells Android the session is over: it stops the service and takes
    // the notification down. Only when nothing is left to play, not when the
    // player is idle for a moment between or after songs.
    final over = _closed || _c.currentTrack == null;
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {MediaAction.seek},
        androidCompactActionIndices: const [0, 1, 2],
        processingState: over
            ? AudioProcessingState.idle
            : _c.casting
            ? (_c.isBuffering ? AudioProcessingState.buffering : AudioProcessingState.ready)
            : switch (p.processingState) {
                ProcessingState.idle => AudioProcessingState.ready,
                ProcessingState.loading => AudioProcessingState.loading,
                ProcessingState.buffering => AudioProcessingState.buffering,
                ProcessingState.ready => AudioProcessingState.ready,
                ProcessingState.completed => AudioProcessingState.completed,
              },
        playing: playing,
        updatePosition: _c.position,
        bufferedPosition: p.bufferedPosition,
        speed: p.speed,
      ),
    );
  }

  static Future<Directory>? _artDir;

  /// This user's cache folder, not the temporary one: on Linux that is the
  /// shared /tmp, where another account could plant a link under a cover's
  /// name (and have the cover written over a file of yours) or see what you play.
  static Future<Directory> _openArtDir() async {
    final dir = Directory(p.join((await getApplicationCacheDirectory()).path, 'now-playing-art'));
    await dir.create(recursive: true);
    // A cover for each song played: keep the newest few.
    final old = await dir.list().where((e) => e is File).cast<File>().toList();
    if (old.length > 64) {
      final dated = [for (final f in old) (f, (await f.stat()).modified)]..sort((a, b) => b.$2.compareTo(a.$2));
      for (final (f, _) in dated.skip(32)) {
        f.delete().ignore();
      }
    }
    return dir;
  }

  static Future<File?> _artFile(Track t) async {
    final bytes = Metadata.cachedArtwork(t) ?? await Metadata.artwork(t);
    if (bytes == null) return null;
    final dir = await (_artDir ??= _openArtDir());
    // Named after the album and the cover's size, not a hash of the picture:
    // hashing a hi-res cover on every song change took tens of milliseconds.
    final name = sha1.convert(utf8.encode('${t.albumKey ?? t.id}\u0000${bytes.length}'));
    final file = File(p.join(dir.path, '$name.img'));
    if (!file.existsSync()) {
      final part = File('${file.path}.part');
      await part.writeAsBytes(bytes);
      await part.rename(file.path);
    }
    return file;
  }

  @override
  Future<void> play() => _c.play();

  @override
  Future<void> pause() => _c.pause();

  @override
  Future<void> stop() => _c.pause();

  /// The app was swiped away from Recents. Closing it stops the music and
  /// takes the notification down; leaving it with Home keeps playing.
  @override
  Future<void> onTaskRemoved() async {
    _closed = true;
    await _c.pause();
    _publishState();
  }

  @override
  Future<void> seek(Duration position) => _c.seek(position);

  @override
  Future<void> skipToNext() => _c.next();

  @override
  Future<void> skipToPrevious() => _c.previous();
}

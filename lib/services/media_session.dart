import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';
import '../platform/host.dart';
import '../platform/network.dart';
import 'language.dart';
import 'lyrics.dart';
import 'lyrics_translation.dart';
import 'metadata.dart';
import 'media_session/media_session_service.dart';
import 'player_controller.dart';

/// The audio_service media session: Android's MediaSession (notification, lock screen, Bluetooth and wired
/// headsets, Android Auto / Wear), MPRemoteCommandCenter and Now Playing on iOS / macOS (Control Center, AirPods,
/// media keys), MPRIS on Linux (the desktop's media widget, media keys, `playerctl`) and the browser's Media Session
/// on the web. One [MediaSessionAdapter] of [MediaSessionService]: it shows what the service sends and passes every
/// button back to it, which runs it on [PlayerController].
class AudioServiceAdapter implements MediaSessionAdapter {
  AudioServiceAdapter(this._c);

  final PlayerController _c;

  /// audio_service starts once per process; a second attach (a hot restart) reuses its handler.
  static MediaSession? _handler;

  @override
  String get name => 'audio_service';

  @override
  Future<bool> attach(void Function(MediaCommand) onCommand) async {
    // Windows has its own adapter (SMTC); audio_service has no Windows implementation.
    if (Host.isWindows) return false;
    if (_handler case final h?) {
      h._send = onCommand;
      h._closed = false;
      return true;
    }
    try {
      _handler = await AudioService.init(
        builder: () => MediaSession._(_c, onCommand),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'dev.riflay.riflay.playback',
          // Also the player's name in MPRIS (Linux media widgets).
          androidNotificationChannelName: 'Riflay',
          androidNotificationIcon: 'mipmap/ic_launcher_monochrome',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
          // Android decodes the notification's cover itself (Java heap, kept in an LRU of an eighth of it). Without
          // a size it decodes the whole embedded picture: a 3000 px cover is a 36 MB bitmap per song, which no
          // computer build pays. It is decoded at a power-of-two step at least this size (512–1023 px, ~1–4 MB),
          // still sharp in the notification and the lock-screen / quick-settings player.
          artDownscaleWidth: 512,
          artDownscaleHeight: 512,
        ),
      );
      return true;
    } catch (e) {
      debugPrint('Media controls unavailable: $e');
      return false;
    }
  }

  @override
  Future<void> update(MediaSessionState state) async => _handler?.show(state);

  /// audio_service can't be stopped and started again in one process: the session is put away (idle), and the
  /// next attach takes it back.
  @override
  Future<void> detach() async {
    final h = _handler;
    if (h == null) return;
    h._send = (_) {};
    h.show(MediaSessionState.empty);
  }
}

/// audio_service's handler: what Android's notification, the lock screen, Control Center, MPRIS and the browser
/// show, and where their buttons arrive. Shows [MediaSessionState]s; every button goes to [MediaSessionService].
class MediaSession extends BaseAudioHandler with SeekHandler {
  MediaSession._(this._c, this._send) {
    showLyrics.addListener(_onShowLyrics);
    LyricsTranslation.romanize.addListener(_loadPronunciation);
  }

  /// A handler outside audio_service, whose buttons go to [send].
  @visibleForTesting
  factory MediaSession.test(PlayerController c, void Function(MediaCommand) send) => MediaSession._(c, send);

  /// The line being sung in place of the artist, in the notification, on the lock screen and on a car's
  /// display (which reads the same fields). Phones only: on a computer the media widget names the artist. Saved.
  static final showLyrics = ValueNotifier(true);
  static bool get lyricsSupported => Host.isAndroid || Host.isIOS;

  /// The words of the line being sung now, null between lines or without synced lyrics. The home-screen widget
  /// shows them, changing as the notification's line does: once a line, not on a clock.
  static final lyricLine = ValueNotifier<String?>(null);

  /// How [lyricLine] is read when it is in another script and the lyrics page's Pronunciation is on
  /// ("kyō mo mata hajimaru"); null otherwise. The widget shows it under the line.
  static final lyricSaid = ValueNotifier<String?>(null);

  /// The line sung after [lyricLine], which the widget shows under it when there is no pronunciation.
  static final lyricNext = ValueNotifier<String?>(null);

  static Future<void> loadLyricsSetting() async {
    final p = await SharedPreferences.getInstance();
    showLyrics.value = p.getBool(_lyricsKey) ?? true;
    showLyrics.addListener(() => p.setBool(_lyricsKey, showLyrics.value));
  }

  static const _lyricsKey = 'lyrics.lockScreen';

  final PlayerController _c;

  /// Where the system's buttons go: [MediaSessionService.dispatch].
  void Function(MediaCommand) _send;

  /// The state last shown.
  MediaSessionState _state = MediaSessionState.empty;
  MediaTrackInfo? _shownTrack;

  /// The song as published, with its artist: the lyric line takes the artist's place over a copy of it.
  MediaItem? _item;
  Lyrics? _lyrics;
  String? _lyricsFor;

  /// Each line's pronunciation, fetched once per song while the lyrics page's Pronunciation is on.
  List<LineExtras>? _extras;
  Timer? _nextLine;
  String? _shownLine;
  bool? _shownPlaying;
  bool _shownOver = false;

  /// Swiped away from Recents: the session is put away until something plays.
  bool _closed = false;

  /// Shows [s]: the song when it changed (and looks up its lyrics), then the playback state.
  void show(MediaSessionState s) {
    // No song for a moment while still playing or loading (a new queue opening): the last one stays. Shown as
    // over, Android stopped the service and the notification went with it.
    if (s.track == null && _shownTrack != null && !_closed && (s.playing || s.processing == MediaProcessing.loading)) {
      s = s.copyWith(track: _shownTrack);
    }
    _state = s;
    final changedSong = s.track?.id != _shownTrack?.id;
    if (s.track != _shownTrack) _publishItem(s.track);
    if (changedSong) _loadLyrics();
    _publishState();
    // Where the song is decides the line shown: a seek, a pause or play moves it.
    _followLyrics();
  }

  void _publishItem(MediaTrackInfo? t) {
    _shownTrack = t;
    // The web build's tab is named after the song too (a no-op in native builds).
    pageTitle = t == null ? 'Riflay' : [t.title, if (t.artist.isNotEmpty) t.artist].join(' · ');
    if (t == null) {
      _item = null;
      _publishLine();
      mediaItem.add(null);
      return;
    }
    _item = MediaItem(
      id: t.id,
      title: t.title,
      artist: t.artist,
      album: t.album,
      duration: t.duration,
      artUri: t.artUri,
    );
    _shownLine = null;
    _publishLine(force: true);
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
    if (item == null || t == null) {
      lyricLine.value = null;
      lyricSaid.value = null;
      lyricNext.value = null;
      return;
    }
    final follow = l != null && showLyrics.value && lyricsSupported;
    final at = _c.position - LyricsTiming.of(t).value;
    final line = follow ? lineFor(l, at, extras: _extras) : null;
    // The widget has a row for each: the words, and their pronunciation under them.
    lyricLine.value = follow ? lineFor(l, at) : null;
    lyricSaid.value = follow ? saidFor(l, at, _extras) : null;
    lyricNext.value = follow ? upcomingFor(l, at) : null;
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

  /// The pronunciation from [extras] of the line sung at [position], when that line is in another script; null
  /// between lines, for a line in Latin script, or without [extras].
  @visibleForTesting
  static String? saidFor(Lyrics lyrics, Duration position, List<LineExtras>? extras) {
    if (extras == null) return null;
    final i = lyrics.lineAt(position + _early);
    if (i < 0 || i >= extras.length) return null;
    final line = lyrics.lines[i];
    if (line.end case final end? when position + _early >= end) return null;
    final text = line.text.trim();
    if (text.isEmpty || !LyricsTranslation.hasNonLatin(text)) return null;
    return extras[i].romanized;
  }

  /// The words of the next line to be sung after [position] (skipping empty and ♪ lines), null after the last.
  @visibleForTesting
  static String? upcomingFor(Lyrics lyrics, Duration position) {
    for (var j = lyrics.lineAt(position + _early) + 1; j < lyrics.lines.length; j++) {
      final text = lyrics.lines[j].text.trim();
      if (text.isNotEmpty && !RegExp(r'^[♪♫\s]+$').hasMatch(text)) return text;
    }
    return null;
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
    final s = _state;
    final playing = s.playing;
    if (playing) _closed = false;
    // Android's service forgets the song when it's stopped and started again,
    // which left a notification with only the app's name. Starting to play
    // sends the song along every time.
    // Idle tells Android the session is over: it stops the service and takes
    // the notification down. Only when nothing is left to play, not when the
    // player is idle for a moment between or after songs.
    final over = _closed || s.track == null;
    // Back from over too: the service that comes up again has no song either.
    if (playing && (_shownPlaying != true || _shownOver) && !over && mediaItem.value != null) {
      mediaItem.add(mediaItem.value);
    }
    _shownPlaying = playing;
    _shownOver = over;
    playbackState.add(
      PlaybackState(
        // After the three standard buttons, so the small notification keeps those (androidCompactActionIndices).
        // Android 13 and later show the first two of the rest beside them.
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
          if (s.liked case final liked?)
            MediaControl.custom(
              androidIcon: liked ? 'drawable/ic_widget_favorite' : 'drawable/ic_widget_favorite_border',
              label: liked ? tr.removeFromLiked : tr.addToLiked,
              name: 'like',
            ),
          if (s.track != null) ...[
            MediaControl.custom(
              androidIcon: s.shuffle ? 'drawable/ic_widget_shuffle' : 'drawable/ic_notify_shuffle_off',
              label: s.shuffle ? tr.disableShuffle : tr.enableShuffle,
              name: 'shuffle',
            ),
            // The label says what a press does next: off → all → one → off.
            MediaControl.custom(
              androidIcon: switch (s.repeat) {
                MediaRepeat.off => 'drawable/ic_notify_repeat_off',
                MediaRepeat.all => 'drawable/ic_widget_repeat',
                MediaRepeat.one => 'drawable/ic_widget_repeat_one',
              },
              label: switch (s.repeat) {
                MediaRepeat.off => tr.enableRepeat,
                MediaRepeat.all => tr.enableRepeatOne,
                MediaRepeat.one => tr.disableRepeat,
              },
              name: 'repeat',
            ),
          ],
        ],
        systemActions: const {MediaAction.seek},
        androidCompactActionIndices: const [0, 1, 2],
        processingState: over
            ? AudioProcessingState.idle
            : switch (s.processing) {
                MediaProcessing.idle => AudioProcessingState.ready,
                MediaProcessing.loading => AudioProcessingState.loading,
                MediaProcessing.buffering => AudioProcessingState.buffering,
                MediaProcessing.ready => AudioProcessingState.ready,
                MediaProcessing.completed => AudioProcessingState.completed,
              },
        playing: playing,
        updatePosition: s.position,
        bufferedPosition: s.bufferedPosition,
        speed: s.speed,
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

  /// A picture file of [t]'s cover (the system and the home-screen widget need a file), null without one.
  static Future<File?> artFile(Track t) async {
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

  // Every button goes to MediaSessionService, which runs it on PlayerController (once, in order).

  @override
  Future<void> play() async => _send(const MediaCommand.play());

  @override
  Future<void> pause() async => _send(const MediaCommand.pause());

  @override
  Future<void> stop() async => _send(const MediaCommand.stop());

  /// The app was swiped away from Recents. A song playing plays on, its notification still there to control it,
  /// as music apps do; a paused one's session is put away and the notification goes.
  @override
  Future<void> onTaskRemoved() async {
    if (_state.playing) return;
    _closed = true;
    _publishState();
  }

  @override
  Future<void> seek(Duration position) async => _send(MediaCommand.seek(position));

  @override
  Future<void> skipToNext() async => _send(const MediaCommand.next());

  @override
  Future<void> skipToPrevious() async => _send(const MediaCommand.previous());

  @override
  Future<dynamic> customAction(String name, [Map<String, dynamic>? extras]) async => switch (name) {
    'like' => _send(const MediaCommand(MediaCommandKind.like)),
    'shuffle' => _send(const MediaCommand(MediaCommandKind.shuffle)),
    'repeat' => _send(const MediaCommand(MediaCommandKind.repeat)),
    _ => null,
  };
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color, HSLColor;
import 'package:flutter/services.dart';

import '../models/track.dart';
import '../platform/host.dart';
import 'appearance.dart';
import 'discord_presence.dart';
import 'language.dart';
import 'media_session.dart';
import 'metadata.dart';
import 'player_controller.dart';

/// The colours of the home-screen player, worked out from the song's cover colour as the app's mini window is: a
/// dark card tinted with the cover, white text on it, and the accent (the line being sung, the progress wave, the
/// play button) a bright shade of the cover's colour.
@immutable
class HomeWidgetColors {
  const HomeWidgetColors({required this.surface, required this.accent, required this.onAccent});

  /// From the cover's colour ([Metadata.accent]). The card stays dark enough for white text whatever the cover is:
  /// a pale cover would otherwise leave the title unreadable on it. A grey cover keeps a grey accent rather than
  /// taking on a colour of its own.
  factory HomeWidgetColors.from(Color cover) {
    final hsl = HSLColor.fromColor(cover);
    final surface = hsl.withLightness((hsl.lightness * 0.45).clamp(0.08, 0.2)).toColor();
    final accent = hsl.saturation < 0.12
        ? hsl.withLightness(0.82).toColor()
        : hsl.withLightness(0.72).withSaturation(hsl.saturation.clamp(0.55, 0.9)).toColor();
    final onAccent = hsl.withLightness(0.12).toColor();
    return HomeWidgetColors(surface: surface, accent: accent, onAccent: onAccent);
  }

  final Color surface;
  final Color accent;
  final Color onAccent;

  Map<String, int> toMap() => {
    'surface': surface.toARGB32(),
    'accent': accent.toARGB32(),
    'onAccent': onAccent.toARGB32(),
  };

  @override
  bool operator ==(Object other) =>
      other is HomeWidgetColors && other.surface == surface && other.accent == accent && other.onAccent == onAccent;

  @override
  int get hashCode => Object.hash(surface, accent, onAccent);
}

/// What the home-screen player shows, as sent to Android. Everything but the progress is compared to decide
/// whether to send it again.
@immutable
class HomeWidgetState {
  const HomeWidgetState({
    required this.trackId,
    required this.title,
    required this.artist,
    required this.quality,
    required this.playing,
    required this.hasQueue,
    required this.hasNext,
    required this.shuffle,
    required this.loop,
    required this.liked,
    required this.colors,
    required this.cover,
    required this.labels,
  });

  /// What [c] is playing now. [liked] is null where the song can't be liked (not signed in to YouTube Music, or a
  /// song from somewhere else), which hides the button; [colors] null leaves the widget in the system's colours.
  factory HomeWidgetState.of(PlayerController c, {HomeWidgetColors? colors, String? cover}) {
    final t = c.currentTrack;
    final account = c.ytMusic;
    return HomeWidgetState(
      trackId: t?.id,
      title: t?.title ?? tr.nothingPlaying,
      artist: t?.artist ?? '',
      quality: switch (t == null ? null : c.qualityOf(t)) {
        final String q => DiscordPresence.shortQuality(q),
        null => null,
      },
      playing: t != null && c.showsPlaying,
      hasQueue: c.hasQueue,
      hasNext: c.hasNext,
      shuffle: c.shuffle,
      loop: c.loopMode.name,
      liked: t != null && t.isRemote && account.canEdit ? account.isLiked(t) : null,
      colors: t == null ? null : colors,
      cover: t == null ? null : cover,
      labels: {
        'play': tr.play,
        'pause': tr.pause,
        'previous': tr.previous,
        'next': tr.next,
        'shuffle': tr.trayShuffle,
        'repeat': tr.trayRepeat,
        'like': tr.addToLiked,
        'unlike': tr.removeFromLiked,
        'open': tr.openRiflay,
      },
    );
  }

  final String? trackId;
  final String title;
  final String artist;

  /// The song's format in a few characters, as the mini window's chip: "FLAC 24/96", "Opus 160 kbps". Null until
  /// it is known.
  final String? quality;
  final bool playing;
  final bool hasQueue;
  final bool hasNext;
  final bool shuffle;

  /// Repeat: `off`, `all` or `one` ([LoopMode]'s names).
  final String loop;
  final bool? liked;
  final HomeWidgetColors? colors;

  /// A picture file of the cover, which Android decodes at the widget's size.
  final String? cover;

  /// The buttons' names for TalkBack, in the app's language (which may not be the phone's).
  final Map<String, String> labels;

  Map<String, Object?> toMap({required Duration position, required Duration? duration}) => {
    'title': title,
    'artist': artist,
    'quality': quality,
    'playing': playing,
    'hasTrack': trackId != null,
    'hasQueue': hasQueue,
    'hasNext': hasNext,
    'shuffle': shuffle,
    'loop': loop,
    'liked': liked,
    'colors': colors?.toMap(),
    'cover': cover,
    'labels': labels,
    'position': position.inMilliseconds,
    'duration': duration?.inMilliseconds ?? 0,
  };

  @override
  bool operator ==(Object other) =>
      other is HomeWidgetState &&
      other.trackId == trackId &&
      other.title == title &&
      other.artist == artist &&
      other.quality == quality &&
      other.playing == playing &&
      other.hasQueue == hasQueue &&
      other.hasNext == hasNext &&
      other.shuffle == shuffle &&
      other.loop == loop &&
      other.liked == liked &&
      other.colors == colors &&
      other.cover == cover &&
      mapEquals(other.labels, labels);

  @override
  int get hashCode => Object.hash(
    trackId,
    title,
    artist,
    quality,
    playing,
    hasQueue,
    hasNext,
    shuffle,
    loop,
    liked,
    colors,
    cover,
    Object.hashAll(labels.values),
  );
}

/// Android: the player on the home screen (android/.../PlayerWidget.kt), which looks like the mini player.
///
/// Previous and next go to the media session. Play / pause, like, shuffle and repeat use the Dart controller.
/// It is sent the song only when something it shows changes, not on every player
/// notification, plus the progress every [progressEvery] while playing: each send redraws the widget in the
/// launcher, so the line moves in coarse steps rather than waking the phone each second.
class HomeWidget {
  HomeWidget(
    this._c, {
    MethodChannel? channel,
    Future<String?> Function(Track t)? coverFile,
    Future<Color> Function(Track t)? accent,
    ValueListenable<String?>? lyric,
    ValueListenable<String?>? lyricSaid,
    ValueListenable<String?>? lyricNext,
  }) : _channel = channel ?? const MethodChannel('riflay/home_widget'),
       _coverFile = coverFile ?? _defaultCover,
       _accent = accent ?? Metadata.accent,
       _lyric = lyric ?? MediaSession.lyricLine,
       _lyricSaid = lyricSaid ?? MediaSession.lyricSaid,
       _lyricNext = lyricNext ?? MediaSession.lyricNext;

  /// The elapsed time counts by itself on the widget (a Chronometer); the wave is redrawn this often.
  static const progressEvery = Duration(seconds: 15);

  final PlayerController _c;
  final MethodChannel _channel;
  final Future<String?> Function(Track t) _coverFile;
  final Future<Color> Function(Track t) _accent;

  /// The line being sung, as the notification shows it ([MediaSession.lyricLine]). It changes once a line, so it
  /// is sent on its own: Android swaps the text in without drawing the rest of the widget again.
  final ValueListenable<String?> _lyric;

  /// Its pronunciation (Pronunciation on, a line in another script), shown faintly underneath; else the line
  /// after it.
  final ValueListenable<String?> _lyricSaid;
  final ValueListenable<String?> _lyricNext;
  bool _lyricDue = false;

  HomeWidgetState? _shown;
  Timer? _progress;
  Future<void> _playbackActions = Future.value();

  /// The current song's cover file and colours, once they are known.
  String? _resolvedFor;
  bool? _resolvedTinted;
  String? _cover;
  HomeWidgetColors? _colors;

  static HomeWidget? _instance;

  /// Starts following [c]. Nothing happens off Android.
  static void start(PlayerController c) {
    if (!Host.isAndroid || _instance != null) return;
    _instance = HomeWidget(c)..attach();
  }

  @visibleForTesting
  void attach() {
    _channel.setMethodCallHandler(_onCall);
    _c.addListener(sync);
    _c.ytMusic.addListener(sync);
    Appearance.instance.addListener(sync);
    Language.instance.addListener(sync);
    _lyric.addListener(_sendLyric);
    _lyricSaid.addListener(_sendLyric);
    _lyricNext.addListener(_sendLyric);
    sync();
    _takePlaybackActions();
  }

  /// The lines change together: sent once, after all of them.
  void _sendLyric() {
    if (_lyricDue) return;
    _lyricDue = true;
    scheduleMicrotask(() {
      _lyricDue = false;
      _channel
          .invokeMethod<void>('lyric', {'lyric': _lyric.value, 'said': _lyricSaid.value, 'next': _lyricNext.value})
          .catchError((Object e) => debugPrint('Home-screen widget: $e'));
    });
  }

  @visibleForTesting
  void detach() {
    _channel.setMethodCallHandler(null);
    _c.removeListener(sync);
    _c.ytMusic.removeListener(sync);
    Appearance.instance.removeListener(sync);
    Language.instance.removeListener(sync);
    _lyric.removeListener(_sendLyric);
    _lyricSaid.removeListener(_sendLyric);
    _lyricNext.removeListener(_sendLyric);
    _progress?.cancel();
  }

  void _takePlaybackActions() {
    _playbackActions = _playbackActions
        .then((_) async {
          final count = await _channel.invokeMethod<int>('takePlaybackToggles') ?? 0;
          for (var i = 0; i < count; i++) {
            // A second tap can pause while the first tap is still opening its stream.
            unawaited(_c.togglePlay().catchError((Object e) => debugPrint('Home-screen playback control: $e')));
          }
        })
        .catchError((Object e) => debugPrint('Home-screen playback control: $e'));
  }

  /// Actions pressed on the widget.
  Future<Object?> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'playbackActionAvailable':
        _takePlaybackActions();
      case 'like':
        final t = _c.currentTrack;
        final account = _c.ytMusic;
        if (t == null || !t.isRemote || !account.canEdit) return null;
        await account.setLiked(t, !account.isLiked(t));
      case 'shuffle':
        await _c.toggleShuffle();
      case 'repeat':
        await _c.cycleLoopMode();
    }
    return null;
  }

  /// Whether the widget takes the cover's colours: when the app does (cover colours, or the Dynamic theme).
  /// Otherwise it stays in the system's (Material You on Android 12 and later).
  static bool get _tinted {
    final look = Appearance.instance;
    return look.coverColors || look.theme == ThemeChoice.dynamic;
  }

  @visibleForTesting
  void sync() {
    final t = _c.currentTrack;
    final tinted = _tinted;
    if (t?.id != _resolvedFor || tinted != _resolvedTinted) _resolve(t, tinted);
    final now = HomeWidgetState.of(_c, colors: _colors, cover: _cover);
    _followProgress(now.playing);
    if (now == _shown) return;
    _shown = now;
    _send(now);
  }

  /// Looks up the song's cover and colours, then sends them along.
  void _resolve(Track? t, bool tinted) {
    _resolvedFor = t?.id;
    _resolvedTinted = tinted;
    _cover = null;
    _colors = null;
    if (t == null) return;
    final cached = tinted ? Metadata.cachedAccent(t) : null;
    if (cached != null) _colors = HomeWidgetColors.from(cached);
    unawaited(() async {
      try {
        final cover = await _coverFile(t);
        final accent = tinted && _colors == null ? await _accent(t) : null;
        if (_resolvedFor != t.id || _resolvedTinted != tinted) return;
        _cover = cover;
        if (accent != null) _colors = HomeWidgetColors.from(accent);
        sync();
      } catch (e) {
        debugPrint('Home-screen widget: no cover ($e)');
      }
    }());
  }

  void _followProgress(bool playing) {
    if (!playing) {
      _progress?.cancel();
      _progress = null;
      return;
    }
    _progress ??= Timer.periodic(progressEvery, (_) {
      final shown = _shown;
      if (shown != null) _send(shown);
    });
  }

  void _send(HomeWidgetState s) {
    _channel
        .invokeMethod<void>(
          'update',
          // The line too, so a widget drawn again from scratch (resized, the launcher restarted) keeps it.
          {
            ...s.toMap(position: _c.position, duration: _c.duration ?? _c.currentTrack?.duration),
            'lyric': _lyric.value,
            'said': _lyricSaid.value,
            'next': _lyricNext.value,
          },
        )
        .catchError((Object e) => debugPrint('Home-screen widget: $e'));
  }

  static Future<String?> _defaultCover(Track t) async => (await MediaSession.artFile(t))?.path;
}

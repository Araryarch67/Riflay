import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart' hide NativePlayer, Track;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/host.dart';
import '../platform/mpv.dart';
import '../platform/native_video.dart';
import '../ui/widgets/native_video_surface.dart';
import '../ui/debug_switches.dart';
import '../models/track.dart';
import 'beta_features.dart';
import 'layout_prefs.dart';
import 'player_controller.dart';
import 'video_alignment.dart';
import 'video_download.dart';
import 'video_engine.dart';
import 'youtube_stream.dart';
import 'ytmusic_web.dart';
import 'language.dart';

/// Video mode: a YouTube song's music video on the Now Playing views,
/// YouTube Music's Song / Video switch.
///
/// The song keeps playing through the app's own player (equalizer, leveling,
/// gapless and the rest stay as they are). The video is a second mpv with no
/// sound that follows it: it starts where the song is, pauses and seeks with
/// it, and catches up when it drifts.
///
/// To spare data and battery, nothing about the video is fetched until
/// Video is picked, it is only decoded while a Now Playing view shows it, and
/// it turns back into Song when the app goes to the background (the screen
/// turns off, another app comes in front).
///
/// The same player also serves the Music video Now Playing background, at a
/// small size and without being asked for by the Song / Video switch.
class VideoMode extends ChangeNotifier with WidgetsBindingObserver {
  VideoMode._();

  static final instance = VideoMode._();

  /// The tallest the video comes in, wherever it shows: on phones 1440p, 720p in Lightweight (what a low-end phone
  /// starts in, see `DeviceSetup.fitPhone`: a 1440p VP9 stream there was decoder surfaces and read-ahead it couldn't
  /// spare); on computers by performance mode, 1080p in Heavy, 720p in Balanced and 480p in Lightweight. A phone fills its tall screen with it cropped to cover, so only
  /// a middle strip of each frame shows, stretched about 2.5 times; 1440p is VP9, which phones decode in hardware.
  /// Taller (4K) streams buffered on ordinary connections. On a computer each video frame redraws the window, and a
  /// smaller one is decoded, uploaded and kept (decoder surfaces, read-ahead) for less: the video in a cover-sized
  /// view or behind a blurred page looks the same at 720p.
  static int get maxHeight => Host.isAndroid || Host.isIOS
      ? (LayoutPrefs.lightweight ? 720 : 1440)
      : switch (LayoutPrefs.instance.performance) {
          PerformanceMode.heavy => 1080,
          PerformanceMode.balanced => 720,
          PerformanceMode.lightweight => 480,
        };

  /// Behind the page: the same size (a background is fetched only on Wi-Fi, see `prefetchAllowed`).
  static int get backgroundHeight => maxHeight;

  // ---- Fitting the connection ----

  /// The most video frames a second on a computer, null for the video's own rate (Heavy, phones). Every frame is
  /// a full redraw of the window (Flutter has no partial redraw there): a 30 fps video beside Balanced's 20 fps
  /// decorations made about 50 a second, ~3% of a 24-thread processor. The fps filter only passes or drops the
  /// decoded GPU frames, so hardware decoding stays.
  static int? get maxFps => Host.isAndroid || Host.isIOS
      ? null
      : switch (LayoutPrefs.instance.performance) {
          PerformanceMode.heavy => null,
          PerformanceMode.balanced => int.tryParse(Host.environment['RIFLAY_VIDEO_FPS'] ?? '') ?? 15,
          PerformanceMode.lightweight => 10,
        };

  /// Off with `RIFLAY_NO_ADAPTIVE_VIDEO`: the video always comes at [maxHeight], however often it stalls.
  static const adaptive = !bool.fromEnvironment('RIFLAY_NO_ADAPTIVE_VIDEO');

  /// The steps the video comes down (and back up) through.
  static const ladder = [2160, 1440, 1080, 720, 480, 360];

  /// The tallest the connection has kept up with: a video that stalls comes down a step, and goes back up a step
  /// at the next song after a minute and a half without stalling. Null: [maxHeight].
  int? _cap;
  int _streamHeight = 0;
  bool _streamed = false;
  DateTime? _stallSince;
  final _stalls = <DateTime>[];
  DateTime _smoothSince = DateTime.now();

  /// The height the video was just moved to, to tell the person (a snackbar), with a count so the same height
  /// twice still tells.
  final qualityChanged = ValueNotifier<({int height, bool lower, int serial})?>(null);

  int _height(bool foreground) {
    final most = foreground ? maxHeight : backgroundHeight;
    return _cap == null ? most : _cap!.clamp(ladder.last, most);
  }

  /// The step under [height], or null at the bottom.
  @visibleForTesting
  static int? stepDown(int height) => ladder.where((h) => h < height).firstOrNull;

  /// The step over [height] up to [most], or null when already there.
  @visibleForTesting
  static int? stepUp(int height, int most) => ladder.reversed.where((h) => h > height && h <= most).firstOrNull;

  void _announce(int height, {required bool lower}) =>
      qualityChanged.value = (height: height, lower: lower, serial: (qualityChanged.value?.serial ?? 0) + 1);

  /// Watches the streamed video for stalls while the song plays: one of 2.5 s, or three in 40 s, bring it down a
  /// step. A seek's own wait doesn't count. True when the video was let go to come back smaller.
  bool _watchStalls(VideoEngine player, bool play, DateTime now) {
    if (!adaptive ||
        !_streamed ||
        !play ||
        _seekedTo != null ||
        now.difference(_lastSeek) < const Duration(seconds: 3)) {
      _stallSince = null;
      return false;
    }
    if (player.buffering) {
      _stallSince ??= now;
      return now.difference(_stallSince!) > const Duration(milliseconds: 2500) && _lower();
    }
    if (_stallSince case final since?) {
      _stallSince = null;
      if (now.difference(since) > const Duration(milliseconds: 400)) {
        _stalls
          ..add(now)
          ..removeWhere((t) => now.difference(t) > const Duration(seconds: 40));
        _smoothSince = now;
        if (_stalls.length >= 3) return _lower();
      }
    }
    return false;
  }

  bool _lower() {
    final next = stepDown(_streamHeight > 0 ? _streamHeight : _height(_loadedForeground));
    _stalls.clear();
    _stallSince = null;
    _smoothSince = DateTime.now();
    if (next == null) return false;
    _cap = next;
    _announce(next, lower: true);
    debugPrint('Video mode: stalling, down to ${next}p');
    // Again from where the song is, smaller; the cover shows meanwhile.
    _stop().then((_) => _sync());
    return true;
  }

  PlayerController? _c;

  /// Starts following [c]'s current song. Called by the views; once is enough.
  void follow(PlayerController c) {
    if (identical(_c, c)) return;
    _c?.removeListener(_changed);
    if (_c == null) WidgetsBinding.instance.addObserver(this);
    _c = c;
    c.addListener(_changed);
    _loadOn();
    LayoutPrefs.instance
      ..removeListener(_decoderChanged)
      ..addListener(_decoderChanged);
    _probe();
  }

  // ---- Which songs have a video ----

  /// Whether this device's mpv can decode video at all. Riflay's Android and
  /// Apple builds carry h264 and vp9 (tool/build_libmpv_android.sh and
  /// tool/build_libmpv_apple.sh); a build of sound only, or an older one,
  /// keeps the switch hidden.
  bool _canDecode = false;
  bool _probed = false;

  Future<void> _probe() async {
    if (_probed) return;
    _probed = true;
    if (Host.isLinux || Host.isWindows) {
      _canDecode = true;
      // follow() is called from the views' build: tell them after it, not during it.
      scheduleMicrotask(notifyListeners);
      return;
    }
    Player? p;
    try {
      MediaKit.ensureInitialized();
      p = Player(configuration: const PlayerConfiguration(muted: true, title: 'Riflay video check'));
      final list = await (p.platform as NativePlayer).getProperty('decoder-list');
      _canDecode = decodesVideo(list);
    } catch (e) {
      debugPrint('Video mode: no decoder list: $e');
    } finally {
      await p?.dispose();
    }
    notifyListeners();
  }

  /// Whether mpv's `decoder-list` has a decoder for YouTube's video streams.
  /// h264 is what media_kit_video itself looks for before it makes a video
  /// output (and what YouTube serves at every size); without it the output
  /// can't be made, whatever else is there.
  @visibleForTesting
  static bool decodesVideo(String decoderList) => decoderList.contains('h264');

  /// Looked-up songs: the video, or null for none. Missing while not asked yet.
  final _found = <String, MusicVideo?>{};
  final _asking = <String>{};

  /// The downloaded music video that [track] is playing from, if it is: the file itself, or the downloaded copy of
  /// a streamed song. Only that file, so the picture is the very recording the sound comes from.
  File? localVideoOf(Track? track) {
    final c = _c;
    if (track == null || c == null) return null;
    final path = track.isRemote ? c.downloadedCopy(track)?.path : track.path;
    if (path == null || !isVideoFile(path)) return null;
    return File(path);
  }

  /// The music video of [track], when it has one and this device can show it. A downloaded one is there
  /// without asking YouTube Music, so it also works offline.
  MusicVideo? videoOf(Track? track) {
    if (!_canDecode || !BetaFeatures.instance.isOn(BetaFeature.videoMode)) return null;
    if (localVideoOf(track) != null) {
      return MusicVideo(videoId: track?.videoId ?? youtubeVideoIdOf(track?.sourceUrl) ?? track!.id);
    }
    return _found[track?.videoId];
  }

  /// Asks YouTube Music once whether [track] has a video (one small request,
  /// made when a Now Playing view shows the song; no video data).
  void lookUp(Track? track) {
    final id = track?.videoId;
    final c = _c;
    if (id == null ||
        c == null ||
        !_canDecode ||
        !BetaFeatures.instance.isOn(BetaFeature.videoMode) ||
        _found.containsKey(id) ||
        localVideoOf(track) != null ||
        !_asking.add(id)) {
      return;
    }
    (debugLookUp ?? c.ytMusic.musicVideo)(id)
        .then(
          (v) {
            _found[id] = v;
            if (v != null) _align(id, v);
          },
          onError: (Object e) {
            debugPrint('Video mode: looking up $id: $e');
            _found[id] = null;
          },
        )
        .whenComplete(() {
          _asking.remove(id);
          while (_found.length > 64) {
            _found.remove(_found.keys.first);
          }
          _sync();
          notifyListeners();
        });
  }

  /// A video without YouTube Music's map of the parts plays on the song's timeline until its own is measured
  /// ([VideoAlignment]); then it moves there, with one seek.
  void _align(String songId, MusicVideo v) {
    if (!VideoAlignment.enabled || v.segments.isNotEmpty || v.videoId == songId || debugLookUp != null) return;
    VideoAlignment.of(songId, v.videoId).then((a) {
      if (a == null || a.none || !identical(_found[songId], v)) return;
      final shifted = _found[songId] = v.shifted(a.offset, a.rate);
      if (identical(_playing, v)) {
        _playing = shifted;
        _lastSeek = DateTime(0);
        _seekedTo = null;
        _follow(seekNow: true);
      }
    }).ignore();
  }

  /// Stands in for YouTube Music's answer in [lookUp] (tests).
  @visibleForTesting
  static Future<MusicVideo?> Function(String videoId)? debugLookUp;

  @visibleForTesting
  void debugSetFound(String videoId, MusicVideo? video) {
    _canDecode = _probed = true;
    _found[videoId] = video;
    notifyListeners();
  }

  // ---- The switch ----

  bool _on = true;
  static const _onKey = 'videoMode.on';

  /// Video (true) or Song: what the user picked, kept between launches. Song shows no video anywhere, only the
  /// cover; Video shows the music video wherever the layout has room for it: in the cover's place, behind the page
  /// (Cover: Background) or behind the side panel. Video by default.
  bool get on => _on;

  Future<void> _loadOn() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getBool(_onKey);
      if (saved != null && saved != _on) {
        _on = saved;
        _sync();
        notifyListeners();
      }
    } catch (_) {}
  }

  /// A calm line under the switch when the video couldn't be shown.
  String? get notice => _notice;
  String? _notice;

  void setOn(bool on) {
    if (on == _on) return;
    _on = on;
    _notice = null;
    _sync();
    notifyListeners();
    SharedPreferences.getInstance().then((p) => p.setBool(_onKey, on)).ignore();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Phones: the screen went off or another app is in front. The song plays on alone.
    final away = state == AppLifecycleState.paused || state == AppLifecycleState.hidden;
    // The video stops with it, and starts again when the app is back; the choice of Song or Video stays.
    if (away != _away) {
      _away = away;
      _sync();
      notifyListeners();
    }
    // Computers: another window has the focus. The video holds its picture (nothing decodes, nothing is drawn: in
    // Balanced a playing video was most of what a song cost, about 1.7% of a 24-thread processor), and after
    // [unfocusedRelease] it lets go of its player and buffers (about 100 MB). Back in front it starts again where
    // the song is. Phones pass through `inactive` for a pulled-down shade: they keep playing.
    // Windows' own-window video costs next to nothing to keep playing (the graphics card decodes and draws it), and
    // a window behind another is often still watched: it plays on until the window is minimized or hidden.
    final unfocused = _computer && (Host.isLinux || _native == null) && state == AppLifecycleState.inactive;
    if (unfocused != _unfocused) {
      _unfocused = unfocused;
      _unfocusedRelease?.cancel();
      if (unfocused) {
        _follow();
        _unfocusedRelease = Timer(unfocusedRelease, () {
          _released = true;
          _sync();
        });
      } else if (_released) {
        _released = false;
        _sync();
      } else {
        _follow(seekNow: true);
      }
    }
  }

  bool _away = false;

  static bool get _computer => Host.isLinux || Host.isWindows || Host.isMacOS;

  /// How long another window may have the focus before the video's player is let go.
  static const unfocusedRelease = Duration(seconds: 20);
  bool _unfocused = false;
  bool _released = false;
  Timer? _unfocusedRelease;

  // ---- The video player ----

  int _views = 0;
  Timer? _release;

  /// How long the player is kept with no view on screen. A page changing, a dialog (Signal path) or the cover moving
  /// between layouts briefly has none: drawn in the page, the video goes after 2 s; in Windows' own window, where
  /// keeping it costs little, after a minute (fetching it again shows the cover for a few seconds).
  static Duration get _holdWithoutView =>
      Host.isWindows && instance._native != null ? const Duration(minutes: 1) : const Duration(seconds: 2);

  /// Full-screen views ([VideoPicture] in the landscape player): they show whatever is playing, a background
  /// video too, without asking for it again at the cover's size (a reload would show the cover for seconds).
  int _fullViews = 0;

  /// A view that shows the video came on screen (or went away). The video is
  /// only fetched and decoded while one is. [full]: the full-screen player.
  void addView({bool full = false}) {
    full ? _fullViews++ : _views++;
    _viewsChanged();
    _release?.cancel();
    // Views come on screen while the tree builds: start the video right after.
    scheduleMicrotask(_sync);
  }

  void removeView({bool full = false}) {
    full ? _fullViews-- : _views--;
    _viewsChanged();
    // A page changing, or the cover moving between layouts, briefly has no view: keep the video through that.
    _release?.cancel();
    _release = Timer(_holdWithoutView, _sync);
  }

  // ---- The Now Playing background ----

  int _backgrounds = 0;
  final _backgroundFailed = <String>{};

  /// A Now Playing background that wants the video came on screen (or went away). Like [addView], the video is
  /// only fetched and decoded while one is.
  void addBackground() {
    _backgrounds++;
    _viewsChanged();
    _release?.cancel();
    scheduleMicrotask(_sync);
  }

  void removeBackground() {
    _backgrounds--;
    _viewsChanged();
    _release?.cancel();
    _release = Timer(_holdWithoutView, _sync);
  }

  /// Whether the video of [track] may play behind the page: Video is picked, the song has one, not in Lightweight,
  /// and it hasn't failed to load. Song picked: no video anywhere. (Where the cover area shows the video itself, the
  /// background keeps the cover: [backgroundController] is null while the video plays there.)
  bool showsAsBackground(Track? track) {
    final v = videoOf(track);
    // Windows' own-window video can't lie under the page's words: the blurred cover does there.
    return v != null &&
        _on &&
        !LayoutPrefs.lightweight &&
        (!native || Host.isLinux) &&
        !_backgroundFailed.contains(v.videoId);
  }

  /// The background's video, once its first picture is ready; null shows the blurred cover.
  VideoController? backgroundController(Track? track) =>
      showsAsBackground(track) && _loaded == videoOf(track)?.videoId && !_foreground ? controller : null;

  /// The background video of [track] is playing and covers the page: what lies under it is not drawn.
  bool coversBackground(Track? track) => backgroundController(track) != null;

  VideoEngine? _player;
  VideoController? _video;
  NativeVideoPlayer? _native;
  Future<void> _surfaceChange = Future.value();
  int _videoRequest = 0;
  ({String id, bool foreground})? _opening;
  bool _disposed = false;

  // Native surfaces have one renderer. Serialize only creation/disposal, not
  // network loading, so a newer song can cancel a slow load immediately.
  Future<T> _withSurface<T>(Future<T> Function() work) async {
    final previous = _surfaceChange;
    final finished = Completer<void>();
    _surfaceChange = finished.future;
    try {
      await previous;
      return await work();
    } finally {
      finished.complete();
    }
  }

  /// Windows/Linux: video has its own native surface over the page. Views place
  /// it with [NativeVideoSurface] instead of drawing [controller].
  static bool get native => !DebugSwitches.noNativeVideo && !_nativeUnavailable && NativeVideoPlayer.available;
  static bool _nativeUnavailable = false;

  static String _nativeHwdec(String hwdec) => Host.isWindows && hwdec == 'auto' ? 'd3d11va' : hwdec;

  /// The own-window video is ready to be placed (its first picture is out).
  bool get nativeReady => _ready && _native != null;

  /// Cover (cropped to fill) or fit, as the box showing it asks ([NativeVideoSurface.cover]).
  void _fit() {
    if (!_fitting) {
      _fitting = true;
      NativeVideoWindow.cover.addListener(_fit);
      NativeVideoWindow.fade.addListener(_fit);
    }
    final own = _native;
    if (own == null) return;
    own.setProperty('panscan', NativeVideoWindow.cover.value ? '1.0' : '0.0');
    final fade = NativeVideoWindow.fade.value;
    final shader = fade == null ? '' : _fadeShader(fade);
    if (shader != _shader) {
      _shader = shader;
      own.setProperty('glsl-shaders', shader);
    }
  }

  String? _shader;

  /// An mpv user shader (written once per colour, run on the graphics card) that does what Flutter drew over the
  /// video before: a shade across the top, and the foot faded into [into].
  static String _fadeShader(Color into) {
    String c(double v) => v.toStringAsFixed(4);
    final hex = into.toARGB32().toRadixString(16).padLeft(8, '0');
    // The version in the name: a changed shader must not reuse an older file of the same colour.
    final file = File('${Directory.systemTemp.path}${Platform.pathSeparator}riflay-video-fade-v2-$hex.glsl');
    if (!file.existsSync()) {
      // The gradient the panel drew over its picture: black at 45% to clear by 22% down, clear to half way, then
      // the panel's colour at 85% by 88% and solid at the foot.
      file.writeAsStringSync('''
//!HOOK OUTPUT
//!BIND HOOKED
//!DESC Riflay: the side panel's shade and fade
vec4 hook() {
    float y = HOOKED_pos.y;
    vec4 color = HOOKED_tex(HOOKED_pos);
    color.rgb *= 1.0 - 0.45 * (1.0 - clamp(y / 0.22, 0.0, 1.0));
    float t = y < 0.88 ? 0.85 * clamp((y - 0.5) / 0.38, 0.0, 1.0) : mix(0.85, 1.0, (y - 0.88) / 0.12);
    color.rgb = mix(color.rgb, vec3(${c(into.r)}, ${c(into.g)}, ${c(into.b)}), t);
    return color;
}
''');
    }
    return file.path;
  }

  bool _fitting = false;

  /// Its width over its height (16:9 until it is known).
  double get nativeAspect => _native?.aspect ?? 16 / 9;
  bool _loadedForeground = true;
  String? _loaded;
  MusicVideo? _playing;
  bool _ready = false;
  Timer? _tick;
  DateTime _lastSeek = DateTime(0);
  double _rate = 1;

  /// How far ahead of the song a seek aims while playing: what fetching and
  /// decoding from the new point took last time (it depends on the connection).
  Duration _lead = const Duration(milliseconds: 600);

  /// Where the last seek aimed while playing, until the gap it left is measured.
  Duration? _seekedTo;

  /// The video to draw, once its first picture is ready; null shows the cover.
  VideoController? get controller => _ready ? _video : null;

  /// The video is being fetched (the view shows a small spinner over the cover).
  bool get loading => _player != null && !_ready;

  /// Where the video is, and whether it is playing (for tests).
  @visibleForTesting
  ({Duration position, bool playing})? get debugVideoState =>
      _player == null ? null : (position: _player!.position, playing: _player!.playing);

  /// What should play now, from the facts: Video picked, a view on screen,
  /// and the current song has a video.
  MusicVideo? get _wanted {
    if (_released || _disposed) return null;
    final track = _c?.currentTrack;
    if (_foreground) return videoOf(track);
    if (_backgrounds > 0 && !_away && showsAsBackground(track)) return videoOf(track);
    return null;
  }

  bool get _foreground => _on && (_views > 0 || _fullViews > 0);

  /// The music video's picture is on screen now: its first frame is ready and a view shows it. Decorations and the
  /// visualizer rest meanwhile (`PlayingMotion`, `AudioReactiveView`): the video is the motion, and with its surface
  /// over the window each frame Flutter drew cost the Linux main thread twice as much (~20 ms).
  bool get showing => _ready && _wanted != null;

  /// [showing] may change with the views: listeners hear it after the frame that changed them (never mid-build).
  void _viewsChanged() => scheduleMicrotask(() {
    if (!_disposed) notifyListeners();
  });

  void _changed() {
    final track = _c?.currentTrack;
    if (_on || _backgrounds > 0) lookUp(track);
    _sync();
    _follow();
  }

  void _sync() {
    final want = _wanted;
    if (want == null) {
      if (_player != null || _opening != null) _stop();
      return;
    }
    if (_opening == (id: want.videoId, foreground: _foreground)) return;
    // A background video is small: the Song / Video switch asks for the full size again.
    if (_opening != null ||
        _loaded != want.videoId ||
        _on && _views > 0 && !_loadedForeground ||
        Host.isLinux && !_foreground && _native != null) {
      _start(want, foreground: _foreground);
    }
  }

  Future<void> _start(MusicVideo v, {required bool foreground}) async {
    final request = ++_videoRequest;
    _opening = (id: v.videoId, foreground: foreground);
    VideoEngine? selected;
    VideoController? video;
    NativeVideoPlayer? own;
    try {
      await _withSurface(() async {
        if (request != _videoRequest) return;
        await _disposePlayer();
        if (request != _videoRequest) return;
        // A minute and a half without a stall: this song may try a step higher.
        if (adaptive && _cap != null && DateTime.now().difference(_smoothSince) > const Duration(seconds: 90)) {
          final most = foreground ? maxHeight : backgroundHeight;
          final up = stepUp(_cap!, most);
          _cap = up == null || up >= most ? null : up;
          _smoothSince = DateTime.now();
          if (up != null) _announce(up, lower: false);
        }
        _streamed = false;
        _streamHeight = 0;
        _loaded = v.videoId;
        _loadedForeground = foreground;
        _playing = v;
        _decoder = LayoutPrefs.instance.videoDecoder;
        final hwdec = LayoutPrefs.instance.videoDecoder.hwdec;
        // A full-page background needs Flutter text and effects above the video.
        // Linux retains its texture backend there; cover/side-panel video is native.
        if (native && (foreground || !Host.isLinux)) {
          try {
            // Linux retains its power limits until full-app profiling supports
            // relaxing them. Windows' direct window output is already measured.
            own = NativeVideoPlayer(
              window: await NativeVideoWindow.ensure(),
              hwdec: _nativeHwdec(hwdec),
              maxFps: Host.isLinux ? maxFps : null,
              foreground: foreground,
            );
            await own!.attach();
          } catch (e) {
            debugPrint('Video mode: no own window ($e), drawing it in the page');
            await own?.dispose();
            own = null;
            if (request != _videoRequest) return;
            _nativeUnavailable = true;
          }
          if (request != _videoRequest) {
            await own?.dispose();
            return;
          }
        }
        if (own != null) {
          selected = _player = _native = own;
          _fit();
        } else {
          final kit = Player(
            configuration: PlayerConfiguration(
              muted: true,
              title: 'Riflay video',
              bufferSize: foreground ? 4 << 20 : 2 << 20,
            ),
          );
          selected = _player = _KitEngine(kit);
          video = _video = VideoController(
            kit,
            // Drawn on the graphics card either way; Settings › Now Playing › Video decoding picks what decodes it.
            configuration: VideoControllerConfiguration(hwdec: hwdec),
          );
        }
        notifyListeners();
      });
    } finally {
      if (request == _videoRequest) _opening = null;
    }
    final player = selected;
    if (player == null || request != _videoRequest) return;
    try {
      if (player case _KitEngine(:final kit)) {
        final mpv = kit.platform as NativePlayer;
        // Video only: no sound track, and only half a minute read ahead (not the whole video).
        await mpv.setProperty('aid', 'no');
        for (final o in (Host.environment['RIFLAY_VIDEO_MPV_OPTIONS'] ?? '').split(';')) {
          if (o.contains('=')) await mpv.setProperty(o.substring(0, o.indexOf('=')), o.substring(o.indexOf('=') + 1));
        }
        await mpv.setProperty('cache-secs', foreground ? '30' : '10');
        await mpv.setProperty('demuxer-max-bytes', '${(foreground ? 32 : 12) << 20}');
        await mpv.setProperty('demuxer-max-back-bytes', '${(foreground ? 8 : 2) << 20}');
        // Each video frame redraws the whole window on a computer: fewer of them below Heavy (see [maxFps]).
        if (maxFps case final fps?) await mpv.setProperty('vf', 'fps=$fps');
      }
      Future<void> open(String url, Duration at) async {
        if (player case _KitEngine(:final kit)) {
          await kit.open(Media(url, start: at), play: false);
        } else {
          await own!.open(url, start: at);
        }
      }

      final at = v.videoTimeAt(_c?.position ?? Duration.zero) ?? Duration.zero;
      final local = localVideoOf(_c?.currentTrack);
      if (local != null) {
        // The downloaded file: no network, and the size it was saved at.
        debugPrint('Video mode: ${v.videoId} from ${local.path}');
        await open(own != null ? local.path : Uri.file(local.path).toString(), at);
      } else {
        // Nobody asked for this video: a phone on mobile data (or on a saver) doesn't spend it.
        if (!foreground && !await YoutubeStream.prefetchAllowed()) throw StateError('metered connection');
        if (!identical(player, _player)) return;
        final stream = await YoutubeStream.video(v.videoId, maxHeight: _height(foreground));
        if (!identical(player, _player)) return;
        _streamed = true;
        _streamHeight = stream.height;
        debugPrint('Video mode: ${v.videoId} at ${stream.height}p ${stream.codec}');
        await open(stream.url.toString(), at);
      }
      if (own != null) {
        if (!await own!.firstFrame(const Duration(seconds: 25))) throw TimeoutException('no first picture');
      } else {
        final kitVideo = video!;
        await kitVideo.waitUntilFirstFrameRendered.timeout(const Duration(seconds: 25));
        // And its size: until then a view has only an empty (black) texture to draw, so the cover stays.
        if (!_sized(kitVideo)) {
          final sized = Completer<void>();
          void check() {
            if (_sized(kitVideo) && !sized.isCompleted) sized.complete();
          }

          kitVideo.rect.addListener(check);
          try {
            await sized.future.timeout(const Duration(seconds: 3), onTimeout: () {});
          } finally {
            kitVideo.rect.removeListener(check);
          }
        }
      }
      if (!identical(player, _player)) return;
      _readDecoder();
      _ready = true;
      _tick = Timer.periodic(const Duration(milliseconds: 250), (_) => _follow());
      _follow();
      notifyListeners();
    } catch (e) {
      if (!identical(player, _player)) return;
      debugPrint('Video mode: ${v.videoId} failed: $e');
      if (!foreground) {
        // The page falls back to the blurred cover, with no message; don't try this video again.
        _backgroundFailed.add(v.videoId);
        await _stop();
        notifyListeners();
        return;
      }
      _found[_c?.currentTrack?.videoId ?? ''] = null;
      _on = false;
      _notice = tr.videoCouldntLoad;
      await _stop();
      notifyListeners();
    }
  }

  // ---- Decoding ----

  VideoDecoder? _decoder;

  /// What decodes the video now, as mpv names it (`d3d11va`, `vaapi`, `videotoolbox`...; `no` is the
  /// processor), once a video has played; null before.
  String? get decoderInUse => _decoderInUse;
  String? _decoderInUse;

  Future<void> _readDecoder() async {
    final player = _player;
    if (player == null) return;
    try {
      final now = await player.getProperty('hwdec-current');
      if (!identical(player, _player)) return;
      _decoderInUse = now.isEmpty ? 'no' : now;
      debugPrint('Video mode: decoding with $_decoderInUse');
      notifyListeners();
    } catch (_) {}
  }

  /// A new Video decoding setting applies to the video that is playing: mpv switches decoders in place.
  void _decoderChanged() {
    final want = LayoutPrefs.instance.videoDecoder;
    final player = _player;
    if (want == _decoder) return;
    _decoder = want;
    if (player == null) return;
    player.setProperty('hwdec', _native != null ? _nativeHwdec(want.hwdec) : want.hwdec).then((_) async {
      // The switch lands on the next decoded frame.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await _readDecoder();
    }).ignore();
  }

  Future<void> _stop() async {
    final request = ++_videoRequest;
    _opening = null;
    await _withSurface(_disposePlayer);
    if (request == _videoRequest) _sync();
  }

  Future<void> _disposePlayer() async {
    final player = _player;
    _tick?.cancel();
    _tick = null;
    _player = null;
    _video = null;
    _native = null;
    _loaded = null;
    _loadedForeground = true;
    _playing = null;
    _ready = false;
    _rate = 1;
    _seekedTo = null;
    if (!_disposed) notifyListeners();
    await player?.dispose();
  }

  static bool _sized(VideoController video) => (video.rect.value?.width ?? 0) > 1;

  /// Keeps the video with the song: same play / pause; a small gap closes by
  /// running the video a little faster or slower (invisible, and no new
  /// buffering), a big one (a seek, a stall) with a seek of its own, aimed
  /// ahead by what the last one took. A seek waits for the last one to land.
  void _follow({bool seekNow = false}) {
    final c = _c, player = _player, v = _playing;
    if (c == null || player == null || v == null || !_ready) return;
    final target = v.videoTimeAt(c.position);
    final play = target != null && c.isPlaying && !c.isBuffering && !_unfocused;
    var rate = 1.0;
    if (target != null) {
      final drift = player.position - target;
      final now = DateTime.now();
      if (_watchStalls(player, play, now)) return;
      // Once the video moves on after a seek, the gap left says how far ahead to aim next time.
      if (_seekedTo case final to? when player.position > to + const Duration(milliseconds: 100)) {
        _seekedTo = null;
        if (play) _lead = nextLead(_lead, drift);
      }
      // A seek that never lands (a stalled connection) stops holding the next one back.
      if (now.difference(_lastSeek) > const Duration(seconds: 8)) _seekedTo = null;
      // A paused song is matched exactly. A song that is only buffering (a streamed song does, briefly, between
      // chunks) just pauses the video: a seek would send it back to the network for nothing.
      // Up to [seekBeyond] closes by speed: a seek on a stream fetches again first, and measured on a song's first
      // seconds the video froze two or three seconds after each one, then overshot into the next (a 1 s limit
      // swung the gap between -1.4 and +1.3 s for twelve seconds).
      // Held while another window has the focus: it catches up once back in front.
      if (_unfocused) {
        // Nothing to match.
      } else if (seekNow && drift.abs() > const Duration(milliseconds: 100) ||
          drift.abs() > seekBeyond ||
          !c.isPlaying && drift.abs() > const Duration(milliseconds: 100)) {
        // Not until the last seek has landed: the stream comes only a little faster than it plays, so each seek
        // fetches for a second or two first, and a new one would throw that away and start again.
        if (_seekedTo == null && now.difference(_lastSeek) > const Duration(milliseconds: 700)) {
          _lastSeek = now;
          _seekedTo = play ? target + _lead : null;
          player.seek(_seekedTo ?? target).ignore();
        }
      } else if (play) {
        rate = catchUpRate(drift);
      }
    }
    // In steps: every change of speed makes mpv retime its frames, which shows as a stutter.
    if ((rate - _rate).abs() >= 0.02 || rate == 1 && _rate != 1) {
      _rate = rate;
      player.setRate(rate).ignore();
    }
    if (play != player.playing) (play ? player.play() : player.pause()).ignore();
  }

  /// The next seek's [lead], from the gap [drift] (video minus song) the last
  /// one left: behind means aim further ahead.
  @visibleForTesting
  static Duration nextLead(Duration lead, Duration drift) {
    final ms = (lead - drift).inMilliseconds.clamp(150, 4000);
    return Duration(milliseconds: ms);
  }

  /// A gap (video minus song) past this while playing is closed by a seek; anything smaller by speed.
  static const seekBeyond = Duration(milliseconds: 2500);

  /// The video's speed that closes a gap of [drift] (video minus song) in
  /// about three seconds; within 40 ms it is in step. Between 0.7 and 1.4
  /// times, so a gap up to [seekBeyond] closes in a few seconds without a seek.
  @visibleForTesting
  static double catchUpRate(Duration drift) {
    final ms = drift.inMilliseconds;
    if (ms.abs() <= 40) return 1;
    return (1 - ms / 3000).clamp(0.7, 1.4);
  }

  @override
  void dispose() {
    _disposed = true;
    _c?.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    _release?.cancel();
    _unfocusedRelease?.cancel();
    _stop();
    super.dispose();
  }
}

/// media_kit's player (the video drawn by Flutter through a texture) as a [VideoEngine].
class _KitEngine implements VideoEngine {
  _KitEngine(this.kit);

  final Player kit;

  @override
  Duration get position => kit.state.position;
  @override
  bool get playing => kit.state.playing;
  @override
  bool get buffering => kit.state.buffering;
  @override
  Future<void> play() => kit.play();
  @override
  Future<void> pause() => kit.pause();
  @override
  Future<void> seek(Duration to) => kit.seek(to);
  @override
  Future<void> setRate(double rate) => kit.setRate(rate);
  @override
  Future<String> getProperty(String name) => (kit.platform as NativePlayer).getProperty(name);
  @override
  Future<void> setProperty(String name, String value) => (kit.platform as NativePlayer).setProperty(name, value);
  @override
  Future<void> dispose() => kit.dispose();
}

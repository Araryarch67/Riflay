import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:media_kit_video/media_kit_video.dart';

import '../models/track.dart';
import 'player_controller.dart';
import 'youtube_stream.dart';
import 'ytmusic_web.dart';

/// Video mode (Beta): a YouTube song's music video on the Now Playing views,
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
class VideoMode extends ChangeNotifier with WidgetsBindingObserver {
  VideoMode._();

  static final instance = VideoMode._();

  /// Phones get a lighter stream: less data, less to decode.
  static int get maxHeight => Platform.isAndroid || Platform.isIOS ? 480 : 720;

  PlayerController? _c;

  /// Starts following [c]'s current song. Called by the views; once is enough.
  void follow(PlayerController c) {
    if (identical(_c, c)) return;
    _c?.removeListener(_changed);
    if (_c == null) WidgetsBinding.instance.addObserver(this);
    _c = c;
    c.addListener(_changed);
    _probe();
  }

  // ---- Which songs have a video ----

  /// Whether this device's mpv can decode video at all. The Android and Apple
  /// builds are made for sound only; they keep the switch hidden until a
  /// build with video decoders comes along.
  bool _canDecode = false;
  bool _probed = false;

  Future<void> _probe() async {
    if (_probed) return;
    _probed = true;
    if (Platform.isLinux || Platform.isWindows) {
      _canDecode = true;
      notifyListeners();
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
  @visibleForTesting
  static bool decodesVideo(String decoderList) => RegExp(r'\b(h264|vp9|libdav1d|av1)\b').hasMatch(decoderList);

  /// Looked-up songs: the video, or null for none. Missing while not asked yet.
  final _found = <String, MusicVideo?>{};
  final _asking = <String>{};

  /// The music video of [track], when it has one and this device can show it.
  MusicVideo? videoOf(Track? track) => _canDecode ? _found[track?.videoId] : null;

  /// Asks YouTube Music once whether [track] has a video (one small request,
  /// made when a Now Playing view shows the song; no video data).
  void lookUp(Track? track) {
    final id = track?.videoId;
    final c = _c;
    if (id == null || c == null || !_canDecode || _found.containsKey(id) || !_asking.add(id)) return;
    c.ytMusic
        .musicVideo(id)
        .then(
          (v) => _found[id] = v,
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

  @visibleForTesting
  void debugSetFound(String videoId, MusicVideo? video) {
    _canDecode = _probed = true;
    _found[videoId] = video;
    notifyListeners();
  }

  // ---- The switch ----

  bool _on = false;

  /// Video (true) or Song: what the user picked. It lasts until they pick
  /// Song, or the app goes to the background.
  bool get on => _on;

  /// A calm line under the switch when the video couldn't be shown.
  String? get notice => _notice;
  String? _notice;

  void setOn(bool on) {
    if (on == _on) return;
    _on = on;
    _notice = null;
    _sync();
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Phones: the screen went off or another app is in front. The song plays on alone.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) setOn(false);
  }

  // ---- The video player ----

  int _views = 0;
  Timer? _release;

  /// A view that shows the video came on screen (or went away). The video is
  /// only fetched and decoded while one is.
  void addView() {
    _views++;
    _release?.cancel();
    // Views come on screen while the tree builds: start the video right after.
    scheduleMicrotask(_sync);
  }

  void removeView() {
    _views--;
    // A page changing, or the cover moving between layouts, briefly has no view: keep the video through that.
    _release?.cancel();
    _release = Timer(const Duration(seconds: 2), _sync);
  }

  Player? _player;
  VideoController? _video;
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
      _player == null ? null : (position: _player!.state.position, playing: _player!.state.playing);

  /// What should play now, from the facts: Video picked, a view on screen,
  /// and the current song has a video.
  MusicVideo? get _wanted => _on && _views > 0 ? videoOf(_c?.currentTrack) : null;

  void _changed() {
    final track = _c?.currentTrack;
    if (_on) lookUp(track);
    _sync();
    _follow();
  }

  void _sync() {
    final want = _wanted;
    if (want == null) {
      if (_player != null) _stop();
      return;
    }
    if (_loaded != want.videoId) _start(want);
  }

  Future<void> _start(MusicVideo v) async {
    await _stop();
    _loaded = v.videoId;
    _playing = v;
    final player = _player = Player(
      configuration: const PlayerConfiguration(muted: true, title: 'Riflay video', bufferSize: 4 << 20),
    );
    final video = _video = VideoController(player);
    notifyListeners();
    try {
      final mpv = player.platform as NativePlayer;
      // Video only: no sound track, and only half a minute read ahead (not the whole video).
      await mpv.setProperty('aid', 'no');
      await mpv.setProperty('cache-secs', '30');
      await mpv.setProperty('demuxer-max-bytes', '${32 << 20}');
      await mpv.setProperty('demuxer-max-back-bytes', '${8 << 20}');
      final stream = await YoutubeStream.video(v.videoId, maxHeight: maxHeight);
      if (!identical(player, _player)) return;
      debugPrint('Video mode: ${v.videoId} at ${stream.height}p ${stream.codec}');
      final at = v.videoTimeAt(_c?.position ?? Duration.zero) ?? Duration.zero;
      await player.open(Media(stream.url.toString(), start: at), play: false);
      await video.waitUntilFirstFrameRendered.timeout(const Duration(seconds: 25));
      if (!identical(player, _player)) return;
      _ready = true;
      _tick = Timer.periodic(const Duration(milliseconds: 250), (_) => _follow());
      _follow();
      notifyListeners();
    } catch (e) {
      if (!identical(player, _player)) return;
      debugPrint('Video mode: ${v.videoId} failed: $e');
      _found[_c?.currentTrack?.videoId ?? ''] = null;
      _on = false;
      _notice = 'The video couldn\'t load, so the song plays on its own.';
      await _stop();
      notifyListeners();
    }
  }

  Future<void> _stop() async {
    final player = _player;
    _tick?.cancel();
    _tick = null;
    _player = null;
    _video = null;
    _loaded = null;
    _playing = null;
    _ready = false;
    _rate = 1;
    _seekedTo = null;
    notifyListeners();
    await player?.dispose();
  }

  /// Keeps the video with the song: same play / pause; a small gap closes by
  /// running the video a little faster or slower (invisible, and no new
  /// buffering), a big one (a seek, a stall) with a seek of its own, aimed
  /// ahead by what the last one took. A seek waits for the last one to land.
  void _follow() {
    final c = _c, player = _player, v = _playing;
    if (c == null || player == null || v == null || !_ready) return;
    final target = v.videoTimeAt(c.position);
    final play = target != null && c.isPlaying && !c.isBuffering;
    var rate = 1.0;
    if (target != null) {
      final drift = player.state.position - target;
      final now = DateTime.now();
      // Once the video moves on after a seek, the gap left says how far ahead to aim next time.
      if (_seekedTo case final to? when player.state.position > to + const Duration(milliseconds: 100)) {
        _seekedTo = null;
        if (play) _lead = nextLead(_lead, drift);
      }
      // A seek that never lands (a stalled connection) stops holding the next one back.
      if (now.difference(_lastSeek) > const Duration(seconds: 8)) _seekedTo = null;
      // A paused song is matched exactly. A song that is only buffering (a streamed song does, briefly, between
      // chunks) just pauses the video: a seek would send it back to the network for nothing.
      if (drift.abs() > const Duration(seconds: 1) || !c.isPlaying && drift.abs() > const Duration(milliseconds: 100)) {
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
    if (play != player.state.playing) (play ? player.play() : player.pause()).ignore();
  }

  /// The next seek's [lead], from the gap [drift] (video minus song) the last
  /// one left: behind means aim further ahead.
  @visibleForTesting
  static Duration nextLead(Duration lead, Duration drift) {
    final ms = (lead - drift).inMilliseconds.clamp(150, 4000);
    return Duration(milliseconds: ms);
  }

  /// The video's speed that closes a gap of [drift] (video minus song) in
  /// about three seconds; within 40 ms it is in step.
  @visibleForTesting
  static double catchUpRate(Duration drift) {
    final ms = drift.inMilliseconds;
    if (ms.abs() <= 40) return 1;
    return (1 - ms / 3000).clamp(0.75, 1.25);
  }

  @override
  void dispose() {
    _c?.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    _release?.cancel();
    _stop();
    super.dispose();
  }
}

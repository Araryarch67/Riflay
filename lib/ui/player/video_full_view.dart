import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../models/track.dart';
import '../../services/appearance.dart';
import '../../services/language.dart';
import '../../services/layout_prefs.dart';
import '../../services/lyrics.dart';
import '../../services/player_controller.dart';
import '../../services/video_mode.dart';
import '../debug_switches.dart';
import '../pages/queue_page.dart';
import '../shell_scope.dart';
import '../theme.dart';
import '../widgets/controls.dart';
import '../ytmusic_edit.dart' show LikeButton;
import '../widgets/video_mode.dart';
import 'full_screen_player.dart' show windowFullScreen;

/// The name of the full-screen video's route, so Now Playing can tell it is on top.
const videoFullViewRouteName = 'video-full-view';

/// A phone (not a tablet): the full-screen video turns it sideways. A tablet keeps its orientation, since turning
/// it wide would swap the phone layout (and Now Playing under the video) for the desktop one.
bool _isPhone(BuildContext context) =>
    (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS) &&
    MediaQuery.sizeOf(context).shortestSide < 600;

/// Opens the music video full screen ([VideoFullView]) over Now Playing. [rotated]: the phone was turned sideways
/// to open it, so turning it back upright closes it (the orientation isn't locked then).
Future<void> openVideoFullView(BuildContext context, {bool rotated = false}) {
  final shell = context.dependOnInheritedWidgetOfExactType<ShellScope>();
  final phone = _isPhone(context);
  // The root navigator: on a computer the cover sits in the page history, which this view must not join.
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      settings: const RouteSettings(name: videoFullViewRouteName),
      transitionDuration: LayoutPrefs.dur(const Duration(milliseconds: 220)),
      reverseTransitionDuration: LayoutPrefs.dur(const Duration(milliseconds: 180)),
      pageBuilder: (_, _, _) => VideoFullView(
        lockLandscape: phone && !rotated,
        closeUpright: phone && rotated,
        openQueue: shell?.openQueue,
        shell: shell,
      ),
      transitionsBuilder: (_, anim, _, child) => FadeTransition(opacity: anim, child: child),
    ),
  );
}

/// The music video full screen, uncropped (letterboxed), in step with the song as on the cover: the same player
/// and picture ([VideoPicture]), no second decoder. A tap shows the controls (play, previous / next, the seek bar,
/// the title, like, a line of lyrics, Queue and a close button) for a few seconds. The phone turns sideways and the
/// system bars hide; closing puts both back.
///
/// On a computer it fills the window: the controls sit above and below the picture (the native video's surface lies
/// over anything drawn on it) and go, with the pointer, after a few seconds without a move. F11 or a double click
/// fills the screen, Esc leaves it (then the view), and Queue opens beside the picture.
class VideoFullView extends StatefulWidget {
  const VideoFullView({super.key, this.lockLandscape = false, this.closeUpright = false, this.openQueue, this.shell});

  /// Turns the phone sideways while open (opened from the button).
  final bool lockLandscape;

  /// Closes when the phone is held upright again (opened by turning it sideways).
  final bool closeUpright;

  /// A phone's Queue, opened over this view.
  final VoidCallback? openQueue;

  /// The shell it was opened from: a computer's Queue panel beside the picture is built with it.
  final ShellScope? shell;

  /// How long the controls stay after the last touch.
  static const controlsFor = Duration(seconds: 4);

  @override
  State<VideoFullView> createState() => _VideoFullViewState();
}

class _VideoFullViewState extends State<VideoFullView> {
  /// Kept between openings in a session: someone who reads along wants it again.
  static bool _lyricsShown = false;

  bool _controls = true;
  Timer? _hide;
  bool _restored = false;
  bool _closing = false;

  /// The pointer is over the bars: they stay.
  bool _overBars = false;

  /// A computer's Queue panel beside the picture.
  bool _queuePanel = false;

  /// This view made the window fill the screen (and puts it back on closing).
  bool _madeFull = false;

  /// A computer: the window layout, not the phone's.
  bool get _desktop => !(widget.lockLandscape || widget.closeUpright) && !(widget.shell?.compact ?? true);

  @override
  void initState() {
    super.initState();
    if (widget.lockLandscape) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _showControls();
  }

  /// The orientation and the system bars as they were: back to what the app declares, both bars shown.
  void _restore() {
    if (_restored) return;
    _restored = true;
    if (widget.lockLandscape) SystemChrome.setPreferredOrientations(const []);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    if (_madeFull && windowFullScreen.value) _setWindowFull(false);
  }

  /// Fills the screen with the window, or leaves it (F11, a double click, the button). The title bar goes with it
  /// ([windowFullScreen]).
  Future<void> _setWindowFull(bool full) async {
    windowFullScreen.value = full;
    _madeFull = full;
    if (mounted) setState(() {});
    try {
      await windowManager.setFullScreen(full);
    } catch (e) {
      debugPrint('Video full screen: $e'); // the view still fills the window
    }
  }

  /// Esc: out of the screen-filling window first, then out of the view.
  void _escape() {
    if (_madeFull && windowFullScreen.value) {
      _setWindowFull(false);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.closeUpright && MediaQuery.orientationOf(context) == Orientation.portrait) _close();
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    _restore();
    super.dispose();
  }

  void _showControls() {
    _hide?.cancel();
    if (!_controls) setState(() => _controls = true);
    _hide = Timer(VideoFullView.controlsFor, () {
      if (mounted && !_overBars && !_queuePanel) setState(() => _controls = false);
    });
  }

  void _hideControls() {
    _hide?.cancel();
    _overBars = false;
    setState(() => _controls = false);
  }

  void _toggleLyrics() {
    setState(() => _lyricsShown = !_lyricsShown);
    _showControls();
  }

  void _queue() {
    if (_desktop) {
      setState(() => _queuePanel = !_queuePanel);
      _showControls();
      return;
    }
    widget.openQueue?.call();
  }

  @override
  Widget build(BuildContext context) {
    final c = PlayerScope.read(context);
    // Windows / Linux draw the video in a surface of their own over the window: nothing Flutter draws can lie over
    // it, so the controls stay above and below the picture there instead of over it. Phones draw it in the page.
    final stacked = _desktop || VideoMode.native && !_isPhone(context);
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _restore();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _escape,
          const SingleActivator(LogicalKeyboardKey.space): c.togglePlay,
          if (_desktop) const SingleActivator(LogicalKeyboardKey.f11): () => _setWindowFull(!windowFullScreen.value),
        },
        child: Focus(
          autofocus: true,
          child: _OnBlack(
            child: Material(
              color: Colors.black,
              child: PlayerSelect<Track?>(
                select: (c) => c.currentTrack,
                builder: (context, track, _) => stacked ? _stacked(context, track) : _overlaid(context, track),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Phones (and macOS): the picture fills the screen, the controls fade in over it on a tap.
  Widget _overlaid(BuildContext context, Track? track) {
    final lyrics = _lyricsShown && track != null;
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          key: const ValueKey('video-full-surface'),
          behavior: HitTestBehavior.opaque,
          onTap: () => _controls ? _hideControls() : _showControls(),
          child: VideoPicture(track: track),
        ),
        if (lyrics)
          Positioned(
            left: 48,
            right: 48,
            bottom: _controls ? 132 : 24,
            child: IgnorePointer(child: _LyricsLine(track: track)),
          ),
        // Taken out of the tree once faded: a hidden seek bar would still tick.
        AnimatedSwitcher(
          duration: LayoutPrefs.dur(const Duration(milliseconds: 200)),
          child: _controls
              ? Listener(
                  key: const ValueKey('video-full-controls'),
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (_) => _showControls(),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // The empty middle closes them again, as a tap on the picture opened them.
                      GestureDetector(behavior: HitTestBehavior.translucent, onTap: _hideControls),
                      const IgnorePointer(child: _Shade()),
                      SafeArea(child: Column(children: [_topBar(context, track), const Spacer(), _bottomBar()])),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  /// Computers: the controls above and below the picture (nothing can lie over the native video's surface), gone
  /// with the pointer after a few seconds without a move; the picture takes the whole window then.
  Widget _stacked(BuildContext context, Track? track) {
    Widget bars(Widget child) =>
        MouseRegion(onEnter: (_) => _overBars = true, onExit: (_) => _overBars = false, child: child);
    final picture = Column(
      children: [
        if (_controls) bars(_topBar(context, track)),
        Expanded(
          child: GestureDetector(
            key: const ValueKey('video-full-surface'),
            behavior: HitTestBehavior.opaque,
            onTap: () => _controls ? _hideControls() : _showControls(),
            onDoubleTap: _desktop ? () => _setWindowFull(!windowFullScreen.value) : null,
            child: VideoPicture(track: track),
          ),
        ),
        if (_lyricsShown && track != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 8),
            child: _LyricsLine(track: track),
          ),
        // Taken out of the tree while hidden: a hidden seek bar would still tick.
        if (_controls) bars(_bottomBar()),
      ],
    );
    final shell = widget.shell;
    return MouseRegion(
      cursor: _controls ? MouseCursor.defer : SystemMouseCursors.none,
      onHover: (_) => _showControls(),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(child: picture),
            if (_queuePanel && shell != null)
              SizedBox(
                key: const ValueKey('video-full-queue'),
                width: 380,
                child: bars(_QueuePanel(shell: shell)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context, Track? track) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Row(
        children: [
          IconButton(
            // A computer's view closes back to the window; full screen is the button on the right.
            tooltip: _desktop ? tr.close : tr.exitFullScreen,
            color: Colors.white,
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(_desktop ? Icons.close_rounded : Icons.fullscreen_exit_rounded, size: 28),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  track?.title ?? tr.nothingPlaying,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: Colors.white),
                ),
                if (track != null)
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium?.copyWith(color: Colors.white70),
                  ),
              ],
            ),
          ),
          if (track != null) LikeButton(track: track, size: 24, color: Colors.white),
          IconButton(
            tooltip: _lyricsShown ? tr.hideLyrics : tr.showLyrics,
            color: _lyricsShown ? AppColors.of(context).accent : Colors.white,
            isSelected: _lyricsShown,
            onPressed: track == null ? null : _toggleLyrics,
            icon: const Icon(Icons.lyrics_outlined),
          ),
          IconButton(
            tooltip: tr.queue,
            color: _queuePanel ? AppColors.of(context).accent : Colors.white,
            onPressed: _desktop || widget.openQueue != null ? _queue : null,
            icon: const Icon(Icons.queue_music_rounded),
          ),
          if (_desktop)
            ValueListenableBuilder(
              valueListenable: windowFullScreen,
              builder: (context, full, _) => IconButton(
                tooltip: full ? tr.exitFullScreen : tr.fullScreen,
                color: Colors.white,
                onPressed: () => _setWindowFull(!full),
                icon: Icon(full ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded),
              ),
            ),
        ],
      ),
    );
  }

  Widget _bottomBar() => const Padding(
    padding: EdgeInsets.fromLTRB(24, 0, 24, 4),
    child: Column(mainAxisSize: MainAxisSize.min, children: [SeekBar(phonePlayer: true), TransportControls()]),
  );
}

/// The app's colours worked out for black, as Now Playing's Black background does: the controls read on the black
/// around the video whatever the theme.
class _OnBlack extends StatelessWidget {
  const _OnBlack({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final a = Appearance.instance;
    final palette = AppPalette.derive(Colors.black, accent: a.palette.accent);
    final theme = Theme.of(context);
    return AppColorsScope(
      colors: AppColorsView(palette, 1, a.highContrast),
      child: Theme(
        data: theme.copyWith(
          brightness: Brightness.dark,
          textTheme: theme.textTheme.apply(bodyColor: palette.textPrimary, displayColor: palette.textPrimary),
          iconTheme: theme.iconTheme.copyWith(color: palette.textPrimary),
          sliderTheme: theme.sliderTheme.copyWith(
            thumbColor: palette.accent,
            inactiveTrackColor: palette.textPrimary.withValues(alpha: 0.3),
          ),
        ),
        child: child,
      ),
    );
  }
}

/// A computer's Queue beside the picture: the Queue page in a navigator of its own, so it has no back button that
/// would close the view, and with no page history, which lies under this view.
class _QueuePanel extends StatelessWidget {
  const _QueuePanel({required this.shell});

  final ShellScope shell;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.of(context).elevated,
    child: Navigator(
      onGenerateRoute: (_) => PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => ShellScope(
          compact: false,
          width: 380,
          open: shell.open,
          openCollection: shell.openCollection,
          openQueue: shell.openQueue,
          openNowPlaying: shell.openNowPlaying,
          openLyrics: shell.openLyrics,
          openDownloads: shell.openDownloads,
          importFromYoutube: shell.importFromYoutube,
          addFiles: shell.addFiles,
          addFolder: shell.addFolder,
          child: const Material(type: MaterialType.transparency, child: QueuePage()),
        ),
      ),
    ),
  );
}

/// Dark at the top and the foot, under the controls, so white reads over a bright frame.
class _Shade extends StatelessWidget {
  const _Shade();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.black.withValues(alpha: 0.6),
          Colors.transparent,
          Colors.transparent,
          Colors.black.withValues(alpha: 0.7),
        ],
        stops: const [0, 0.3, 0.6, 1],
      ),
    ),
  );
}

/// The line of synced lyrics being sung, over the video. Redrawn only when the line changes; position comes a few
/// times a second while playing and stops while paused ([PlayerController.positionUpdates]).
class _LyricsLine extends StatefulWidget {
  const _LyricsLine({required this.track});

  final Track track;

  @override
  State<_LyricsLine> createState() => _LyricsLineState();
}

class _LyricsLineState extends State<_LyricsLine> {
  List<LyricLine> _lines = const [];
  int _index = -1;
  StreamSubscription<Duration>? _ticks;
  String? _for;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ticks ??= PlayerScope.read(context).positionUpdates().listen(_at);
    _load();
  }

  @override
  void didUpdateWidget(_LyricsLine old) {
    super.didUpdateWidget(old);
    _load();
  }

  void _load() {
    final track = widget.track;
    if (track.id == _for) return;
    _for = track.id;
    _lines = const [];
    _index = -1;
    LyricsService.forTrack(track).then((l) {
      if (!mounted || _for != track.id) return;
      setState(() => _lines = l.lines);
      _at(PlayerScope.read(context).position);
    }, onError: (Object e) => debugPrint('Lyrics over the video: $e'));
  }

  void _at(Duration position) {
    var i = -1;
    for (var n = 0; n < _lines.length && _lines[n].time <= position; n++) {
      i = n;
    }
    if (i != _index) setState(() => _index = i);
  }

  @override
  void dispose() {
    _ticks?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final line = _index < 0 ? '' : _lines[_index].text;
    return AnimatedSwitcher(
      duration: LayoutPrefs.dur(const Duration(milliseconds: 200)),
      child: Text(
        line,
        key: ValueKey(_index),
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          shadows: const [Shadow(blurRadius: 8, color: Colors.black)],
        ),
      ),
    );
  }
}

/// Opens [VideoFullView] when a phone showing the music video in Now Playing is turned sideways
/// ([VideoFullView.closeUpright]: turning it back closes it). Off with `RIFLAY_NO_VIDEO_ROTATE`.
class VideoRotateWatcher extends StatefulWidget {
  const VideoRotateWatcher({super.key, required this.track});

  final Track? track;

  @override
  State<VideoRotateWatcher> createState() => _VideoRotateWatcherState();
}

class _VideoRotateWatcherState extends State<VideoRotateWatcher> {
  Orientation? _was;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final now = MediaQuery.orientationOf(context);
    final turned = _was == Orientation.portrait && now == Orientation.landscape;
    _was = now;
    // Only from Now Playing itself: the full view's own turn (it locks landscape) reaches this page underneath too.
    if (!turned || DebugSwitches.noVideoRotate || !_isPhone(context)) return;
    if (ModalRoute.of(context)?.isCurrent == false) return;
    final mode = VideoMode.instance;
    if (!mode.on || mode.videoOf(widget.track) == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ModalRoute.of(context)?.isCurrent != false) openVideoFullView(context, rotated: true);
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

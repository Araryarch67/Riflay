import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart' show LoopMode;
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import '../../models/track.dart';
import '../../platform/features.dart';
import '../../platform/host.dart';
import '../../services/layout_prefs.dart';
import '../../services/lyrics.dart';
import '../../services/lyrics_translation.dart';
import '../../services/player_controller.dart';
import '../../services/visualizer_levels.dart';
import '../theme.dart';
import '../widgets/audio_reactive_view.dart';
import '../widgets/controls.dart';
import '../widgets/marquee_text.dart';
import '../widgets/playing_motion.dart';
import '../widgets/wavy_seek_track.dart';
import '../widgets/signal_path.dart' show QualityChip;
import 'full_screen_player.dart';
import 'player_common.dart';
import '../../services/language.dart';

/// Desktop mini player: the window shrinks and stays on top of other windows. It takes one of two shapes
/// ([DesktopMiniStyle], Settings › Pages & navigation): a small window with the cover, like Spotify's, or an island,
/// a pill at the top of the screen that opens into the controls when pointed at. The full window comes back at its
/// old size and place (maximized again if it was).
final miniPlayer = ValueNotifier<bool>(false);

/// The shape the mini player has while [miniPlayer] is on.
final miniPlayerStyle = ValueNotifier<DesktopMiniStyle>(DesktopMiniStyle.window);

const _windowSize = Size(460, 224);
const _normalMinimum = Size(320, 420);

/// The island closed (one row: cover, title, playing bars; as wide as Settings says) and open (the mini window's
/// deck).
Size get islandClosedSize => Size(LayoutPrefs.instance.islandWidth.width, _islandDocked ? 40 : 44);
bool get _islandDocked => LayoutPrefs.instance.islandPlacement == IslandPlacement.docked;
const islandOpenSize = _windowSize;
const _islandRadius = 28.0;

/// The island's window: the open pill with room around it for its overshoot and shadow.
const _islandWindow = Size(500, 264);

/// The window before it shrank.
({Rect bounds, bool maximized})? _before;

/// Where each shape was left last in this run, so it comes back there: the mini window's bounds, the island's
/// top centre (it opens downwards and sideways from there).
Rect? _lastWindow;
Offset? _lastIslandTop;

/// The docked island's middle, across the top edge.
double? _lastDockX;

/// The mini player's settings changed while it is on (Settings › Pages & navigation): the island moves to its
/// place (docked or floating) and the window keeps above others or not.
Future<void> refreshMiniPlayer() => _enqueue(() async {
  if (!miniPlayer.value) return;
  try {
    await windowManager.setAlwaysOnTop(LayoutPrefs.instance.miniOnTop);
    if (miniPlayerStyle.value == DesktopMiniStyle.island) {
      await windowManager.setBounds(await _islandBounds(_islandWindow));
    }
  } catch (e) {
    debugPrint('Mini player window: $e');
  }
});

/// Docked, the island goes back to the top edge after it was dragged (it slides only sideways).
Future<void> _snapDocked() => _enqueue(() async {
  if (!miniPlayer.value || miniPlayerStyle.value != DesktopMiniStyle.island || !_islandDocked) return;
  final b = await windowManager.getBounds();
  final top = (await _workArea())?.top ?? 0;
  if ((b.top - top).abs() < 1) return;
  _lastDockX = b.center.dx;
  await windowManager.setPosition(Offset(b.left, top));
});

/// Window changes one after another: a quick second click (or the island opening while it's being left) mustn't
/// read bounds halfway through the first.
Future<void> _queue = Future.value();

Future<void> _enqueue(Future<void> Function() change) {
  final next = _queue.then((_) => change());
  _queue = next.catchError((Object e) => debugPrint('Mini player window: $e'));
  return _queue;
}

const _channel = MethodChannel('riflay/window');

/// Turns the mini player on (in [style], the one in Settings by default) or off. Called while on with another
/// style, it switches shape in place.
Future<void> setMiniPlayer(bool on, {DesktopMiniStyle? style}) =>
    _enqueue(() => _switch(on, style ?? LayoutPrefs.instance.desktopMini));

Future<void> _switch(bool on, DesktopMiniStyle style) async {
  if (on == miniPlayer.value && (!on || style == miniPlayerStyle.value)) return;
  final island = style == DesktopMiniStyle.island;
  try {
    if (on) {
      if (miniPlayer.value) {
        await _rememberSpot();
      } else {
        await setFullScreenPlayer(false);
        // A maximized window ignores a new size on Windows (it stayed full size with the mini view in it); its
        // own normal bounds are the ones to come back to.
        final maximized = await windowManager.isMaximized();
        if (maximized) await windowManager.unmaximize();
        _before = (bounds: await windowManager.getBounds(), maximized: maximized);
      }
      final bounds = island ? await _islandBounds(_islandWindow) : await _windowBounds();
      // The island's view fits any size, the window's needs its own: it shows once the window has grown (from the
      // island, it was drawn squeezed into the pill for a moment).
      if (island) miniPlayerStyle.value = style;
      miniPlayer.value = true;
      await windowManager.setResizable(false);
      await windowManager.setMinimumSize(island ? _islandWindow : _windowSize);
      // The island's view tells the window where it takes clicks once it has its size.
      if (!island) await _islandHit(null);
      await windowManager.setBounds(bounds);
      miniPlayerStyle.value = style;
      // Again, now the island's view is gone: one last frame of it, laid out at the new size while the window grew,
      // may have sent its pill after the first, and the window then showed only a pill-shaped strip of itself.
      if (!island) await _islandHit(null);
      await windowManager.setAlwaysOnTop(LayoutPrefs.instance.miniOnTop);
      await _followTaskbar();
    } else {
      await _rememberSpot();
      miniPlayer.value = false;
      await _followTaskbar();
      await windowManager.setAlwaysOnTop(false);
      await _islandHit(null);
      await windowManager.setResizable(true);
      await windowManager.setMinimumSize(_normalMinimum);
      if (_before case final b?) {
        await windowManager.setBounds(b.bounds);
        if (b.maximized) await windowManager.maximize();
      }
      _before = null;
    }
  } catch (e) {
    // Tiling compositors may refuse to resize; the view switches anyway.
    debugPrint('Mini player window: $e');
    miniPlayer.value = on;
    await _followTaskbar();
  }
}

/// Whether the window keeps off the taskbar: while it's the mini player (always on top, so it needs no button),
/// except minimized, where the button is the way back (otherwise only Alt+Tab or the tray would find it).
@visibleForTesting
bool miniSkipsTaskbar({required bool mini, required bool minimized}) => mini && !minimized;

bool _minimized = false;
_TaskbarFollower? _taskbarFollower;

/// Takes the taskbar button away or brings it back to match [miniSkipsTaskbar]. Sent again on every focus too:
/// Windows puts a removed button back when the window is shown again (from the tray, say).
Future<void> _followTaskbar() async {
  if (!Features.miniPlayerOffTaskbar) return;
  if (miniPlayer.value && _taskbarFollower == null) windowManager.addListener(_taskbarFollower = _TaskbarFollower());
  try {
    await windowManager.setSkipTaskbar(miniSkipsTaskbar(mini: miniPlayer.value, minimized: _minimized));
  } catch (e) {
    debugPrint('Mini player taskbar: $e');
  }
}

class _TaskbarFollower with WindowListener {
  void _set(bool minimized) {
    _minimized = minimized;
    if (miniPlayer.value) unawaited(_enqueue(_followTaskbar));
  }

  @override
  void onWindowMinimize() => _set(true);

  @override
  void onWindowRestore() => _set(false);

  @override
  void onWindowFocus() => _set(false);
}

Future<void> _rememberSpot() async {
  if (!miniPlayer.value) return;
  final b = await windowManager.getBounds();
  if (miniPlayerStyle.value == DesktopMiniStyle.island) {
    if (_islandDocked) {
      _lastDockX = b.center.dx;
    } else {
      _lastIslandTop = b.topCenter;
    }
  } else {
    _lastWindow = b;
  }
}

/// Where the island takes clicks, in its window of [client] size: the closed pill, or (open, or on its way there)
/// all of it; null turns the island's window off. Windows keeps only that part of the window ([SetIsland] in the
/// runner) and lets Flutter's clear pixels show the desktop, so the pill can grow and shrink inside a window that
/// keeps its size; Linux's window is see-through anyway. macOS gets a clear window background.
Future<void> _islandHit(bool? open, [Size client = Size.zero]) async {
  try {
    if (Host.isWindows) {
      await _channel.invokeMethod<void>('setIsland', switch (open) {
        null => <double>[],
        true => <double>[0, 0, client.width, client.height],
        // The pill sits at the top middle (the island view's Align); a pixel around it for its anti-aliased edge.
        false => <double>[
          (client.width - islandClosedSize.width) / 2 - 1,
          0,
          islandClosedSize.width + 2,
          islandClosedSize.height + 1,
        ],
      });
    } else if (Host.isMacOS) {
      await windowManager.setBackgroundColor(open == null ? AppColors.solidBackground : Colors.transparent);
      await windowManager.setHasShadow(open == null);
    }
  } catch (e) {
    debugPrint('Island window: $e');
  }
}

/// The visible part of the screen the window is on (without the taskbar).
Future<Rect?> _workArea() async {
  if (Host.isWindows) {
    try {
      final edges = await _channel.invokeListMethod<double>('currentMonitorWorkArea');
      if (edges?.length == 4) return Rect.fromLTRB(edges![0], edges[1], edges[2], edges[3]);
    } on PlatformException catch (e) {
      debugPrint('Monitor work area: ${e.code}');
    } on MissingPluginException {
      // An older Windows runner can still report the displays through the plugin.
    }
  }
  try {
    final centre = (await windowManager.getBounds()).center;
    return nearestMonitorWorkArea(centre, (await screenRetriever.getAllDisplays()).map(_displayArea));
  } catch (e) {
    debugPrint('Screen size: $e');
    return null;
  }
}

Rect _displayArea(Display display) => (display.visiblePosition ?? Offset.zero) & (display.visibleSize ?? display.size);

@visibleForTesting
Rect? nearestMonitorWorkArea(Offset point, Iterable<Rect> areas) {
  Rect? nearest;
  var distance = double.infinity;
  for (final area in areas) {
    if (area.contains(point)) return area;
    final edge = Offset(point.dx.clamp(area.left, area.right), point.dy.clamp(area.top, area.bottom));
    final gap = (point - edge).distanceSquared;
    if (gap < distance) {
      distance = gap;
      nearest = area;
    }
  }
  return nearest;
}

/// First time: the bottom-right corner of the screen, out of the way. Then wherever it was left.
Future<Rect> _windowBounds() async {
  if (_lastWindow case final last?) return last;
  final area = await _workArea();
  if (area == null) return Offset.zero & _windowSize;
  return Rect.fromLTWH(
    area.right - _windowSize.width - 24,
    area.bottom - _windowSize.height - 24,
    _windowSize.width,
    _windowSize.height,
  );
}

/// First time: the top middle of the screen, where islands sit. Then wherever it was dragged.
Future<Rect> _islandBounds(Size size) async {
  final area = await _workArea();
  if (_islandDocked) {
    // On the top edge (below a taskbar there), where it was slid to.
    final x = _lastDockX ?? _lastIslandTop?.dx ?? area?.center.dx ?? size.width / 2;
    return Rect.fromLTWH(x - size.width / 2, area?.top ?? 0, size.width, size.height);
  }
  var top = _lastIslandTop;
  top ??= area == null ? Offset(size.width / 2, 0) : area.topCenter + const Offset(0, 8);
  return Rect.fromLTWH(top.dx - size.width / 2, top.dy, size.width, size.height);
}

class MiniPlayerWindow extends StatefulWidget {
  const MiniPlayerWindow({super.key});

  @override
  State<MiniPlayerWindow> createState() => _MiniPlayerWindowState();
}

class _MiniPlayerWindowState extends State<MiniPlayerWindow> {
  // The mini player sits outside the app's Navigator: its own Overlay gives the play button's tooltip (and the
  // others) somewhere to show. Without it, pointing at play threw "No Overlay widget found".
  late final _entry = OverlayEntry(
    builder: (context) => ValueListenableBuilder(
      valueListenable: miniPlayerStyle,
      builder: (context, style, _) => style == DesktopMiniStyle.island
          ? const _IslandView()
          // A window still on its way to its size (or a compositor that refused it) gets the view scaled down
          // rather than cut off.
          : LayoutBuilder(
              builder: (context, box) => box.maxHeight >= 180 && box.maxWidth >= 360
                  ? const _WindowView()
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.topCenter,
                      child: SizedBox.fromSize(size: _windowSize, child: const _WindowView()),
                    ),
            ),
    ),
  );

  @override
  void dispose() {
    _entry
      ..remove()
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = PlayerScope.read(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): () {
          if (c.canPlay) c.togglePlay();
        },
        const SingleActivator(LogicalKeyboardKey.escape): () => setMiniPlayer(false),
        const SingleActivator(LogicalKeyboardKey.arrowRight, control: true): c.next,
        const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true): c.previous,
      },
      child: Focus(autofocus: true, child: Overlay(initialEntries: [_entry])),
    );
  }
}

/// Song and play state: the parts both shapes rebuild on. The position has its own stream ([MiniProgress]).
typedef _Now = ({Track? track, bool playing, bool canPlay, bool buffering});

Widget _nowBuilder(Widget Function(BuildContext context, PlayerController c, _Now now) builder) => PlayerSelect<_Now>(
  select: (c) => (track: c.currentTrack, playing: c.showsPlaying, canPlay: c.canPlay, buffering: c.isBuffering),
  builder: (context, now, _) => builder(context, PlayerScope.read(context), now),
);

/// The mini window: the deck on a surface tinted by the cover.
class _WindowView extends StatelessWidget {
  const _WindowView();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    // What it shows is up to Settings (volume, shuffle and repeat, the quality badge).
    listenable: LayoutPrefs.instance,
    builder: (context, _) => _nowBuilder(
      (context, c, now) => AccentBuilder(
        track: now.track,
        // An M3 surface tinted by the cover, solid: it's a window of its own.
        builder: (context, accent) => ColoredBox(
          color: AppColors.sink(accent, 0.86).withValues(alpha: 1),
          child: _Deck(c: c, now: now, island: false, lyricColor: AppColors.accent),
        ),
      ),
    ),
  );
}

/// The mini player laid out like a small deck: the cover beside the song and the line being sung, the seek bar
/// across, and a row of controls (shuffle and repeat, previous / play / next, lyrics) at its foot. The mini window
/// and the open island both show it.
class _Deck extends StatelessWidget {
  const _Deck({required this.c, required this.now, required this.island, required this.lyricColor});

  final PlayerController c;
  final _Now now;

  /// Inside the island: its corner button goes to the mini window instead.
  final bool island;
  final Color lyricColor;

  @override
  Widget build(BuildContext context) {
    final track = now.track;
    final text = Theme.of(context).textTheme;
    final ink = _Ink.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      child: Column(
        children: [
          Expanded(
            // Dragging the cover or the song moves the window (not the seek bar or the buttons below); the docked
            // island's only along the top edge.
            child: _IslandDrag(
              docked: island && _islandDocked,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: track == null
                        ? Artwork(track: null, radius: 16)
                        : TrackSwitcher(
                            trackId: track.id,
                            slide: false,
                            child: Artwork(key: ValueKey(track.id), track: track, radius: 16),
                          ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: MarqueeText(
                                track?.title ?? tr.nothingPlaying,
                                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: ink.text),
                              ),
                            ),
                            const _LyricsToggle(),
                            island
                                ? _SmallIcon(
                                    icon: Icons.picture_in_picture_alt_rounded,
                                    tooltip: tr.miniSwitchToWindow,
                                    onPressed: () => setMiniPlayer(true, style: DesktopMiniStyle.window),
                                  )
                                : _SmallIcon(
                                    icon: Icons.call_to_action_rounded,
                                    tooltip: tr.miniSwitchToIsland,
                                    onPressed: () => setMiniPlayer(true, style: DesktopMiniStyle.island),
                                  ),
                            _SmallIcon(
                              icon: Icons.open_in_full_rounded,
                              tooltip: tr.miniBackToApp,
                              onPressed: () => setMiniPlayer(false),
                            ),
                          ],
                        ),
                        if (track != null)
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  track.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.bodyMedium?.copyWith(color: ink.muted),
                                ),
                              ),
                              // "FLAC 24/44.1": what's playing, as the player's quality badge says it.
                              if (LayoutPrefs.instance.miniQuality) ...[
                                const SizedBox(width: 8),
                                QualityChip(color: ink.muted),
                              ],
                            ],
                          ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: _LyricLine(
                            track: track,
                            builder: (context, lyric) => _Lyric(
                              now: lyric,
                              style: text.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: lyricColor,
                                height: 1.25,
                              ),
                              saidStyle: text.bodySmall?.copyWith(color: lyricColor.withValues(alpha: 0.75)),
                              nextStyle: text.bodySmall?.copyWith(color: ink.muted),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          _MiniSeek(c: c, enabled: track != null),
          _WindowControls(c: c, now: now),
        ],
      ),
    );
  }
}

/// Shuffle and repeat on the left, previous / play / next in the middle, the lyrics switch on the right. M3 toggle
/// buttons: the accent and a tonal fill while on.
class _WindowControls extends StatelessWidget {
  const _WindowControls({required this.c, required this.now});

  final PlayerController c;
  final _Now now;

  @override
  Widget build(BuildContext context) => PlayerSelect<({bool shuffle, LoopMode loop, bool hasQueue})>(
    select: (c) => (shuffle: c.shuffle, loop: c.loopMode, hasQueue: c.hasQueue),
    builder: (context, q, _) => Row(
      children: [
        Expanded(
          child: Row(
            children: [
              if (LayoutPrefs.instance.miniShuffleRepeat) ...[
                _Toggle(
                  icon: Icons.shuffle_rounded,
                  tooltip: q.shuffle ? tr.disableShuffle : tr.enableShuffle,
                  on: q.shuffle,
                  onPressed: q.hasQueue ? c.toggleShuffle : null,
                ),
                _Toggle(
                  icon: q.loop == LoopMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                  tooltip: switch (q.loop) {
                    LoopMode.off => tr.enableRepeat,
                    LoopMode.all => tr.enableRepeatOne,
                    LoopMode.one => tr.disableRepeat,
                  },
                  on: q.loop != LoopMode.off,
                  onPressed: q.hasQueue ? c.cycleLoopMode : null,
                ),
              ],
            ],
          ),
        ),
        _Transport(c: c, now: now, size: 46),
        Expanded(child: LayoutPrefs.instance.miniVolume ? const _MiniVolume() : const SizedBox.shrink()),
      ],
    ),
  );
}

/// The lyrics switch, small beside the window buttons at the top: on, the line being sung shows under the song.
class _LyricsToggle extends StatelessWidget {
  const _LyricsToggle();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: LayoutPrefs.instance,
    builder: (context, _) {
      final on = LayoutPrefs.instance.miniLyrics;
      return _Toggle(
        icon: Icons.lyrics_outlined,
        tooltip: on ? tr.hideLyrics : tr.showLyrics,
        on: on,
        small: true,
        onPressed: () => LayoutPrefs.instance.setMiniLyrics(!on),
      );
    },
  );
}

/// Mute and a volume slider, in the ink of the shape around them (light on the island). The same level as the
/// player bar's: the cast device's while casting, fixed at full for DoP (the DAC's own volume is the one to use);
/// the scroll wheel nudges it.
class _MiniVolume extends StatelessWidget {
  const _MiniVolume();

  @override
  Widget build(BuildContext context) {
    final c = PlayerScope.read(context);
    final ink = _Ink.of(context);
    return PlayerSelect<({bool casting, double device, bool canSet, bool dop})>(
      select: (c) => (
        casting: c.casting,
        device: c.casting ? c.volume : 0,
        canSet: c.canSetVolume,
        dop: !c.casting && c.audio.dopPlaying != null,
      ),
      builder: (context, v, _) => ValueListenableBuilder<double>(
        valueListenable: c.volumeLevel,
        builder: (context, level, _) {
          final volume = v.dop ? 1.0 : (v.casting ? v.device : level);
          final setVolume = v.canSet && !v.dop ? c.setVolume : null;
          final row = Listener(
            onPointerSignal: (e) {
              if (e is PointerScrollEvent && setVolume != null) c.nudgeVolume(e.scrollDelta.dy < 0 ? 0.05 : -0.05);
            },
            child: Row(
              children: [
                IconButton(
                  tooltip: volume == 0 ? tr.unmute : tr.mute,
                  iconSize: 20,
                  visualDensity: VisualDensity.compact,
                  color: ink.muted,
                  onPressed: setVolume == null ? null : c.toggleMute,
                  icon: Icon(
                    volume == 0
                        ? Icons.volume_off_rounded
                        : volume < 0.5
                        ? Icons.volume_down_rounded
                        : Icons.volume_up_rounded,
                  ),
                ),
                Expanded(
                  child: ListenableBuilder(
                    listenable: LayoutPrefs.instance,
                    builder: (context, slider) {
                      final base = SliderTheme.of(context);
                      final look = LayoutPrefs.instance.volumeSlider;
                      final theme = switch (look) {
                        VolumeSliderShape.classic => base.copyWith(
                          trackHeight: 4,
                          trackShape: const RoundedRectSliderTrackShape(),
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6, elevation: 0),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                          activeTrackColor: ink.text,
                          inactiveTrackColor: ink.text.withValues(alpha: 0.18),
                          thumbColor: ink.text,
                        ),
                        VolumeSliderShape.thin => thinSliderTheme(base, ink.text),
                        VolumeSliderShape.pill => pillSliderTheme(base, ink.text, height: 12, thumb: 28),
                      };
                      return SliderTheme(
                        data: theme.copyWith(padding: const EdgeInsets.symmetric(horizontal: 6)),
                        child: SizedBox(height: look == VolumeSliderShape.pill ? 28 : 24, child: slider),
                      );
                    },
                    child: Slider(
                      value: volume.clamp(0, 1),
                      onChangeStart: setVolume == null ? null : (_) => c.volumeDragStarted(),
                      onChanged: setVolume,
                    ),
                  ),
                ),
              ],
            ),
          );
          return v.dop ? Tooltip(message: tr.dsdUseDacVolume, child: row) : row;
        },
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.icon,
    required this.tooltip,
    required this.on,
    required this.onPressed,
    this.small = false,
  });

  final IconData icon;
  final String tooltip;
  final bool on;
  final VoidCallback? onPressed;

  /// The size of the window buttons beside it ([_SmallIcon]).
  final bool small;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    isSelected: on,
    iconSize: small ? 18 : 20,
    visualDensity: small ? VisualDensity.compact : null,
    color: _Ink.of(context).muted,
    selectedIcon: Icon(icon, color: AppColors.accent),
    style: IconButton.styleFrom(backgroundColor: on ? AppColors.accent.withValues(alpha: 0.16) : null),
    onPressed: onPressed,
    icon: Icon(icon),
  );
}

/// The island: a black pill at the top of the screen with the cover, title (or the line being sung) and bars that
/// follow the music. Pointed at (or clicked) it grows into the mini window's deck on springs, width a little ahead
/// of height, the row blurring away and the deck coming into focus; it folds back a moment after the pointer
/// leaves. The window keeps the open size the whole time: only the pill Flutter draws moves.
class _IslandView extends StatefulWidget {
  const _IslandView();

  @override
  State<_IslandView> createState() => _IslandViewState();
}

class _IslandViewState extends State<_IslandView> with TickerProviderStateMixin, WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  // Dragged off the top edge while docked: back onto it.
  @override
  void onWindowMoved() => _snapDocked();

  /// 0 closed, 1 open; past 1 while a spring overshoots.
  late final _w = AnimationController.unbounded(vsync: this);
  late final _h = AnimationController.unbounded(vsync: this);
  late final _both = Listenable.merge([_w, _h]);

  // Opening bounces a little (about 5% past), width first; closing settles without one.
  static final _openWidth = SpringDescription.withDampingRatio(mass: 1, stiffness: 420, ratio: 0.68);
  static final _openHeight = SpringDescription.withDampingRatio(mass: 1, stiffness: 300, ratio: 0.7);
  static final _close = SpringDescription.withDampingRatio(mass: 1, stiffness: 360, ratio: 0.92);

  Timer? _timer;
  bool _open = false;

  /// What the window was last told about clicks: the island's state and its size.
  (bool, Size, Size)? _sent;

  void _later(Duration after, bool open) {
    _timer?.cancel();
    _timer = Timer(after, () => _set(open));
  }

  void _set(bool open) {
    if (!mounted || open == _open) return;
    setState(() => _open = open);
    final target = open ? 1.0 : 0.0;
    if (!LayoutPrefs.moves || MediaQuery.disableAnimationsOf(context)) {
      _w.value = _h.value = target;
      return;
    }
    _w.animateWith(SpringSimulation(open ? _openWidth : _close, _w.value, target, _w.velocity));
    final folded = _h.animateWith(SpringSimulation(open ? _openHeight : _close, _h.value, target, _h.velocity));
    // Clicks around the pill go back to the windows behind once it has folded (a spring cut short by the pointer
    // coming back never completes, and the island stays open).
    if (!open) folded.then((_) => _syncHit(force: true));
  }

  /// Opening, the whole window takes clicks at once, so the pill never grows into a part that lets them through.
  void _syncHit({bool force = false}) {
    // Only while the window is the island: a frame of it left over from a switch to the mini window (or out of the
    // mini player) would cut that window down to the pill.
    if (!mounted || !miniPlayer.value || miniPlayerStyle.value != DesktopMiniStyle.island) return;
    final open = _open || _h.value > 0.01;
    final size = MediaQuery.sizeOf(context);
    // The closed pill's size too: Settings may change its width or placement while it shows.
    if (!force && _sent == (open, size, islandClosedSize)) return;
    _sent = (open, size, islandClosedSize);
    _islandHit(open, size);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _timer?.cancel();
    _w.dispose();
    _h.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // After the frame: the window's size (it changes as the island takes over the window) and state.
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncHit());
    return ListenableBuilder(
      listenable: LayoutPrefs.instance,
      builder: (context, _) => _nowBuilder(
        (context, c, now) => AccentBuilder(
          track: now.track,
          builder: (context, accent) {
            final prefs = LayoutPrefs.instance;
            final docked = _islandDocked;
            // Black like an island, with as much of the cover's colour as Settings says; its text is light whatever
            // the theme.
            final panel = Color.alphaBlend(accent.withValues(alpha: prefs.islandColor.tint), const Color(0xFF0A0A0C));
            final lyric = Color.lerp(accent, Colors.white, 0.45)!;
            return Align(
              alignment: Alignment.topCenter,
              child: AnimatedBuilder(
                animation: _both,
                builder: (context, _) {
                  final w = _w.value, h = _h.value, p = h.clamp(0.0, 1.0);
                  final size = Size(
                    lerpDouble(islandClosedSize.width, islandOpenSize.width, w)!,
                    lerpDouble(islandClosedSize.height, islandOpenSize.height, h)!,
                  );
                  final radius = lerpDouble(islandClosedSize.height / 2, _islandRadius, p)!;
                  // Docked: flat against the top edge, round below, like a notch.
                  final corners = docked
                      ? BorderRadius.vertical(bottom: Radius.circular(radius))
                      : BorderRadius.circular(radius);
                  // The row blurs away at once; the deck comes into focus over the second half.
                  final closed = (1 - p * 3).clamp(0.0, 1.0);
                  final open = ((p - 0.35) / 0.65).clamp(0.0, 1.0);
                  return MouseRegion(
                    // A short wait, so a pointer only passing over it on the way elsewhere leaves it closed. Set to open
                    // on a click, resting on it does nothing.
                    onEnter: (_) {
                      if (prefs.islandOpen == IslandOpen.hover) _later(const Duration(milliseconds: 160), true);
                    },
                    onExit: (_) => _later(const Duration(milliseconds: 420), false),
                    child: SizedBox.fromSize(
                      size: size,
                      child: DecoratedBox(
                        decoration: ShapeDecoration(
                          color: panel,
                          shape: RoundedRectangleBorder(borderRadius: corners),
                          // Lifted while open; none closed, where the window keeps only the pill.
                          shadows: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3 * p),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: corners,
                          child: _Ink(
                            text: Colors.white,
                            muted: Colors.white.withValues(alpha: 0.68),
                            child: Stack(
                              children: [
                                if (open > 0)
                                  _Morph(
                                    amount: open,
                                    blur: 10,
                                    scale: 0.9,
                                    child: OverflowBox(
                                      alignment: Alignment.topCenter,
                                      minWidth: islandOpenSize.width,
                                      maxWidth: islandOpenSize.width,
                                      minHeight: islandOpenSize.height,
                                      maxHeight: islandOpenSize.height,
                                      child: _Deck(c: c, now: now, island: true, lyricColor: lyric),
                                    ),
                                  ),
                                if (closed > 0)
                                  _Morph(
                                    amount: closed,
                                    blur: 6,
                                    scale: 1.06,
                                    // Docked it slides along the top edge only; floating it goes anywhere.
                                    // Pressed to drag it, it stays closed: opening on the pointer resting there would
                                    // swap the pill being dragged for the deck.
                                    child: Listener(
                                      onPointerDown: (_) => _timer?.cancel(),
                                      child: _IslandDrag(
                                        docked: docked,
                                        child: GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: () => _later(Duration.zero, true),
                                          child: SizedBox(
                                            width: size.width,
                                            height: islandClosedSize.height,
                                            child: _IslandClosed(now: now),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Dragging the closed island: docked it slides along the top edge ([_SlideAlongTop]), floating it goes anywhere.
class _IslandDrag extends StatelessWidget {
  const _IslandDrag({required this.docked, required this.child});

  final bool docked;
  final Widget child;

  @override
  Widget build(BuildContext context) => docked ? _SlideAlongTop(child: child) : DragToMoveArea(child: child);
}

/// The docked island follows the pointer across displays and stays on that monitor's top edge.
class _SlideAlongTop extends StatefulWidget {
  const _SlideAlongTop({required this.child});

  final Widget child;

  @override
  State<_SlideAlongTop> createState() => _SlideAlongTopState();
}

class _SlideAlongTopState extends State<_SlideAlongTop> {
  /// Where the pointer took hold, from the window's left edge; the top edge it stays on.
  double? _grab;
  List<Rect> _monitors = const [];
  bool _moving = false;
  Offset? _pending;

  Future<void> _start(DragStartDetails _) async {
    final cursor = await screenRetriever.getCursorScreenPoint();
    final b = await windowManager.getBounds();
    if (!Host.isWindows) _monitors = (await screenRetriever.getAllDisplays()).map(_displayArea).toList();
    _grab = cursor.dx - b.left;
  }

  Future<void> _move(DragUpdateDetails _) async {
    final grab = _grab;
    if (grab == null) return;
    if (Host.isWindows) {
      await _channel.invokeMethod<void>('moveDockedIsland', grab);
      return;
    }
    final cursor = await screenRetriever.getCursorScreenPoint();
    _pending = Offset(cursor.dx - grab, nearestMonitorWorkArea(cursor, _monitors)?.top ?? 0);
    // One move at a time: the latest place wins.
    if (_moving) return;
    _moving = true;
    try {
      for (var to = _pending; to != null; to = _pending) {
        _pending = null;
        await windowManager.setPosition(to);
      }
    } finally {
      _moving = false;
    }
  }

  void _end(DragEndDetails _) {
    _grab = null;
    if (!Host.isWindows) _snapDocked();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onPanStart: _start,
    onPanUpdate: _move,
    onPanEnd: _end,
    onPanCancel: () => _grab = null,
    child: widget.child,
  );
}

/// Content coming into focus as [amount] goes to 1: faded, blurred by up to [blur] and scaled from [scale] before.
class _Morph extends StatelessWidget {
  const _Morph({required this.amount, required this.blur, required this.scale, required this.child});

  final double amount;
  final double blur;
  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final sigma = (1 - amount) * blur;
    Widget out = Transform.scale(scale: lerpDouble(scale, 1, amount)!, alignment: Alignment.topCenter, child: child);
    // Only while it moves: a blur filter on a settled view would cost every frame for nothing.
    if (sigma > 0.1) {
      out = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: out,
      );
    }
    return Opacity(opacity: amount, child: out);
  }
}

/// The closed island's bars, following the music (the player's audio levels, which keep coming with the window
/// behind others); still and low while paused.
class _IslandBars extends StatelessWidget {
  const _IslandBars({required this.playing});

  final bool playing;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.accent;
    final c = PlayerScope.read(context);
    final music =
        LayoutPrefs.instance.islandBars == IslandBars.music &&
        Features.audioVisualizer &&
        visualizerBlockedBy(c, reduceMotion: MediaQuery.disableAnimationsOf(context)) == null &&
        visualizerHiddenBy(c) == null;
    switch (LayoutPrefs.instance.islandBars) {
      case IslandBars.off:
        return const SizedBox.shrink();
      case IslandBars.animated:
      case IslandBars.music when !music:
        // Where the levels can't be had (bit-perfect, casting, Lightweight): bars that move by themselves.
        return EqualizerIcon(playing: playing, size: 16, color: color);
      case IslandBars.music:
        break;
    }
    return AudioReactiveView(
      enabled: playing,
      maxFps: 30,
      // Its own levels, whatever the visualizer switch says; the island has no music video under it.
      own: true,
      followsVideo: false,
      builder: (context, levels) => RepaintBoundary(
        child: CustomPaint(size: const Size(22, 16), painter: _BarsPainter(levels, color, playing)),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.levels, this.color, this.playing) : super(repaint: levels);

  final VisualizerLevels levels;
  final Color color;
  final bool playing;

  /// Bass to treble, as a fraction of the bands.
  static const _picks = [0.06, 0.2, 0.38, 0.58, 0.8];

  @override
  void paint(Canvas canvas, Size size) {
    final values = levels.value;
    final paint = Paint()..color = color;
    final bar = size.width / (_picks.length * 2 - 1);
    for (var i = 0; i < _picks.length; i++) {
      final level = playing && values.isNotEmpty ? values[(values.length * _picks[i]).floor()].clamp(0.0, 1.0) : 0.0;
      final height = size.height * (0.18 + 0.82 * math.pow(level, 0.7));
      final x = i * bar * 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, size.height - height, bar, height), Radius.circular(bar / 2)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.color != color || old.playing != playing || old.levels != levels;
}

class _IslandClosed extends StatelessWidget {
  const _IslandClosed({required this.now});

  final _Now now;

  @override
  Widget build(BuildContext context) {
    final track = now.track;
    final style = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(fontWeight: FontWeight.w600, color: _Ink.of(context).text);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 16, 0),
      child: Row(
        children: [
          Artwork(track: track, size: 28, circle: true),
          const SizedBox(width: 10),
          // The line being sung when the song has timed lyrics (and they're on), the title otherwise.
          Expanded(
            child: _LyricLine(
              track: track,
              builder: (context, lyric) => AnimatedSwitcher(
                duration: LayoutPrefs.dur(const Duration(milliseconds: 220)),
                layoutBuilder: (current, previous) =>
                    Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
                child: switch (lyric) {
                  (line: null, said: _, next: _) => MarqueeText(
                    key: const ValueKey(''),
                    track?.title ?? tr.nothingPlaying,
                    style: style,
                  ),
                  (line: final String line, said: null, next: _) => Text(
                    line,
                    key: ValueKey(line),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  ),
                  // Two small lines in the one row: the words, and how they're said.
                  (line: final String line, said: final String said, next: _) => Column(
                    key: ValueKey((line, said)),
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: style?.copyWith(fontSize: 13, height: 1.15),
                      ),
                      Text(
                        said,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: style?.copyWith(
                          fontSize: 11,
                          height: 1.15,
                          fontWeight: FontWeight.w500,
                          color: _Ink.of(context).muted,
                        ),
                      ),
                    ],
                  ),
                },
              ),
            ),
          ),
          const SizedBox(width: 10),
          if (now.buffering)
            SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))
          else if (now.playing)
            const _IslandBars(playing: true)
          else
            Icon(Icons.pause_rounded, size: 18, color: _Ink.of(context).muted),
        ],
      ),
    );
  }
}

/// What the mini player shows of the lyrics: the line being sung, how it's said when it's in another script
/// ("kyō mo mata hajimaru", with the lyrics page's Pronunciation on), and the next line.
typedef MiniLyric = ({String? line, String? said, String? next});

const MiniLyric _noLyric = (line: null, said: null, next: null);

/// The line being sung of [track]'s timed lyrics, its pronunciation and the line after it, while the mini player's
/// lyrics are on. All null when there's nothing to show: lyrics off, none found or not timed. Only a change of line
/// rebuilds [builder].
class _LyricLine extends StatefulWidget {
  const _LyricLine({required this.track, required this.builder});

  final Track? track;
  final Widget Function(BuildContext context, MiniLyric now) builder;

  @override
  State<_LyricLine> createState() => _LyricLineState();
}

class _LyricLineState extends State<_LyricLine> {
  StreamSubscription<Duration>? _ticks;
  MiniLyric _now = _noLyric;
  bool? _loadedOn;
  String? _loadedId;
  Lyrics? _lyrics;

  /// Each line's pronunciation; null until fetched, or with Pronunciation off.
  List<LineExtras>? _extras;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    LayoutPrefs.instance.addListener(_load);
    LyricsTranslation.romanize.addListener(_loadExtras);
    _load();
  }

  @override
  void didUpdateWidget(_LyricLine old) {
    super.didUpdateWidget(old);
    if (old.track?.id != widget.track?.id) _load();
  }

  @override
  void dispose() {
    LayoutPrefs.instance.removeListener(_load);
    LyricsTranslation.romanize.removeListener(_loadExtras);
    _ticks?.cancel();
    super.dispose();
  }

  void _load() {
    final t = widget.track, on = LayoutPrefs.instance.miniLyrics;
    if (_loadedOn == on && _loadedId == t?.id) return;
    _loadedOn = on;
    _loadedId = t?.id;
    _ticks?.cancel();
    _ticks = null;
    _lyrics = null;
    _extras = null;
    _show(_noLyric);
    if (t == null || !on) return;
    if (LyricsService.loaded(t) case final known?) return _follow(t, known);
    LyricsService.forTrack(t).then(
      (l) {
        if (mounted && _loadedId == t.id && LayoutPrefs.instance.miniLyrics) _follow(t, l);
      },
      // Offline or no source answered: the mini player simply shows no line.
      onError: (Object e) => debugPrint('Mini player lyrics: $e'),
    );
  }

  void _follow(Track t, Lyrics lyrics) {
    if (!lyrics.synced) return;
    _lyrics = lyrics;
    final shift = LyricsTiming.of(t);
    _ticks = PlayerScope.read(context).smoothPosition().listen((p) {
      _last = p - shift.value;
      _show(miniLyricAt(lyrics, _last, extras: _extras));
    });
    _loadExtras();
  }

  /// The same one request per song the lyrics page makes (and caches).
  Future<void> _loadExtras() async {
    final l = _lyrics;
    if (l == null) return;
    if (!LyricsTranslation.romanize.value) {
      _extras = null;
      return _show(miniLyricAt(l, _last));
    }
    final lines = [for (final line in l.lines) line.text];
    if (_extras != null || !lines.any(LyricsTranslation.hasNonLatin)) return;
    try {
      final extras = await LyricsTranslation.of(lines);
      if (!mounted || !identical(_lyrics, l) || !LyricsTranslation.romanize.value) return;
      _extras = extras;
      _show(miniLyricAt(l, _last, extras: extras));
    } catch (e) {
      // Unreachable: the lines show without it.
      debugPrint('Mini player pronunciation: $e');
    }
  }

  void _show(MiniLyric now) {
    if (now == _now) return;
    if (mounted) setState(() => _now = now);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _now);
}

/// The line of [lyrics] sung at [position], how it's said (from [extras], one per line, for a line in another
/// script) and the next line; the line is null between lines (an empty or ♪ line, before the first, after one's
/// end). A little early, as the lyrics page lights it.
@visibleForTesting
MiniLyric miniLyricAt(Lyrics lyrics, Duration position, {List<LineExtras>? extras}) {
  final at = position + const Duration(milliseconds: 150);
  String? words(int i) {
    if (i < 0 || i >= lyrics.lines.length) return null;
    final text = lyrics.lines[i].text.trim();
    return text.isEmpty || RegExp(r'^[♪♫\s]+$').hasMatch(text) ? null : text;
  }

  final i = lyrics.lineAt(at);
  final end = i >= 0 ? lyrics.lines[i].end : null;
  final line = end != null && at >= end ? null : words(i);
  final said = line != null && extras != null && i < extras.length && LyricsTranslation.hasNonLatin(line)
      ? extras[i].romanized?.trim()
      : null;
  return (line: line, said: said == null || said.isEmpty ? null : said, next: words(i + 1));
}

/// The sung line, fading from one to the next, with its pronunciation and the next line underneath while there's
/// room (cut off below, never overflowing).
class _Lyric extends StatelessWidget {
  const _Lyric({required this.now, required this.style, required this.saidStyle, this.nextStyle});

  final MiniLyric now;
  final TextStyle? style;
  final TextStyle? saidStyle;
  final TextStyle? nextStyle;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: LayoutPrefs.dur(const Duration(milliseconds: 220)),
    layoutBuilder: (current, previous) => Stack(alignment: Alignment.topLeft, children: [...previous, ?current]),
    child: now.line == null
        ? const SizedBox.shrink()
        : SingleChildScrollView(
            key: ValueKey((now.line, now.said)),
            physics: const NeverScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(now.line!, maxLines: now.said == null ? 2 : 1, overflow: TextOverflow.ellipsis, style: style),
                if (now.said case final said?)
                  Text(said, maxLines: 1, overflow: TextOverflow.ellipsis, style: saidStyle),
                if (now.next case final next? when nextStyle != null)
                  Text(next, maxLines: 1, overflow: TextOverflow.ellipsis, style: nextStyle),
              ],
            ),
          ),
  );
}

/// Previous, play / pause and next: an M3 filled play button between two standard icon buttons.
class _Transport extends StatelessWidget {
  const _Transport({required this.c, required this.now, required this.size});

  final PlayerController c;
  final _Now now;
  final double size;

  @override
  Widget build(BuildContext context) => PlayerSelect<({bool hasQueue, bool hasNext})>(
    select: (c) => (hasQueue: c.hasQueue, hasNext: c.hasNext),
    builder: (context, q, _) => Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: tr.previous,
          color: _Ink.of(context).text,
          iconSize: 28,
          onPressed: q.hasQueue ? c.previous : null,
          icon: const Icon(Icons.skip_previous_rounded),
        ),
        const SizedBox(width: 12),
        PlayButton(
          size: size,
          playing: now.playing,
          loading: now.buffering,
          onPressed: now.canPlay ? c.togglePlay : null,
        ),
        const SizedBox(width: 12),
        IconButton(
          tooltip: tr.next,
          color: _Ink.of(context).text,
          iconSize: 28,
          onPressed: q.hasNext ? c.next : null,
          icon: const Icon(Icons.skip_next_rounded),
        ),
      ],
    ),
  );
}

/// A thin M3 seek bar with the time on either side; it follows the position every frame and seeks on release.
class _MiniSeek extends StatefulWidget {
  const _MiniSeek({required this.c, required this.enabled});

  final PlayerController c;
  final bool enabled;

  @override
  State<_MiniSeek> createState() => _MiniSeekState();
}

class _MiniSeekState extends State<_MiniSeek> {
  /// Where the thumb is held while dragging, in milliseconds.
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: _Ink.of(context).muted, fontFeatures: const [FontFeature.tabularFigures()]);
    return MiniProgress(
      builder: (context, snap) {
        final total = (widget.c.duration?.inMilliseconds ?? 0).toDouble();
        final pos = (_drag ?? snap.data?.inMilliseconds.toDouble() ?? 0).clamp(0.0, total);
        // The wave by default (the plain track in Lightweight); it rolls while the song plays, also with another
        // window focused (the mini player stays in sight on top), and flattens on a pause.
        final wavy = !LayoutPrefs.lightweight;
        Widget slider(MotionClock? clock) => SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            trackShape: wavy ? WavySeekTrack(motion: clock) : null,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            activeTrackColor: AppColors.accent,
            inactiveTrackColor: _Ink.of(context).text.withValues(alpha: 0.18),
            thumbColor: AppColors.accent,
          ),
          child: SizedBox(
            height: 24,
            child: Slider(
              value: total == 0 ? 0 : pos,
              max: total == 0 ? 1 : total,
              onChanged: widget.enabled && total > 0 ? (v) => setState(() => _drag = v) : null,
              onChangeEnd: (v) {
                widget.c.seek(Duration(milliseconds: v.round()));
                setState(() => _drag = null);
              },
            ),
          ),
        );
        return Row(
          children: [
            Text(formatDuration(Duration(milliseconds: pos.round())), style: small),
            // Room between the times and the bar: the wave runs to its very ends.
            const SizedBox(width: 10),
            Expanded(
              child: wavy
                  ? PlayingMotion(
                      restWithVideo: false,
                      moveUnfocused: true,
                      builder: (context, clock) => RepaintBoundary(
                        child: RepaintOn(listenable: clock, child: slider(clock)),
                      ),
                    )
                  : slider(null),
            ),
            const SizedBox(width: 10),
            Text(formatDuration(widget.c.duration), style: small),
          ],
        );
      },
    );
  }
}

class _SmallIcon extends StatelessWidget {
  const _SmallIcon({required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    color: _Ink.of(context).text,
    iconSize: 18,
    visualDensity: VisualDensity.compact,
    onPressed: onPressed,
    icon: Icon(icon),
  );
}

/// The text and icon colours of the shape around them: the theme's on the mini window, light on the dark island.
class _Ink extends InheritedWidget {
  const _Ink({required this.text, required this.muted, required super.child});

  final Color text;
  final Color muted;

  static ({Color text, Color muted}) of(BuildContext context) {
    final ink = context.dependOnInheritedWidgetOfExactType<_Ink>();
    return ink == null
        ? (text: AppColors.textPrimary, muted: AppColors.textSecondary)
        : (text: ink.text, muted: ink.muted);
  }

  @override
  bool updateShouldNotify(_Ink old) => text != old.text || muted != old.muted;
}

import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../../services/layout_prefs.dart';
import '../../services/player_controller.dart';
import '../widgets/controls.dart';
import '../theme.dart';
import '../widgets/marquee_text.dart';
import '../ytmusic_edit.dart';
import 'more_sheet.dart';
import 'player_common.dart';
import '../../services/language.dart';

/// Floating bar above the bottom tabs on phones, tinted with the cover colour.
/// Cover, title, like, play / pause and next; swipe sideways to change song,
/// down to close; long-press for the rest (queue, lyrics, sleep timer…).
class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key, required this.onOpen});

  final VoidCallback onOpen;

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

/// Swiping the song sideways changes it: left for the next one, right for the previous one.
mixin _SongSwipe<T extends StatefulWidget> on State<T> {
  /// How far the song is being dragged sideways.
  final _drag = ValueNotifier<double>(0);

  @override
  void dispose() {
    _drag.dispose();
    super.dispose();
  }

  void _endDrag(PlayerController c, DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    final dx = _drag.value;
    _drag.value = 0;
    final threshold = LayoutPrefs.instance.swipeDistance;
    final velocity = 600 * threshold / 72;
    if (dx < -threshold || v < -velocity) {
      c.next();
    } else if (dx > threshold || v > velocity) {
      c.previous();
    }
  }

  /// [child] following the finger, fading as it goes.
  Widget _swipeable(PlayerController c, Widget child) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onHorizontalDragUpdate: (d) => _drag.value += d.delta.dx,
    onHorizontalDragEnd: (d) => _endDrag(c, d),
    onHorizontalDragCancel: () => _drag.value = 0,
    child: ValueListenableBuilder<double>(
      valueListenable: _drag,
      builder: (context, dx, child) => Transform.translate(
        offset: Offset(dx, 0),
        child: Opacity(opacity: (1 - dx.abs() / 240).clamp(0.3, 1), child: child),
      ),
      child: child,
    ),
  );
}

/// Connects either mini-player skin to the phone shell's interactive expansion.
class MiniPlayerExpansion extends InheritedWidget {
  const MiniPlayerExpansion({
    super.key,
    required this.anchorKey,
    required this.update,
    required this.finish,
    required super.child,
  });

  final GlobalKey anchorKey;

  final void Function(Rect origin, double distance) update;
  final void Function(double velocity, {required bool cancelled}) finish;

  static MiniPlayerExpansion? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType();

  @override
  bool updateShouldNotify(MiniPlayerExpansion oldWidget) => update != oldWidget.update || finish != oldWidget.finish;
}

class _MiniPlayerDrag extends StatefulWidget {
  const _MiniPlayerDrag({required this.onOpen, required this.onDismiss, required this.child});

  final VoidCallback onOpen;
  final VoidCallback onDismiss;
  final Widget child;

  @override
  State<_MiniPlayerDrag> createState() => _MiniPlayerDragState();
}

class _MiniPlayerDragState extends State<_MiniPlayerDrag> {
  final _offset = ValueNotifier<double>(0);
  double _distance = 0;
  Rect? _origin;
  bool _expanding = false;

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  void _finish(MiniPlayerExpansion expansion, double velocity, {bool cancelled = false}) {
    final origin = _origin;
    if (_expanding) {
      expansion.finish(velocity, cancelled: cancelled);
    } else if (!cancelled && origin != null && (_distance > origin.height * 0.4 || velocity > 650)) {
      widget.onDismiss();
    }
    _offset.value = 0;
    _origin = null;
    _expanding = false;
  }

  @override
  Widget build(BuildContext context) {
    final expansion = MiniPlayerExpansion.of(context);
    if (expansion == null) {
      return Dismissible(
        key: const ValueKey('mini-player-dismiss'),
        direction: DismissDirection.vertical,
        dismissThresholds: const {DismissDirection.up: 0.42, DismissDirection.down: 0.4},
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.down) return true;
          widget.onOpen();
          return false;
        },
        onDismissed: (_) => widget.onDismiss(),
        child: widget.child,
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      key: expansion.anchorKey,
      onVerticalDragStart: (_) {
        final box = context.findRenderObject() as RenderBox;
        _origin = box.localToGlobal(Offset.zero) & box.size;
        _distance = 0;
        _expanding = false;
      },
      onVerticalDragUpdate: (details) {
        final origin = _origin;
        if (origin == null) return;
        _distance += details.delta.dy;
        if (_distance < 0 || _expanding) {
          _expanding = true;
          _offset.value = 0;
          expansion.update(origin, (-_distance).clamp(0, double.infinity));
        } else {
          _offset.value = _distance.clamp(0, origin.height);
        }
      },
      onVerticalDragEnd: (details) => _finish(expansion, details.primaryVelocity ?? 0),
      onVerticalDragCancel: () => _finish(expansion, 0, cancelled: true),
      child: ValueListenableBuilder<double>(
        valueListenable: _offset,
        child: widget.child,
        builder: (context, down, child) => Transform.translate(offset: Offset(0, down), child: child),
      ),
    );
  }
}

class _MiniPlayerState extends State<MiniPlayer> with _SongSwipe {
  @override
  Widget build(BuildContext context) {
    final c = PlayerScope.read(context);
    // Only the song decides what the bar is; play / pause have their own listener below.
    return PlayerSelect<Track?>(
      select: (c) => c.currentTrack,
      builder: (context, track, _) {
        if (track == null) return const SizedBox.shrink();
        return _bar(context, c, track);
      },
    );
  }

  Widget _bar(BuildContext context, PlayerController c, Track track) {
    final text = Theme.of(context).textTheme;
    final capsule = LayoutPrefs.instance.miniPlayer == MiniPlayerStyle.capsule;
    return AccentBuilder(
      track: track,
      builder: (context, accent) => _MiniPlayerDrag(
        onOpen: widget.onOpen,
        onDismiss: c.closePlayer,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
          child: GlassPanel(
            color: AppColors.sink(accent, 0.75),
            borderRadius: capsule ? BorderRadius.circular(LayoutPrefs.radius(32)) : LayoutPrefs.corner(8),
            child: InkWell(
              onTap: widget.onOpen,
              onLongPress: () => showPlayerMore(context, openPlayer: widget.onOpen),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 2, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: _swipeable(
                            c,
                            TrackSwitcher(
                              trackId: track.id,
                              slide: false,
                              child: Row(
                                key: ValueKey(track.id),
                                children: [
                                  Hero(
                                    tag: 'now-playing-art',
                                    child: Artwork(
                                      track: track,
                                      size: 40,
                                      radius: capsule ? LayoutPrefs.radius(20) : 4,
                                      flower: true,
                                      scalloped: capsule,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        MarqueeText(
                                          track.title,
                                          style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                                        ),
                                        // Plain text, not links: a thumb on its way to the bar landed on the
                                        // artist and left for their page. A tap opens the player, as the rest
                                        // of the bar does; Go to artist is in its menu.
                                        Text(
                                          track.artist,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (capsule) ...[
                          _MiniPrev(c: c),
                          _MiniPlay(c: c, capsule: true),
                          _MiniNext(c: c, capsule: true),
                        ] else ...[
                          LikeButton(track: track, size: 24, color: AppColors.textPrimary),
                          _MiniPlay(c: c),
                          _MiniNext(c: c),
                        ],
                      ],
                    ),
                  ),
                  MiniProgress(
                    builder: (context, snap) {
                      final total = c.duration?.inMilliseconds ?? 0;
                      final pos = snap.data?.inMilliseconds ?? 0;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: LinearProgressIndicator(
                          value: total == 0 ? 0 : (pos / total).clamp(0, 1),
                          minHeight: 2,
                          color: AppColors.textPrimary,
                          backgroundColor: AppColors.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The mini player inside the Liquid glass tab bar, which draws the glass around it: cover, title and artist,
/// play / pause and next. As [compact] goes from 0 to 1 (the bar shrinking to one row) next folds away.
/// Tap to open the player, swipe sideways to change song, down to close; long-press for the rest.
class GlassMiniPlayer extends StatefulWidget {
  const GlassMiniPlayer({super.key, required this.track, required this.onOpen, this.compact = 0});

  final Track track;
  final VoidCallback onOpen;
  final double compact;

  @override
  State<GlassMiniPlayer> createState() => _GlassMiniPlayerState();
}

class _GlassMiniPlayerState extends State<GlassMiniPlayer> with _SongSwipe {
  @override
  Widget build(BuildContext context) {
    final c = PlayerScope.read(context);
    final text = Theme.of(context).textTheme;
    final track = widget.track;
    final compact = widget.compact;
    final foreground = switch (LayoutPrefs.instance.miniGlassTint) {
      GlassTint.theme => AppColors.of(context).textPrimary,
      GlassTint.light => Colors.black87,
      GlassTint.black => Colors.white,
    };
    return _MiniPlayerDrag(
      onOpen: widget.onOpen,
      onDismiss: c.closePlayer,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onOpen,
          onLongPress: () => showPlayerMore(context, openPlayer: widget.onOpen),
          // Two lines of text in a bar of fixed height: large text grows them only so far.
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 4, 0),
              child: Row(
                children: [
                  Expanded(
                    child: _swipeable(
                      c,
                      TrackSwitcher(
                        trackId: track.id,
                        slide: false,
                        child: Row(
                          key: ValueKey(track.id),
                          children: [
                            Hero(
                              tag: 'now-playing-art',
                              child: Artwork(
                                track: track,
                                size: 42,
                                radius: LayoutPrefs.radius(21),
                                flower: true,
                                scalloped: true,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  MarqueeText(
                                    track.title,
                                    style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: foreground),
                                  ),
                                  // Plain text, as in the other mini player: a tap opens the player.
                                  Text(
                                    track.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: text.bodySmall?.copyWith(color: foreground.withValues(alpha: 0.72)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  _MiniPlay(c: c, foreground: foreground),
                  if (compact < 1)
                    ClipRect(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        widthFactor: 1 - compact,
                        child: Opacity(
                          opacity: (1 - compact * 2).clamp(0.0, 1.0),
                          child: _MiniNext(c: c, foreground: foreground),
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
  }
}

/// Play / pause (or the spinner while buffering): the only part of the bar that follows each play state change.
class _MiniPlay extends StatelessWidget {
  const _MiniPlay({required this.c, this.capsule = false, this.foreground});

  final PlayerController c;
  final Color? foreground;

  /// The capsule's round, accent-filled button.
  final bool capsule;

  @override
  Widget build(BuildContext context) => PlayerSelect<({bool buffering, bool playing})>(
    select: (c) => (buffering: c.isBuffering, playing: c.showsPlaying),
    builder: (context, s, _) => SizedBox(
      width: 44,
      height: 44,
      child: s.buffering
          ? Center(
              child: SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2.2, color: foreground ?? AppColors.textPrimary),
              ),
            )
          : IconButton(
              tooltip: s.playing ? tr.pause : tr.play,
              color: capsule ? AppColors.onAccent : foreground ?? AppColors.textPrimary,
              style: capsule
                  ? IconButton.styleFrom(backgroundColor: AppColors.accent, fixedSize: const Size(40, 40))
                  : null,
              iconSize: capsule ? 24 : 30,
              padding: EdgeInsets.zero,
              onPressed: c.togglePlay,
              icon: Icon(s.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
            ),
    ),
  );
}

class _MiniPrev extends StatelessWidget {
  const _MiniPrev({required this.c});

  final PlayerController c;

  @override
  Widget build(BuildContext context) => PlayerSelect<bool>(
    select: (c) => c.hasQueue,
    builder: (context, hasQueue, _) => IconButton(
      tooltip: tr.previous,
      color: AppColors.textPrimary,
      style: IconButton.styleFrom(
        backgroundColor: AppColors.textPrimary.withValues(alpha: 0.1),
        fixedSize: const Size(36, 36),
      ),
      iconSize: 22,
      padding: EdgeInsets.zero,
      onPressed: hasQueue ? c.previous : null,
      icon: const Icon(Icons.skip_previous_rounded),
    ),
  );
}

class _MiniNext extends StatelessWidget {
  const _MiniNext({required this.c, this.capsule = false, this.foreground});

  final PlayerController c;
  final Color? foreground;
  final bool capsule;

  @override
  Widget build(BuildContext context) => PlayerSelect<bool>(
    select: (c) => c.hasNext,
    builder: (context, hasNext, _) => IconButton(
      tooltip: tr.next,
      color: foreground ?? AppColors.textPrimary,
      style: capsule
          ? IconButton.styleFrom(
              backgroundColor: AppColors.textPrimary.withValues(alpha: 0.1),
              fixedSize: const Size(36, 36),
            )
          : null,
      iconSize: capsule ? 22 : 26,
      padding: capsule ? EdgeInsets.zero : null,
      onPressed: hasNext ? c.next : null,
      icon: const Icon(Icons.skip_next_rounded),
    ),
  );
}

import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../../services/layout_prefs.dart';
import '../../services/player_controller.dart';
import '../widgets/controls.dart';
import '../widgets/marquee_text.dart';
import '../ytmusic_edit.dart';
import 'more_sheet.dart';
import 'player_common.dart';

/// Floating bar above the bottom tabs on phones, tinted with the cover colour.
/// Cover, title, like, play / pause and next; swipe sideways to change song,
/// down to close; long-press for the rest (queue, lyrics, sleep timer…).
class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key, required this.onOpen});

  final VoidCallback onOpen;

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
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
    if (dx < -72 || v < -600) {
      c.next();
    } else if (dx > 72 || v > 600) {
      c.previous();
    }
  }

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
    return AccentBuilder(
      track: track,
      builder: (context, accent) => Dismissible(
        key: const ValueKey('mini-player'),
        direction: DismissDirection.down,
        onDismissed: (_) => c.closePlayer(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
          child: GlassPanel(
            color: Color.lerp(accent, Colors.black, 0.45)!,
            borderRadius: LayoutPrefs.corner(8),
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
                          child: GestureDetector(
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
                              child: TrackSwitcher(
                                trackId: track.id,
                                slide: false,
                                child: Row(
                                  key: ValueKey(track.id),
                                  children: [
                                    Hero(
                                      tag: 'now-playing-art',
                                      child: Artwork(track: track, size: 40, radius: 4),
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
                                          MarqueeText(
                                            track.artist,
                                            style: text.bodySmall?.copyWith(color: Colors.white70),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        LikeButton(track: track, size: 24, color: Colors.white),
                        _MiniPlay(c: c),
                        _MiniNext(c: c),
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
                          color: Colors.white,
                          backgroundColor: Colors.white24,
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

/// Play / pause (or the spinner while buffering): the only part of the bar that follows each play state change.
class _MiniPlay extends StatelessWidget {
  const _MiniPlay({required this.c});

  final PlayerController c;

  @override
  Widget build(BuildContext context) => PlayerSelect<({bool buffering, bool playing})>(
    select: (c) => (buffering: c.isBuffering, playing: c.showsPlaying),
    builder: (context, s, _) => SizedBox(
      width: 44,
      height: 44,
      child: s.buffering
          ? const Center(
              child: SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
              ),
            )
          : IconButton(
              tooltip: s.playing ? 'Pause' : 'Play',
              color: Colors.white,
              iconSize: 30,
              padding: EdgeInsets.zero,
              onPressed: c.togglePlay,
              icon: Icon(s.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
            ),
    ),
  );
}

class _MiniNext extends StatelessWidget {
  const _MiniNext({required this.c});

  final PlayerController c;

  @override
  Widget build(BuildContext context) => PlayerSelect<bool>(
    select: (c) => c.hasNext,
    builder: (context, hasNext, _) => IconButton(
      tooltip: 'Next',
      color: Colors.white,
      iconSize: 26,
      onPressed: hasNext ? c.next : null,
      icon: const Icon(Icons.skip_next_rounded),
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../models/track.dart';
import '../../services/player_controller.dart';
import '../theme.dart';
import '../widgets/controls.dart';
import '../widgets/marquee_text.dart';
import 'full_screen_player.dart';
import 'player_common.dart';

/// Desktop mini player: the window shrinks to the cover with controls and
/// stays on top of other windows, like Spotify's. The full player comes back
/// at its old size and place.
final miniPlayer = ValueNotifier<bool>(false);
Rect? _boundsBeforeMini;

Future<void> setMiniPlayer(bool on) async {
  if (miniPlayer.value == on) return;
  if (on) await setFullScreenPlayer(false);
  try {
    if (on) {
      _boundsBeforeMini = await windowManager.getBounds();
      await windowManager.setMinimumSize(const Size(220, 220));
      miniPlayer.value = true;
      await windowManager.setSize(const Size(340, 340));
      await windowManager.setAlwaysOnTop(true);
    } else {
      miniPlayer.value = false;
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setMinimumSize(const Size(320, 420));
      if (_boundsBeforeMini case final b?) await windowManager.setBounds(b);
    }
  } catch (e) {
    // Tiling compositors may refuse to resize; the view switches anyway.
    debugPrint('Mini player window: $e');
    miniPlayer.value = on;
  }
}

class MiniPlayerWindow extends StatefulWidget {
  const MiniPlayerWindow({super.key});

  @override
  State<MiniPlayerWindow> createState() => _MiniPlayerWindowState();
}

class _MiniPlayerWindowState extends State<MiniPlayerWindow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = PlayerScope.read(context);
    final text = Theme.of(context).textTheme;
    // Song and play state only; the position line has its own stream.
    return PlayerSelect<({Track? track, bool playing, bool canPlay})>(
      select: (c) => (track: c.currentTrack, playing: c.showsPlaying, canPlay: c.canPlay),
      builder: (context, now, _) => _view(c, text, now.track, now.playing, now.canPlay),
    );
  }

  Widget _view(PlayerController c, TextTheme text, Track? track, bool playing, bool canPlay) {
    // No Tooltips in here: this sits outside the app's Navigator (no Overlay).
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: ColoredBox(
        color: AppColors.background,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Dragging anywhere on the cover moves the window.
            DragToMoveArea(
              child: track == null
                  ? const SizedBox.expand()
                  : TrackSwitcher(
                      trackId: track.id,
                      slide: false,
                      child: Artwork(key: ValueKey(track.id), track: track, radius: 0),
                    ),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: AnimatedOpacity(
                opacity: _hover ? 1 : 0,
                duration: const Duration(milliseconds: 160),
                child: IconButton.filled(
                  style: IconButton.styleFrom(backgroundColor: Colors.black54, foregroundColor: Colors.white),
                  onPressed: () => setMiniPlayer(false),
                  icon: const Icon(Icons.open_in_full_rounded, size: 18),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                color: const Color(0xCC000000),
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MarqueeText(
                      track?.title ?? 'Nothing playing',
                      style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    if (track != null)
                      MarqueeText(track.artist, style: text.bodySmall?.copyWith(color: AppColors.textSecondary)),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 160),
                      child: !_hover
                          ? const SizedBox(width: double.infinity, height: 6)
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(onPressed: c.previous, icon: const Icon(Icons.skip_previous_rounded)),
                                PlayButton(size: 36, playing: playing, onPressed: canPlay ? c.togglePlay : null),
                                IconButton(onPressed: c.next, icon: const Icon(Icons.skip_next_rounded)),
                              ],
                            ),
                    ),
                    MiniProgress(
                      builder: (context, snap) {
                        final total = c.duration?.inMilliseconds ?? 0;
                        final pos = snap.data?.inMilliseconds ?? 0;
                        return LinearProgressIndicator(
                          value: total == 0 ? 0 : (pos / total).clamp(0, 1),
                          minHeight: 2,
                          color: Colors.white,
                          backgroundColor: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

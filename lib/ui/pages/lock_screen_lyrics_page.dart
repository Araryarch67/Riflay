import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import '../../models/track.dart';
import '../../services/language.dart';
import '../../services/layout_prefs.dart';
import '../../services/lock_screen_lyrics.dart';
import '../player/player_glass.dart' show riflayGlass;
import '../player_scope.dart';
import '../widgets/controls.dart' show AccentBuilder, Artwork;
import '../widgets/faded_cover.dart';
import 'lyrics_page.dart' show LyricsView;

/// The lyrics over the lock screen (Android, [LockScreenLyrics]): over the song's cover, blurred, the time and date,
/// the song, its lyrics following it and the three buttons, each on liquid glass in the cover's own colours. Back
/// does nothing: the rest of the app stays behind the lock until the phone is unlocked.
class LockScreenLyricsPage extends StatefulWidget {
  const LockScreenLyricsPage({super.key});

  @override
  State<LockScreenLyricsPage> createState() => _LockScreenLyricsPageState();
}

class _LockScreenLyricsPageState extends State<LockScreenLyricsPage> {
  @override
  void initState() {
    super.initState();
    // A lock screen of its own: no navigation handle under it.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: PlayerSelect<Track?>(
      select: (c) => c.currentTrack,
      builder: (context, track, _) => AccentBuilder(
        track: track,
        builder: (context, accent) {
          final base = Theme.of(context);
          final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: Brightness.dark);
          return Theme(
            data: base.copyWith(colorScheme: scheme, iconTheme: base.iconTheme.copyWith(color: scheme.onSurface)),
            child: Material(
              color: scheme.surface,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // The cover, blurred, is the whole background: the glass bends it.
                  if (track != null) FadedCover(track: track, darken: 0.45, sharp: false),
                  _GlassLayer(
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          children: [
                            const SizedBox(height: 28),
                            const _Clock(),
                            const SizedBox(height: 20),
                            if (track != null) ...[
                              _SongCard(track: track),
                              const SizedBox(height: 8),
                              Expanded(child: LyricsView(track: track)),
                            ] else
                              const Spacer(),
                            const SizedBox(height: 12),
                            const _Buttons(),
                            const SizedBox(height: 20),
                            _Glass(
                              radius: 28,
                              child: TextButton.icon(
                                onPressed: LockScreenLyrics.unlock,
                                icon: const Icon(Icons.lock_open_rounded),
                                label: Text(tr.unlockPhone),
                                style: TextButton.styleFrom(
                                  foregroundColor: scheme.onSurface,
                                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _SongCard extends StatelessWidget {
  const _SongCard({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return _Glass(
      radius: 28,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Artwork(track: track, size: 56, radius: 16),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleMedium?.copyWith(color: scheme.onSurface, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Buttons extends StatelessWidget {
  const _Buttons();

  @override
  Widget build(BuildContext context) {
    final c = PlayerScope.read(context);
    final scheme = Theme.of(context).colorScheme;
    return PlayerSelect<bool>(
      select: (c) => c.isPlaying,
      builder: (context, playing, _) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _Glass(
            circle: true,
            child: IconButton(
              iconSize: 30,
              padding: const EdgeInsets.all(16),
              tooltip: tr.previous,
              onPressed: c.previous,
              icon: const Icon(Icons.skip_previous_rounded),
            ),
          ),
          const SizedBox(width: 20),
          // Material 3's large play button: a rounded square in the cover's colour, the glass tinted with it.
          _Glass(
            radius: 28,
            tint: scheme.primaryContainer.withValues(alpha: 0.6),
            child: SizedBox.square(
              dimension: 84,
              child: IconButton(
                onPressed: c.togglePlay,
                tooltip: playing ? tr.pause : tr.play,
                color: scheme.onPrimaryContainer,
                icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 44),
              ),
            ),
          ),
          const SizedBox(width: 20),
          _Glass(
            circle: true,
            child: IconButton(
              iconSize: 30,
              padding: const EdgeInsets.all(16),
              tooltip: tr.next,
              onPressed: c.next,
              icon: const Icon(Icons.skip_next_rounded),
            ),
          ),
        ],
      ),
    );
  }
}

/// The time and date, as the lock screen shows them, on a pane of glass, ticking over each minute.
class _Clock extends StatefulWidget {
  const _Clock();

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() {
    _tick = Timer(Duration(seconds: 60 - DateTime.now().second), () {
      if (!mounted) return;
      setState(() {});
      _schedule();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = MaterialLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final now = DateTime.now();
    final time = l.formatTimeOfDay(
      TimeOfDay.fromDateTime(now),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return _Glass(
      radius: 40,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 22, 32, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                time,
                style: text.displayLarge?.copyWith(
                  fontSize: 92,
                  fontWeight: FontWeight.w300,
                  color: scheme.primaryFixed,
                  height: 1,
                  shadows: [Shadow(color: scheme.primary.withValues(alpha: 0.5), blurRadius: 24)],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              l.formatFullDate(now),
              style: text.titleMedium?.copyWith(color: scheme.onSurface, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

/// One backdrop sample shared by the page's glass pieces (the renderer draws up to 16 to a layer).
class _GlassLayer extends StatelessWidget {
  const _GlassLayer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutPrefs.lightweight
      ? child
      : LiquidGlassLayer(settings: riflayGlass(brightness: Brightness.dark), useBackdropGroup: true, child: child);
}

/// Liquid glass over the blurred cover: the cover bends and catches light at its rim. Lightweight mode draws a plain
/// see-through panel instead.
class _Glass extends StatelessWidget {
  const _Glass({required this.child, this.radius = 24, this.circle = false, this.tint = const Color(0x40000000)});

  final Widget child;
  final double radius;
  final bool circle;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final body = Material(type: MaterialType.transparency, child: child);
    if (LayoutPrefs.lightweight) {
      return DecoratedBox(
        decoration: ShapeDecoration(
          color: Color.alphaBlend(tint, Colors.black.withValues(alpha: 0.3)),
          shape: circle ? const CircleBorder() : RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        ),
        child: body,
      );
    }
    return LiquidGlass.auto(
      appearance: LiquidGlassAppearance.ios27Regular(brightness: Brightness.dark, tint: tint),
      settings: riflayGlass(brightness: Brightness.dark),
      useBackdropGroup: true,
      shape: circle ? const LiquidOval() : LiquidRoundedSuperellipse(borderRadius: radius),
      child: body,
    );
  }
}

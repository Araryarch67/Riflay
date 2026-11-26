import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/track.dart';
import '../../services/language.dart';
import '../../services/layout_prefs.dart' show PlayButtonShape, ProgressBarShape;
import '../../services/lock_screen_lyrics.dart';
import '../../services/lyrics.dart';
import '../player_scope.dart';
import '../widgets/controls.dart' show AccentBuilder, Artwork, PlayButton, SeekBar;
import '../widgets/faded_cover.dart';
import 'lyrics_page.dart' show LyricsInset, LyricsView;

/// The lyrics over the lock screen (Android, [LockScreenLyrics]): the song's cover, blurred, and over it only type —
/// the time, the song, its lyrics following it — and three quiet buttons, in the cover's own colours. Back does
/// nothing: the rest of the app stays behind the lock until the phone is unlocked.
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
            data: base.copyWith(
              colorScheme: scheme,
              iconTheme: base.iconTheme.copyWith(color: scheme.onSurface),
            ),
            child: Material(
              color: scheme.surface,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (track != null) FadedCover(track: track, darken: 0.55, sharp: false),
                  // A slow fall into the dark at the foot, where the buttons sit.
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x00000000), Color(0x00000000), Color(0xB3000000)],
                        stops: [0, 0.55, 1],
                      ),
                    ),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Column(
                        children: [
                          const SizedBox(height: 28),
                          Expanded(child: _Body(track: track)),
                          const SizedBox(height: 12),
                          // The player's wavy bar, always: the song moving along under the words.
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: SeekBar(phonePlayer: true, shape: ProgressBarShape.wavy),
                          ),
                          const SizedBox(height: 8),
                          const _Buttons(),
                          const SizedBox(height: 20),
                          TextButton.icon(
                            onPressed: LockScreenLyrics.unlock,
                            icon: const Icon(Icons.lock_open_rounded, size: 16),
                            label: Text(tr.unlockPhone.toUpperCase()),
                            style: TextButton.styleFrom(
                              foregroundColor: scheme.onSurface.withValues(alpha: 0.7),
                              textStyle: base.textTheme.labelMedium?.copyWith(letterSpacing: 2.4),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
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

/// The clock and the song, then the lyrics once there are some. Without lyrics the clock is the lock screen's big
/// one, hours over minutes; when they come it settles into one line and the lyrics take the room.
class _Body extends StatefulWidget {
  const _Body({required this.track});

  final Track? track;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  bool _lyrics = false;
  String? _for;

  @override
  void initState() {
    super.initState();
    _look();
  }

  @override
  void didUpdateWidget(_Body old) {
    super.didUpdateWidget(old);
    if (old.track?.id != widget.track?.id) _look();
  }

  /// The same look the lyrics view makes (shared, so asked once): whether this song has words to show.
  void _look() {
    final t = widget.track;
    _for = t?.id;
    _lyrics = false;
    if (t == null) return;
    LyricsService.forTrack(t).then((l) {
      if (mounted && _for == t.id) setState(() => _lyrics = !l.isEmpty && !l.instrumental);
    }, onError: (Object _) {});
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SizeTransition(sizeFactor: animation, alignment: Alignment.topCenter, child: child),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _Clock(key: ValueKey(_lyrics), compact: _lyrics),
          ),
        ),
        if (t != null && _lyrics) ...[
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _Song(track: t),
          ),
          const SizedBox(height: 4),
          // Edge to edge of the page's margin: the sung line's highlight sits on it, its words in line with the clock.
          Expanded(
            child: LyricsInset(pad: 0, child: LyricsView(track: t)),
          ),
        ] else ...[
          const Spacer(),
          if (t != null) _Song(track: t, centered: true),
        ],
      ],
    );
  }
}

/// The song as a caption: a small cover, the title, the artist under it.
class _Song extends StatelessWidget {
  const _Song({required this.track, this.centered = false});

  final Track track;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final words = Column(
      crossAxisAlignment: centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.titleMedium?.copyWith(color: scheme.onSurface, fontWeight: FontWeight.w600),
        ),
        Text(
          track.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.bodyMedium?.copyWith(color: scheme.onSurface.withValues(alpha: 0.6)),
        ),
      ],
    );
    if (centered) return words;
    return Row(
      children: [
        Artwork(track: track, size: 40, radius: 10),
        const SizedBox(width: 14),
        Expanded(child: words),
      ],
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
          IconButton(
            iconSize: 34,
            color: scheme.onSurface,
            tooltip: tr.previous,
            onPressed: c.previous,
            icon: const Icon(Icons.skip_previous_rounded),
          ),
          const SizedBox(width: 32),
          // The app's flower play button, turning slowly while the song plays, in the cover's colour.
          PlayButton(
            playing: playing,
            onPressed: c.togglePlay,
            size: 84,
            color: scheme.primaryFixed,
            iconColor: scheme.onPrimaryFixed,
            shape: PlayButtonShape.flower,
          ),
          const SizedBox(width: 32),
          IconButton(
            iconSize: 34,
            color: scheme.onSurface,
            tooltip: tr.next,
            onPressed: c.next,
            icon: const Icon(Icons.skip_next_rounded),
          ),
        ],
      ),
    );
  }
}

/// The time, as a phone's lock screen draws it: big and bold, hours over minutes in two of the cover's tones, the
/// date spaced out over them; [compact], one line with the date beside it. Ticks over each minute.
class _Clock extends StatefulWidget {
  const _Clock({super.key, this.compact = false});

  final bool compact;

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
    final h24 = MediaQuery.alwaysUse24HourFormatOf(context);
    final hours = (h24 ? now.hour : (now.hour % 12 == 0 ? 12 : now.hour % 12)).toString().padLeft(2, '0');
    final minutes = now.minute.toString().padLeft(2, '0');
    final date = Text(
      l.formatMediumDate(now).toUpperCase(),
      style: text.labelLarge?.copyWith(color: scheme.onSurface.withValues(alpha: 0.75), letterSpacing: 3),
    );
    // Figtree, bold: round and plain, like a phone's own lock screen clock.
    TextStyle digits(double size, Color color) => TextStyle(
      fontFamily: 'Figtree',
      fontSize: size,
      fontWeight: FontWeight.w600,
      height: 0.9,
      letterSpacing: -size * 0.02,
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    if (widget.compact) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('$hours:$minutes', style: digits(64, scheme.primaryFixed)),
          const SizedBox(width: 16),
          Padding(padding: const EdgeInsets.only(bottom: 8), child: date),
        ],
      );
    }
    return Column(
      children: [
        date,
        const SizedBox(height: 16),
        Text(hours, style: digits(156, scheme.primaryFixed)),
        Text(minutes, style: digits(156, scheme.tertiaryFixed)),
      ],
    );
  }
}

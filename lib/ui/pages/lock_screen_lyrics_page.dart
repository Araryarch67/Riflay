import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../../services/language.dart';
import '../../services/lock_screen_lyrics.dart';
import '../player_scope.dart';
import '../theme.dart';
import '../widgets/controls.dart' show AccentBuilder, Artwork;
import 'lyrics_page.dart' show LyricsView;

/// The lyrics over the lock screen (Android, [LockScreenLyrics]): the time, the song, its lyrics following it and
/// the three buttons. Back does nothing: the rest of the app stays behind the lock until the phone is unlocked.
class LockScreenLyricsPage extends StatelessWidget {
  const LockScreenLyricsPage({super.key});

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: PlayerSelect<Track?>(
      select: (c) => c.currentTrack,
      builder: (context, track, _) => AccentBuilder(
        track: track,
        builder: (context, accent) => Material(
          color: AppColors.sink(accent, 0.8),
          child: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 24),
                const _Clock(),
                const SizedBox(height: 16),
                if (track != null) ...[
                  ListTile(
                    leading: Artwork(track: track, size: 48, radius: 8),
                    title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  Expanded(child: LyricsView(track: track)),
                ] else
                  const Spacer(),
                const _Buttons(),
                TextButton.icon(
                  onPressed: LockScreenLyrics.unlock,
                  icon: const Icon(Icons.lock_open_rounded),
                  label: Text(tr.unlockPhone),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _Buttons extends StatelessWidget {
  const _Buttons();

  @override
  Widget build(BuildContext context) {
    final c = PlayerScope.read(context);
    return PlayerSelect<bool>(
      select: (c) => c.isPlaying,
      builder: (context, playing, _) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            iconSize: 36,
            tooltip: tr.previous,
            onPressed: c.previous,
            icon: const Icon(Icons.skip_previous_rounded),
          ),
          const SizedBox(width: 16),
          IconButton.filled(
            iconSize: 44,
            tooltip: playing ? tr.pause : tr.play,
            onPressed: c.togglePlay,
            icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
          ),
          const SizedBox(width: 16),
          IconButton(iconSize: 36, tooltip: tr.next, onPressed: c.next, icon: const Icon(Icons.skip_next_rounded)),
        ],
      ),
    );
  }
}

/// The time, as the lock screen shows it, ticking over each minute.
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
    final now = DateTime.now();
    _tick = Timer(Duration(seconds: 60 - now.second), () {
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
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.now(),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return Text(time, style: Theme.of(context).textTheme.displayLarge?.copyWith(fontWeight: FontWeight.w300));
  }
}

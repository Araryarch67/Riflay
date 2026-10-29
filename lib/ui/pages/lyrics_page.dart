import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../models/track.dart';
import '../../services/layout_prefs.dart';
import '../../services/lyrics.dart';
import '../../services/lyrics_translation.dart';
import '../../services/player_controller.dart';
import '../shell_scope.dart';
import '../theme.dart';
import '../widgets/controls.dart';
import '../widgets/marquee_text.dart';
import '../widgets/smooth_scroll.dart';

part 'lyrics/lyrics_view.dart';
part 'lyrics/lyrics_extras.dart';
part 'lyrics/synced_view.dart';
part 'lyrics/karaoke.dart';

/// Lyrics of whatever is playing, following the song line by line.
///
/// Lives in the content area on desktop and full screen on phones. The
/// background is the cover's own colour, like the now-playing view.
class LyricsPage extends StatelessWidget {
  const LyricsPage({super.key, this.fullScreen = false});

  /// Phone: pushed over everything, with its own close button and mini controls.
  final bool fullScreen;

  @override
  Widget build(BuildContext context) => PlayerSelect<Track?>(
    // The song only: play / pause, buffering and library batches leave the page alone.
    select: (c) => c.currentTrack,
    builder: (context, track, _) => _page(context, track),
  );

  Widget _page(BuildContext context, Track? track) {
    final text = Theme.of(context).textTheme;
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    return AccentBuilder(
      track: track,
      builder: (context, accent) => Material(
        color: track == null ? AppColors.panel : Color.lerp(accent, Colors.black, 0.25),
        child: SafeArea(
          bottom: fullScreen,
          top: fullScreen || ShellScope.of(context).compact,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                child: Row(
                  children: [
                    if (ShellScope.of(context).history != null && !fullScreen)
                      const SizedBox(width: 8)
                    else if (canPop)
                      IconButton(
                        tooltip: fullScreen ? 'Close' : 'Back',
                        color: Colors.white,
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(fullScreen ? Icons.keyboard_arrow_down_rounded : Icons.arrow_back_rounded),
                      )
                    else
                      const SizedBox(width: 8),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Lyrics', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                          if (track != null)
                            MarqueeText(
                              '${track.title} · ${track.artist}',
                              style: text.bodySmall?.copyWith(color: Colors.white70),
                            ),
                        ],
                      ),
                    ),
                    if (track != null) LyricsExtrasButtons(key: ValueKey(track.id), track: track),
                  ],
                ),
              ),
              Expanded(
                child: track == null ? const _Message('Play a song to see its lyrics here.') : LyricsView(track: track),
              ),
              if (fullScreen && track != null) ...[
                const Padding(padding: EdgeInsets.symmetric(horizontal: 24), child: SeekBar()),
                const TransportControls(large: true),
                const SizedBox(height: 16),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Phone layout? Lyrics also work without the app shell around them (tests).
bool _isCompact(BuildContext context) => context.dependOnInheritedWidgetOfExactType<ShellScope>()?.compact ?? false;

TextStyle? _lineStyle(BuildContext context) {
  final compact = _isCompact(context);
  final base = compact ? Theme.of(context).textTheme.headlineSmall : Theme.of(context).textTheme.headlineMedium;
  final scale = LayoutPrefs.instance.lyricsSize.scale;
  return base?.copyWith(
    fontSize: scale == 1 || base.fontSize == null ? null : base.fontSize! * scale,
    fontWeight: FontWeight.w800,
    height: 1.25,
    letterSpacing: -0.3,
  );
}

bool get _centred => LayoutPrefs.instance.lyricsAlign == LyricsAlign.centre;
TextAlign get _textAlign => _centred ? TextAlign.center : TextAlign.start;

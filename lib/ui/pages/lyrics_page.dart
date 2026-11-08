import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../models/track.dart';
import '../../platform/features.dart';
import '../../services/language.dart';
import '../../services/layout_prefs.dart';
import '../../services/lyrics.dart';
import '../../services/lyrics_translation.dart';
import '../../services/player_controller.dart';
import '../../services/ui_beat.dart';
import '../player/more_sheet.dart' show showPlayerMore;
import '../player/player_parts.dart';
import '../shell_scope.dart';
import '../theme.dart';
import '../debug_switches.dart';
import '../widgets/controls.dart';
import '../widgets/faded_cover.dart';
import '../widgets/marquee_text.dart';
import '../widgets/playing_motion.dart';
import '../widgets/smooth_scroll.dart';
import 'wrap_page.dart' show showLyricCard;

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

  Widget _page(BuildContext context, Track? track) => ListenableBuilder(
    // The layout follows Settings at once.
    listenable: LayoutPrefs.instance,
    builder: (context, _) => _layout(context, track),
  );

  Widget _layout(BuildContext context, Track? track) {
    final text = Theme.of(context).textTheme;
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    final layout = track != null ? LayoutPrefs.instance.lyricsLayout : LyricsLayout.classic;
    // Cover: Background is the page here too, all soft, so the lyrics stay easy to read.
    final coverPage = fullScreen && track != null && LayoutPrefs.instance.playerCover == PlayerCover.background;
    return AccentBuilder(
      track: track,
      builder: (context, accent) => _behind(
        coverPage ? track : null,
        Material(
          color: coverPage ? Colors.transparent : (track == null ? AppColors.panel : AppColors.sink(accent, 0.75)),
          child: SafeArea(
            bottom: fullScreen,
            top: fullScreen || ShellScope.of(context).compact,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (layout == LyricsLayout.topHeader) ...[
                  // One row, on a phone and on desktop: the translation and the other lyrics options are in the header's
                  // ⋯ menu.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 16, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: LyricsTopHeader(track: track!, desktop: !fullScreen),
                        ),
                      ],
                    ),
                  ),
                ] else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                    child: Row(
                      children: [
                        if (ShellScope.of(context).history != null && !fullScreen)
                          const SizedBox(width: 8)
                        else if (canPop)
                          IconButton(
                            tooltip: fullScreen ? tr.close : tr.back,
                            color: AppColors.textPrimary,
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
                              Text(tr.lyrics, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                              if (track != null)
                                MarqueeText(
                                  '${track.title} · ${track.artist}',
                                  style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
                                ),
                            ],
                          ),
                        ),
                        if (track != null) LyricsExtrasButtons(key: ValueKey(track.id), track: track),
                      ],
                    ),
                  ),
                Expanded(child: track == null ? _Message(tr.playToSeeLyrics) : LyricsView(track: track)),
                if (layout == LyricsLayout.bottomCard)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                    // On desktop the card is a strip in the middle, not as wide as the window.
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: LyricsBottomCard(track: track!, desktop: !fullScreen),
                      ),
                    ),
                  )
                // Desktop: the player bar below already has the seek bar, controls and volume.
                else if (layout == LyricsLayout.topHeader) ...[
                  if (fullScreen) const Padding(padding: EdgeInsets.fromLTRB(24, 0, 24, 8), child: LyricsPlainPlayer()),
                ] else if (fullScreen && track != null) ...[
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 24), child: SeekBar(phonePlayer: true)),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 24), child: TransportControls(large: true)),
                  const SizedBox(height: 16),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _behind(Track? cover, Widget page) => cover == null
      ? page
      : Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(child: FadedCover(track: cover, darken: 0.55, sharp: false)),
            // No glow behind the lines: plain white text over the darkened cover.
            page,
          ],
        );
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

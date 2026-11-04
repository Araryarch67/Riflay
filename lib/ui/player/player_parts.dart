import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart' show LoopMode;

import '../../models/track.dart';
import '../../platform/features.dart';
import '../../services/appearance.dart';
import '../../services/layout_prefs.dart';
import '../../services/player_controller.dart';
import '../cast_picker.dart';
import '../pages/listen_together_page.dart';
import '../shell_scope.dart';
import '../shortcuts.dart';
import '../theme.dart';
import '../widgets/controls.dart';
import '../widgets/marquee_text.dart';
import '../widgets/signal_path.dart';
import '../widgets/sleep_timer_button.dart';
import '../widgets/track_row.dart';
import '../ytmusic_edit.dart';
import 'more_sheet.dart';
import 'now_playing_page.dart';
import 'full_screen_player.dart' show ExpandedPanel, expandedPlayerPanel, showExpandedPlayer;
import 'player_common.dart' show LinkText;

// The parts the player is assembled from (Settings › Look & feel › Layout › Player). The phone builds its Now
// Playing from them; the desktop's expanded player, side panel and bar take the ones that fit a wide window.
// Classic keeps its own widgets in now_playing_page.dart; these are the other choices for each part.

/// Copies a link to the song (or its name, for a file on this device) so it can be pasted anywhere.
Future<void> shareTrack(BuildContext context, Track track) async {
  final link = track.videoId == null ? null : (track.sourceUrl ?? 'https://music.youtube.com/watch?v=${track.videoId}');
  final messenger = ScaffoldMessenger.maybeOf(context);
  await Clipboard.setData(ClipboardData(text: link ?? '${track.title} - ${track.artist}'));
  messenger?.showSnackBar(SnackBar(content: Text(link != null ? 'Link copied' : 'Song name copied')));
}

/// How a [PartButton] is filled.
enum PartLook { outlined, filled, muted, plain }

/// A square or round button in the player's own style: corners follow Settings › Layout › Corners.
class PartButton extends StatelessWidget {
  const PartButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.look = PartLook.outlined,
    this.lit = false,
    this.size = 44,
    this.round = false,
    this.iconSize = 22,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final PartLook look;

  /// On: tinted with the accent (shuffle, repeat, a running sleep timer).
  final bool lit;
  final double size;

  /// A circle (with Square corners, a square) instead of a rounded square.
  final bool round;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final radius = math.min(size / 2, LayoutPrefs.radius(round ? size / 2 : 14));
    final (fill, color, side) = lit
        ? (c.accent.withValues(alpha: 0.16), c.accent, BorderSide(color: c.accent.withValues(alpha: 0.5)))
        : switch (look) {
            PartLook.outlined => (
              Colors.transparent,
              c.textPrimary,
              BorderSide(color: c.textPrimary.withValues(alpha: 0.22)),
            ),
            PartLook.filled => (c.inverse, c.onInverse, BorderSide.none),
            PartLook.muted => (c.textPrimary.withValues(alpha: 0.1), c.textPrimary, BorderSide.none),
            PartLook.plain => (Colors.transparent, c.textPrimary, BorderSide.none),
          };
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: iconSize,
      style: IconButton.styleFrom(
        backgroundColor: fill,
        foregroundColor: color,
        disabledForegroundColor: color.withValues(alpha: 0.38),
        fixedSize: Size.square(size),
        minimumSize: Size.square(size),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius), side: side),
      ),
      icon: Icon(icon),
    );
  }
}

/// The heart for [track], or nothing when it can't be liked (only signed-in YouTube Music songs can).
class PlayerLike extends StatelessWidget {
  const PlayerLike({super.key, required this.track, required this.builder});

  final Track track;
  final Widget Function(BuildContext context, bool liked, VoidCallback toggle) builder;

  @override
  Widget build(BuildContext context) {
    final account = PlayerScope.read(context).ytMusic;
    if (!track.isRemote || !account.canEdit) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: account,
      builder: (context, _) => builder(context, account.isLiked(track), () => toggleLike(context, track)),
    );
  }
}

/// More: opens the player's sheet; lit while a sleep timer or a device is on.
class PlayerMoreAction extends StatelessWidget {
  const PlayerMoreAction({
    super.key,
    this.look = PartLook.filled,
    this.icon = Icons.more_horiz_rounded,
    this.size = 44,
    this.iconSize = 22,
  });

  final PartLook look;
  final IconData icon;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final c = PlayerScope.read(context);
    return ListenableBuilder(
      listenable: Listenable.merge([c.sleep, c.cast]),
      builder: (context, _) => PartButton(
        tooltip: 'More',
        icon: icon,
        look: look,
        round: true,
        size: size,
        iconSize: iconSize,
        lit: look == PartLook.plain && (c.sleep.active || c.cast.target != null),
        onPressed: () => showPlayerMore(context, closePlayer: true),
      ),
    );
  }
}

/// The top of Now Playing when it isn't Classic: a close arrow and either "Now Playing" over the name of where
/// it plays from, or one small line.
class PlayerTopBar extends StatelessWidget {
  const PlayerTopBar({super.key, required this.from, required this.trailing, this.color});

  final String? from;

  /// The More button, when nothing else on the page has it.
  final Widget? trailing;

  /// Over a cover the text is white; null follows the theme.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final muted = color?.withValues(alpha: 0.75) ?? colors.textSecondary;
    final single = LayoutPrefs.instance.playerHeader == PlayerHeader.playingFrom;
    return Row(
      children: [
        IconButton(
          tooltip: 'Close',
          color: color ?? colors.textPrimary,
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
        ),
        Expanded(
          child: single
              ? Text(
                  'Playing from ${from ?? 'your library'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: text.labelMedium?.copyWith(color: muted, fontWeight: FontWeight.w600),
                )
              : Column(
                  children: [
                    Text('Now Playing', style: text.labelSmall?.copyWith(color: muted)),
                    Text(
                      from ?? 'Your library',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelLarge?.copyWith(fontWeight: FontWeight.w700, color: color),
                    ),
                  ],
                ),
        ),
        trailing ?? const SizedBox(width: 48),
      ],
    );
  }
}

/// The title and artist with the buttons beside them, as the Buttons by the title setting says.
class PlayerTitleBlock extends StatelessWidget {
  const PlayerTitleBlock({super.key, required this.track, required this.showBadge});

  final Track? track;
  final bool showBadge;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final style = LayoutPrefs.instance.titleActions;
    final t = track;
    final actions = t == null
        ? null
        : switch (style) {
            TitleActions.classic => LikeButton(track: t, size: 28, color: colors.textPrimary),
            TitleActions.boxed => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PartButton(
                  icon: Icons.ios_share_rounded,
                  tooltip: 'Share',
                  look: PartLook.filled,
                  onPressed: () => shareTrack(context, t),
                ),
                PlayerLike(
                  track: t,
                  builder: (context, liked, toggle) => Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: PartButton(
                      icon: liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      tooltip: liked ? 'Remove from Liked music' : 'Add to Liked music',
                      lit: liked,
                      onPressed: toggle,
                    ),
                  ),
                ),
              ],
            ),
            TitleActions.plain => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PlayerLike(
                  track: t,
                  builder: (context, liked, toggle) => PartButton(
                    icon: liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    tooltip: liked ? 'Remove from Liked music' : 'Add to Liked music',
                    look: PartLook.plain,
                    lit: false,
                    size: 40,
                    iconSize: 28,
                    onPressed: toggle,
                  ),
                ),
                const PlayerMoreAction(look: PartLook.plain, icon: Icons.more_vert_rounded, size: 40, iconSize: 28),
              ],
            ),
          };
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MarqueeText(
                t?.title ?? 'Nothing playing',
                style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
              ),
              const SizedBox(height: 2),
              LinkText(
                t?.artist ?? '',
                style: text.titleMedium?.copyWith(color: colors.textSecondary),
                onTap: t == null ? null : openArtist(context, PlayerScope.read(context), t),
              ),
              if (style == TitleActions.classic && showBadge) ...[
                const SizedBox(height: 8),
                const QualityBadge(onDark: true),
              ],
            ],
          ),
        ),
        ?actions,
      ],
    );
  }
}

typedef _Transport = ({
  bool shuffle,
  LoopMode loop,
  bool hasQueue,
  bool hasNext,
  bool canPlay,
  bool playing,
  bool loading,
});

_Transport _selectTransport(PlayerController c) => (
  shuffle: c.shuffle,
  loop: c.loopMode,
  hasQueue: c.hasQueue,
  hasNext: c.hasNext,
  canPlay: c.canPlay,
  playing: c.showsPlaying,
  loading: c.isBuffering && c.showsPlaying,
);

Widget _shuffleButton(PlayerController c, _Transport t, {double size = 22}) => ModeButton(
  tooltip: t.shuffle ? 'Disable shuffle' : 'Enable shuffle',
  active: t.shuffle,
  size: size,
  icon: Icons.shuffle_rounded,
  onPressed: t.hasQueue ? c.toggleShuffle : null,
);

Widget _repeatButton(PlayerController c, _Transport t, {double size = 22}) => ModeButton(
  tooltip: switch (t.loop) {
    LoopMode.off => 'Enable repeat',
    LoopMode.all => 'Enable repeat one',
    LoopMode.one => 'Disable repeat',
  },
  active: t.loop != LoopMode.off,
  size: size,
  icon: t.loop == LoopMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
  onPressed: t.hasQueue ? c.cycleLoopMode : null,
);

/// Previous / play / next as a wide pill or as plain icons. Shuffle and repeat flank them unless the bottom
/// row (Chips) already has them.
class PlayerControlsRow extends StatelessWidget {
  const PlayerControlsRow({super.key, this.plain = false, this.withModes = true});

  final bool plain;
  final bool withModes;

  @override
  Widget build(BuildContext context) {
    final c = PlayerScope.read(context);
    return PlayerSelect<_Transport>(
      select: _selectTransport,
      builder: (context, t, _) {
        final colors = AppColors.of(context);
        final prev = tipWith('Previous', AppAction.previous);
        final next = tipWith('Next', AppAction.next);
        final play = tipWith(t.playing ? 'Pause' : 'Play', AppAction.playPause);
        if (plain) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (withModes) _shuffleButton(c, t),
              IconButton(
                tooltip: prev,
                iconSize: 44,
                color: colors.textPrimary,
                onPressed: t.hasQueue ? c.previous : null,
                icon: const Icon(Icons.fast_rewind_rounded),
              ),
              t.loading
                  ? SizedBox.square(
                      dimension: 64,
                      child: Center(child: CircularProgressIndicator(strokeWidth: 3, color: colors.textPrimary)),
                    )
                  : IconButton(
                      tooltip: play,
                      iconSize: 64,
                      color: colors.textPrimary,
                      onPressed: t.canPlay ? c.togglePlay : null,
                      icon: Icon(t.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                    ),
              IconButton(
                tooltip: next,
                iconSize: 44,
                color: colors.textPrimary,
                onPressed: t.hasNext ? c.next : null,
                icon: const Icon(Icons.fast_forward_rounded),
              ),
              if (withModes) _repeatButton(c, t),
            ],
          );
        }
        final radius = math.min(28.0, LayoutPrefs.radius(28));
        return Row(
          children: [
            if (withModes) _shuffleButton(c, t),
            PartButton(
              icon: Icons.skip_previous_rounded,
              tooltip: prev,
              look: PartLook.muted,
              round: true,
              size: 52,
              iconSize: 28,
              onPressed: t.hasQueue ? c.previous : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Tooltip(
                message: play,
                child: Material(
                  color: t.canPlay ? colors.inverse : colors.inverse.withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: t.canPlay ? c.togglePlay : null,
                    child: SizedBox(
                      height: 56,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          t.loading
                              ? SizedBox.square(
                                  dimension: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2.5, color: colors.onInverse),
                                )
                              : Icon(
                                  t.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                  color: colors.onInverse,
                                ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              t.playing ? 'Pause' : 'Play',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(color: colors.onInverse, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            PartButton(
              icon: Icons.skip_next_rounded,
              tooltip: next,
              look: PartLook.muted,
              round: true,
              size: 52,
              iconSize: 28,
              onPressed: t.hasNext ? c.next : null,
            ),
            if (withModes) _repeatButton(c, t),
          ],
        );
      },
    );
  }
}

/// Where the song plays from, at the top of the desktop's expanded player and side panel, as Settings › Layout ›
/// Player › Top of the player says: Classic is the plain line, the others are the phone's two lines or one.
class PlayerFromLabel extends StatelessWidget {
  const PlayerFromLabel({super.key, required this.from, this.album});

  final String? from;

  /// What Classic shows when nothing says where the song plays from.
  final String? album;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: LayoutPrefs.instance,
    builder: (context, _) {
      final text = Theme.of(context).textTheme;
      final muted = AppColors.of(context).textSecondary;
      return switch (LayoutPrefs.instance.playerHeader) {
        PlayerHeader.classic => Text(
          from ?? album ?? 'Now playing',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        PlayerHeader.centered => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Now Playing', style: text.labelSmall?.copyWith(color: muted)),
            Text(
              from ?? album ?? 'Your library',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        PlayerHeader.playingFrom => Text(
          'Playing from ${from ?? album ?? 'your library'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: text.labelMedium?.copyWith(color: muted, fontWeight: FontWeight.w600),
        ),
      };
    },
  );
}

/// The buttons beside the title in the desktop's expanded player. Classic is the heart and the song's menu; the
/// others add Share in a box or make the heart a plain bigger icon. The song's menu is always there.
List<Widget> desktopTitleActions(BuildContext context, Track track) {
  final menu = TrackMenuButton(track: track, nowPlaying: true);
  return switch (LayoutPrefs.instance.titleActions) {
    TitleActions.classic => [LikeButton(track: track, size: 26), menu],
    TitleActions.boxed => [
      PartButton(
        icon: Icons.ios_share_rounded,
        tooltip: 'Share',
        look: PartLook.filled,
        size: 40,
        iconSize: 20,
        onPressed: () => shareTrack(context, track),
      ),
      PlayerLike(
        track: track,
        builder: (context, liked, toggle) => Padding(
          padding: const EdgeInsets.only(left: 8),
          child: PartButton(
            icon: liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            tooltip: liked ? 'Remove from Liked music' : 'Add to Liked music',
            lit: liked,
            size: 40,
            iconSize: 20,
            onPressed: toggle,
          ),
        ),
      ),
      const SizedBox(width: 4),
      menu,
    ],
    TitleActions.plain => [
      PlayerLike(
        track: track,
        builder: (context, liked, toggle) => PartButton(
          icon: liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          tooltip: liked ? 'Remove from Liked music' : 'Add to Liked music',
          look: PartLook.plain,
          size: 40,
          iconSize: 28,
          onPressed: toggle,
        ),
      ),
      menu,
    ],
  };
}

/// Previous / play / next for the desktop player bar when Controls is Pill or Plain, small enough for its row.
/// Shuffle and repeat flank them, like Classic's.
class DesktopControlsRow extends StatelessWidget {
  const DesktopControlsRow({super.key, required this.plain});

  final bool plain;

  @override
  Widget build(BuildContext context) {
    final c = PlayerScope.read(context);
    return PlayerSelect<_Transport>(
      select: _selectTransport,
      builder: (context, t, _) {
        final colors = AppColors.of(context);
        final prev = tipWith('Previous', AppAction.previous);
        final next = tipWith('Next', AppAction.next);
        final play = tipWith(t.playing ? 'Pause' : 'Play', AppAction.playPause);
        if (plain) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _shuffleButton(c, t, size: 20),
              const SizedBox(width: 8),
              IconButton(
                tooltip: prev,
                iconSize: 26,
                color: colors.textPrimary,
                onPressed: t.hasQueue ? c.previous : null,
                icon: const Icon(Icons.fast_rewind_rounded),
              ),
              IconButton(
                tooltip: play,
                iconSize: 32,
                color: colors.textPrimary,
                onPressed: t.canPlay ? c.togglePlay : null,
                icon: Icon(t.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
              ),
              IconButton(
                tooltip: next,
                iconSize: 26,
                color: colors.textPrimary,
                onPressed: t.hasNext ? c.next : null,
                icon: const Icon(Icons.fast_forward_rounded),
              ),
              const SizedBox(width: 8),
              _repeatButton(c, t, size: 20),
            ],
          );
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _shuffleButton(c, t, size: 20),
            const SizedBox(width: 8),
            PartButton(
              icon: Icons.skip_previous_rounded,
              tooltip: prev,
              look: PartLook.muted,
              round: true,
              size: 36,
              iconSize: 22,
              onPressed: t.hasQueue ? c.previous : null,
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: play,
              child: Material(
                color: t.canPlay ? colors.inverse : colors.inverse.withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(math.min(18.0, LayoutPrefs.radius(18))),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: t.canPlay ? c.togglePlay : null,
                  child: SizedBox(
                    width: 104,
                    height: 36,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          t.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          color: colors.onInverse,
                          size: 20,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          t.playing ? 'Pause' : 'Play',
                          maxLines: 1,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(color: colors.onInverse, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            PartButton(
              icon: Icons.skip_next_rounded,
              tooltip: next,
              look: PartLook.muted,
              round: true,
              size: 36,
              iconSize: 22,
              onPressed: t.hasNext ? c.next : null,
            ),
            const SizedBox(width: 8),
            _repeatButton(c, t, size: 20),
          ],
        );
      },
    );
  }
}

/// The row under the controls: small buttons (Chips) or Lyrics, the output and Queue (Minimal).
/// Lyrics is in both, always.
class PlayerBottomButtons extends StatelessWidget {
  const PlayerBottomButtons({super.key, this.withMore = true});

  /// Chips ends with a More button, unless the buttons by the title already have one.
  final bool withMore;

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.of(context);
    final c = PlayerScope.read(context);
    if (LayoutPrefs.instance.bottomRow == PlayerBottomRow.minimal) return _minimal(context, c, shell);
    return LayoutBuilder(
      builder: (context, box) {
        final size = math.min(44.0, (box.maxWidth - 44) / 6);
        Widget gap() => const SizedBox(width: 8);
        return PlayerSelect<_Transport>(
          select: _selectTransport,
          builder: (context, t, _) => Row(
            children: [
              PartButton(icon: Icons.queue_music_rounded, tooltip: 'Queue', size: size, onPressed: shell.openQueue),
              gap(),
              ListenableBuilder(
                listenable: c.sleep,
                builder: (context, _) {
                  final label = SleepTimerLabel.of(c.sleep);
                  return PartButton(
                    icon: c.sleep.active ? Icons.bedtime_rounded : Icons.bedtime_outlined,
                    tooltip: c.sleep.active ? 'Sleep timer: $label' : 'Sleep timer',
                    lit: c.sleep.active,
                    size: size,
                    onPressed: () => showSleepTimer(context),
                  );
                },
              ),
              gap(),
              PartButton(
                icon: Icons.shuffle_rounded,
                tooltip: t.shuffle ? 'Disable shuffle' : 'Enable shuffle',
                lit: t.shuffle,
                size: size,
                onPressed: t.hasQueue ? c.toggleShuffle : null,
              ),
              gap(),
              PartButton(icon: Icons.lyrics_outlined, tooltip: 'Lyrics', size: size, onPressed: shell.openLyrics),
              gap(),
              PartButton(
                icon: t.loop == LoopMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                tooltip: switch (t.loop) {
                  LoopMode.off => 'Enable repeat',
                  LoopMode.all => 'Enable repeat one',
                  LoopMode.one => 'Disable repeat',
                },
                lit: t.loop != LoopMode.off,
                size: size,
                onPressed: t.hasQueue ? c.cycleLoopMode : null,
              ),
              const Spacer(),
              if (withMore) PlayerMoreAction(size: size),
            ],
          ),
        );
      },
    );
  }

  Widget _minimal(BuildContext context, PlayerController c, ShellScope shell) {
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    Widget plain(IconData icon, String tooltip, VoidCallback onTap) =>
        PartButton(icon: icon, tooltip: tooltip, look: PartLook.plain, size: 48, iconSize: 26, onPressed: onTap);
    Widget segment(String label, VoidCallback onTap, {bool selected = false}) => Flexible(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? colors.textPrimary.withValues(alpha: 0.16) : null,
            borderRadius: BorderRadius.circular(LayoutPrefs.radius(18)),
          ),
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.labelLarge),
        ),
      ),
    );
    final output = Features.casting;
    final together = Features.listenTogether;
    return Row(
      children: [
        plain(Icons.lyrics_outlined, 'Lyrics', shell.openLyrics),
        Expanded(
          child: output || together
              ? ListenableBuilder(
                  listenable: c.cast,
                  builder: (context, _) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: colors.textPrimary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(LayoutPrefs.radius(20)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (output) segment('Speaker', () => showCastPicker(context), selected: true),
                            if (together)
                              segment('Listen together', () => openListenTogether(context, closePlayer: true)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        c.cast.target == null ? 'Playing on this device' : 'Playing on ${c.cast.target!.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.labelSmall?.copyWith(color: colors.textSecondary),
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
        plain(Icons.queue_music_rounded, 'Queue', shell.openQueue),
      ],
    );
  }
}

/// Now Playing when any part is not Classic: the chosen header, cover, title buttons, controls and bottom
/// row, in the same order as Classic. The background is the page's own.
class ComposedNowPlaying extends StatelessWidget {
  const ComposedNowPlaying({
    super.key,
    required this.track,
    required this.from,
    required this.accent,
    required this.cover,
    required this.classicTopBar,
    required this.showBadge,
  });

  final Track? track;
  final String? from;
  final Color accent;
  final Widget Function(double size, {double radius}) cover;

  /// Classic's top bar; its More button can be left out when another part has it.
  final Widget Function({required bool more}) classicTopBar;
  final bool showBadge;

  @override
  Widget build(BuildContext context) {
    final p = LayoutPrefs.instance;
    final moreElsewhere = p.titleActions == TitleActions.plain || p.bottomRow == PlayerBottomRow.chips;
    final full = p.playerCover == PlayerCover.fullBleed;
    final over = full ? Colors.white : null;
    final more = moreElsewhere
        ? null
        : const PlayerMoreAction(look: PartLook.plain, icon: Icons.more_horiz_rounded, size: 48, iconSize: 28);
    final header = p.playerHeader == PlayerHeader.classic
        ? classicTopBar(more: !moreElsewhere)
        : PlayerTopBar(from: from, trailing: more, color: over);
    final plainControls = p.transport == PlayerTransport.plain;
    final controls = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PlayerTitleBlock(track: track, showBadge: showBadge),
          const SizedBox(height: 16),
          const SeekBar(phonePlayer: true),
          const SizedBox(height: 8),
          switch (p.transport) {
            PlayerTransport.classic => const TransportControls(large: true),
            _ => PlayerControlsRow(plain: plainControls, withModes: p.bottomRow != PlayerBottomRow.chips),
          },
          const SizedBox(height: 4),
          if (p.bottomRow == PlayerBottomRow.classic)
            const _ClassicBottom()
          else
            PlayerBottomButtons(withMore: p.titleActions != TitleActions.plain),
          if (p.showVolumeRow) PlayerVolumeRow(mute: plainControls),
          const SizedBox(height: 8),
        ],
      ),
    );
    final fade = switch (Appearance.instance.nowPlaying.effective(lightweight: LayoutPrefs.lightweight)) {
      NowPlayingBackground.color => AppColors.sink(accent, 0.8),
      NowPlayingBackground.black => Colors.black,
      _ => AppColors.solidBackground.withValues(alpha: 0.7),
    };
    if (full) {
      return Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                final side = math.max(box.maxWidth, box.maxHeight);
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    if (box.maxHeight >= 120)
                      ClipRect(
                        child: OverflowBox(maxWidth: side, maxHeight: side, child: cover(side, radius: 0)),
                      ),
                    // A plain fade into the page below: no blur, nothing animated.
                    IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.45),
                              Colors.transparent,
                              Colors.transparent,
                              fade,
                            ],
                            stops: const [0, 0.25, 0.6, 1],
                          ),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.topCenter,
                      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: header),
                    ),
                  ],
                );
              },
            ),
          ),
          controls,
        ],
      );
    }
    return Column(
      children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: header),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              final art = math.min(box.maxWidth - 48, box.maxHeight - 16);
              return art < 96 ? const SizedBox.shrink() : Center(child: cover(art, radius: LayoutPrefs.radius(8)));
            },
          ),
        ),
        controls,
      ],
    );
  }
}

/// Lyrics on the left, Queue on the right: Classic's bottom row.
class _ClassicBottom extends StatelessWidget {
  const _ClassicBottom();

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.of(context);
    final color = AppColors.of(context).textPrimary;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          tooltip: 'Lyrics',
          color: color,
          onPressed: shell.openLyrics,
          icon: const Icon(Icons.lyrics_outlined),
        ),
        IconButton(
          tooltip: 'Queue',
          color: color,
          onPressed: shell.openQueue,
          icon: const Icon(Icons.queue_music_rounded),
        ),
      ],
    );
  }
}

/// Back from the lyrics page to Now Playing: the page just closes if Now Playing is right under it.
void showNowPlayingFromLyrics(BuildContext context) {
  final shell = ShellScope.of(context);
  final self = ModalRoute.of(context);
  if (self == null || !Navigator.of(context).canPop()) return shell.openNowPlaying();
  var under = false;
  Navigator.of(context).popUntil((r) {
    if (r == self) return false;
    under = r.settings.name == nowPlayingRouteName;
    return true;
  });
  if (!under) shell.openNowPlaying();
}

/// The lyrics page's player as a mini card (a thumbnail, the song, play, expand and More) with the seek bar.
class LyricsBottomCard extends StatelessWidget {
  const LyricsBottomCard({super.key, required this.track, this.desktop = false});

  final Track track;

  /// On desktop the player bar below has the seek bar and More, so the card keeps the song, play and expand.
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final c = PlayerScope.read(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: colors.textPrimary.withValues(alpha: 0.08),
            borderRadius: LayoutPrefs.corner(18),
          ),
          child: Row(
            children: [
              Artwork(track: track, size: 44, radius: LayoutPrefs.radius(10)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
              PlayerSelect<({bool playing, bool canPlay})>(
                select: (c) => (playing: c.showsPlaying, canPlay: c.canPlay),
                builder: (context, s, _) => PartButton(
                  icon: s.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  tooltip: tipWith(s.playing ? 'Pause' : 'Play', AppAction.playPause),
                  look: PartLook.muted,
                  round: true,
                  size: 40,
                  onPressed: s.canPlay ? c.togglePlay : null,
                ),
              ),
              const SizedBox(width: 6),
              PartButton(
                icon: Icons.open_in_full_rounded,
                tooltip: desktop ? 'Expanded player' : 'Now Playing',
                size: 40,
                iconSize: 20,
                onPressed: desktop
                    ? () {
                        expandedPlayerPanel.value = ExpandedPanel.lyrics;
                        showExpandedPlayer(true);
                      }
                    : () => showNowPlayingFromLyrics(context),
              ),
              if (!desktop) ...[const SizedBox(width: 6), const PlayerMoreAction(size: 40)],
            ],
          ),
        ),
        if (!desktop) ...[const SizedBox(height: 12), const SeekBar(phonePlayer: true)],
      ],
    );
  }
}

/// The lyrics page's header as a song card: thumbnail, title, artist, a round close and More.
class LyricsTopHeader extends StatelessWidget {
  const LyricsTopHeader({super.key, required this.track, this.desktop = false});

  final Track track;

  /// On desktop the title bar goes back, so the card ends with the heart and the song's menu instead.
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        Artwork(track: track, size: 48, radius: LayoutPrefs.radius(10)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text(
                track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (desktop) ...[
          LikeButton(track: track, size: 24),
          TrackMenuButton(track: track, nowPlaying: true),
        ] else ...[
          PartButton(
            icon: Icons.close_rounded,
            tooltip: 'Close',
            round: true,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 8),
          const PlayerMoreAction(look: PartLook.muted),
        ],
      ],
    );
  }
}

/// Under the lyrics for the Top header layout: the seek bar, plain controls and the volume.
class LyricsPlainPlayer extends StatelessWidget {
  const LyricsPlainPlayer({super.key});

  @override
  Widget build(BuildContext context) => const Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SeekBar(phonePlayer: true),
      SizedBox(height: 8),
      PlayerControlsRow(plain: true),
      PlayerVolumeRow(mute: true),
    ],
  );
}

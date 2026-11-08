import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart' show LoopMode;

import '../../models/track.dart';
import '../../platform/host.dart';
import '../../platform/features.dart';
import '../../services/language.dart';
import '../../services/layout_prefs.dart';
import '../../services/player_controller.dart';
import '../cast_picker.dart';
import '../pages/listen_together_page.dart';
import '../pages/lyrics_page.dart' show LyricsMoreMenu;
import '../shell_scope.dart';
import '../shortcuts.dart';
import '../theme.dart';
import '../widgets/controls.dart';
import '../widgets/marquee_text.dart';
import '../widgets/signal_path.dart';
import '../widgets/stats_for_nerds.dart' show NowPlayingCover;
import '../widgets/sleep_timer_button.dart';
import '../widgets/track_row.dart';
import '../ytmusic_edit.dart';
import 'more_sheet.dart';
import 'now_playing_page.dart';
import 'player_glass.dart';
import 'full_screen_player.dart' show ExpandedPanel, expandedPlayerPanel, showExpandedPlayer;
import 'player_common.dart' show ArtistLinks;

// The parts the player is assembled from (Settings › Look & feel › Now Playing). The phone builds its Now
// Playing from them; the desktop's expanded player, side panel and bar take the ones that fit a wide window.
// Classic keeps its own widgets in now_playing_page.dart; these are the other choices for each part.

/// Copies a link to the song (or its name, for a file on this device) so it can be pasted anywhere.
Future<void> shareTrack(BuildContext context, Track track) async {
  // A downloaded song keeps the link it came from; a streamed one has its video. A file of your own has neither.
  final source = track.sourceUrl;
  final link = source != null && source.startsWith('http')
      ? source
      : track.videoId == null
      ? null
      : 'https://music.youtube.com/watch?v=${track.videoId}';
  final name = track.artist.isEmpty || track.artist == Track.unknownArtist
      ? track.title
      : '${track.title} – ${track.artist}';
  final text = link == null ? name : '$name\n$link';
  final messenger = ScaffoldMessenger.maybeOf(context);
  // The phone's share sheet; a computer has none, so the link (or the name) is copied instead.
  if (Host.isAndroid) {
    try {
      final shown = await const MethodChannel('riflay/share')
          .invokeMethod<bool>('share', {'text': text, 'subject': name});
      if (shown ?? false) return;
    } catch (e) {
      debugPrint('Share sheet: $e');
    }
  }
  await Clipboard.setData(ClipboardData(text: link ?? name));
  messenger?.showSnackBar(SnackBar(content: Text(link != null ? tr.linkCopied : tr.songNameCopied)));
}

/// How a [PartButton] is filled.
enum PartLook { outlined, filled, muted, plain }

/// A square or round button in the player's own style: corners follow Settings › Pages & navigation › Corners.
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
    this.glass = true,
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

  /// False keeps the plain surface under Liquid Glass controls too (the transport, unless its own switch is on).
  final bool glass;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final radius = math.min(size / 2, LayoutPrefs.radius(round ? size / 2 : 14));
    final glass = this.glass && LayoutPrefs.instance.playerGlassControls && look != PartLook.filled;
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
    final button = IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: iconSize,
      style: IconButton.styleFrom(
        backgroundColor: glass && !lit ? Colors.transparent : fill,
        // Disabled (no next song): the same circle, a dimmer icon.
        disabledBackgroundColor: glass && !lit ? Colors.transparent : fill,
        foregroundColor: color,
        disabledForegroundColor: color.withValues(alpha: 0.38),
        fixedSize: Size.square(size),
        minimumSize: Size.square(size),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: glass ? BorderSide.none : side,
        ),
      ),
      icon: Icon(icon),
    );
    // A dark icon on the white fill: the picture's text shadow would ring it in black.
    // Fully round (the Corners setting allows it): a circle of glass, not a squircle.
    if (glass) return PlayerGlassSurface(radius: radius, circle: round && radius == size / 2, child: button);
    return fill == c.inverse ? OffPicture(child: button) : button;
  }
}

/// One button of a [JoinedButtons] group.
typedef JoinedSegment = ({IconData icon, String tooltip, VoidCallback? onPressed, bool lit});

JoinedSegment joinedSegment(IconData icon, String tooltip, VoidCallback? onPressed, {bool lit = false}) =>
    (icon: icon, tooltip: tooltip, onPressed: onPressed, lit: lit);

/// Buttons that touch, as a Material 3 Expressive connected group. Filled: white segments a hairline apart, the outer
/// corners rounder than the inner ones. Outlined: one rounded outline with thin dividers. No text, only icons.
class JoinedButtons extends StatelessWidget {
  const JoinedButtons({
    super.key,
    required this.segments,
    this.outlined = false,
    this.height = 48,
    this.segmentWidth = 52,
    this.iconSize = 22,
  });

  final List<JoinedSegment> segments;
  final bool outlined;
  final double height;
  final double segmentWidth;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final outer = math.min(height / 2, LayoutPrefs.radius(height / 2));
    final inner = math.min(outer, LayoutPrefs.radius(8));
    Widget segment(int i, {required BorderRadius shape}) {
      final s = segments[i];
      // On white the "on" state is the filled icon (a heart), not a tint that could read as dimmed.
      final color = s.lit && outlined ? c.accent : (outlined ? c.textPrimary : c.onInverse);
      return Tooltip(
        message: s.tooltip,
        child: InkWell(
          customBorder: RoundedRectangleBorder(borderRadius: shape),
          onTap: s.onPressed,
          child: SizedBox(
            width: segmentWidth,
            height: height,
            child: Icon(s.icon, size: iconSize, color: s.onPressed == null ? color.withValues(alpha: 0.38) : color),
          ),
        ),
      );
    }

    final last = segments.length - 1;
    if (outlined) {
      return PlayerGlassSurface(
        radius: outer,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: ShapeDecoration(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(outer),
              side: BorderSide(color: c.textPrimary.withValues(alpha: 0.25)),
            ),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i <= last; i++) ...[
                  if (i > 0) Container(width: 1, height: height * 0.5, color: c.textPrimary.withValues(alpha: 0.2)),
                  segment(i, shape: BorderRadius.zero),
                ],
              ],
            ),
          ),
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i <= last; i++) ...[
          if (i > 0) const SizedBox(width: 2),
          Material(
            color: c.inverse,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.horizontal(
                left: Radius.circular(i == 0 ? outer : inner),
                right: Radius.circular(i == last ? outer : inner),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: OffPicture(
              child: segment(
                i,
                shape: BorderRadius.horizontal(
                  left: Radius.circular(i == 0 ? outer : inner),
                  right: Radius.circular(i == last ? outer : inner),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Share and the heart as one joined white pair (Buttons by the title: Boxed). The heart is there for songs that can be
/// liked; Share is always.
class SharePair extends StatelessWidget {
  const SharePair({super.key, required this.track, this.height = 48, this.segmentWidth = 52, this.iconSize = 22});

  final Track track;
  final double height;
  final double segmentWidth;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final account = PlayerScope.read(context).ytMusic;
    JoinedButtons pair(bool? liked, VoidCallback? toggle) => JoinedButtons(
      height: height,
      segmentWidth: segmentWidth,
      iconSize: iconSize,
      segments: [
        joinedSegment(Icons.share_outlined, tr.share, () => shareTrack(context, track)),
        if (liked != null)
          joinedSegment(
            liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            liked ? tr.removeFromLiked : tr.addToLiked,
            toggle,
            lit: liked,
          ),
      ],
    );
    if (!track.isRemote) return pair(null, null);
    return ListenableBuilder(
      listenable: account,
      builder: (context, _) =>
          account.canEdit ? pair(account.isLiked(track), () => toggleLike(context, track)) : pair(null, null),
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
        tooltip: tr.more,
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
        PlayerGlassSurface(
          circle: true,
          child: IconButton(
            tooltip: tr.close,
            color: color ?? colors.textPrimary,
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
          ),
        ),
        Expanded(
          child: single
              ? Text(
                  tr.playingFrom(from ?? tr.yourLibraryInline),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: text.labelMedium?.copyWith(color: muted, fontWeight: FontWeight.w600),
                )
              : Column(
                  children: [
                    Text(tr.nowPlayingTitle, style: text.labelSmall?.copyWith(color: muted)),
                    Text(
                      from ?? tr.yourLibrarySource,
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
    // On the cover itself (Cover: Background) the text is white, whatever the theme.
    final onCover = LayoutPrefs.instance.playerCover == PlayerCover.background;
    final t = track;
    final actions = t == null
        ? null
        : switch (style) {
            TitleActions.classic => LikeButton(track: t, size: 28, color: colors.textPrimary),
            TitleActions.boxed => SharePair(track: t),
            TitleActions.plain => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PlayerLike(
                  track: t,
                  builder: (context, liked, toggle) => PartButton(
                    icon: liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    tooltip: liked ? tr.removeFromLiked : tr.addToLiked,
                    look: PartLook.plain,
                    lit: false,
                    size: 40,
                    iconSize: 28,
                    onPressed: toggle,
                  ),
                ),
                const PlayerMoreAction(look: PartLook.plain, icon: Icons.more_horiz_rounded, size: 40, iconSize: 28),
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
                t?.title ?? tr.nothingPlaying,
                style: text.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: onCover ? Colors.white : null,
                ),
              ),
              const SizedBox(height: 2),
              if (t == null)
                const SizedBox.shrink()
              else
                ArtistLinks(
                  track: t,
                  style: text.titleMedium?.copyWith(color: onCover ? Colors.white70 : colors.textSecondary),
                ),
              // In every look: the tier's icon and the label, no frame.
              if (showBadge && LayoutPrefs.instance.qualityBadgePlace == QualityBadgePlace.underArtist) ...[
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

Widget _shuffleButton(PlayerController c, _Transport t, {double size = 22}) => PlayerGlassSurface(
  circle: true,
  child: ModeButton(
    tooltip: t.shuffle ? tr.disableShuffle : tr.enableShuffle,
    active: t.shuffle,
    size: size,
    icon: Icons.shuffle_rounded,
    onPressed: t.hasQueue ? c.toggleShuffle : null,
  ),
);

Widget _repeatButton(PlayerController c, _Transport t, {double size = 22}) => PlayerGlassSurface(
  circle: true,
  child: ModeButton(
    tooltip: switch (t.loop) {
      LoopMode.off => tr.enableRepeat,
      LoopMode.all => tr.enableRepeatOne,
      LoopMode.one => tr.disableRepeat,
    },
    active: t.loop != LoopMode.off,
    size: size,
    icon: t.loop == LoopMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
    onPressed: t.hasQueue ? c.cycleLoopMode : null,
  ),
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
        final prev = tipWith(tr.previous, AppAction.previous);
        final next = tipWith(tr.next, AppAction.next);
        final play = tipWith(t.playing ? tr.pause : tr.play, AppAction.playPause);
        if (plain) {
          Widget transport(double radius, Widget child) =>
              PlayerGlassSurface(radius: radius, enabled: LayoutPrefs.instance.glassTransport, child: child);
          // Three big glyphs spread evenly; shuffle and repeat, when they are here, wait small at the edges.
          return Row(
            children: [
              if (withModes) _shuffleButton(c, t),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    transport(
                      32,
                      IconButton(
                        tooltip: prev,
                        iconSize: 44,
                        color: colors.textPrimary,
                        onPressed: t.hasQueue ? c.previous : null,
                        icon: const Icon(Icons.fast_rewind_rounded),
                      ),
                    ),
                    transport(
                      40,
                      t.loading
                          ? SizedBox.square(
                              dimension: 64,
                              child: Center(
                                child: CircularProgressIndicator(strokeWidth: 3, color: colors.textPrimary),
                              ),
                            )
                          : IconButton(
                              tooltip: play,
                              iconSize: 64,
                              color: colors.textPrimary,
                              onPressed: t.canPlay ? c.togglePlay : null,
                              icon: Icon(t.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                            ),
                    ),
                    transport(
                      32,
                      IconButton(
                        tooltip: next,
                        iconSize: 44,
                        color: colors.textPrimary,
                        onPressed: t.hasNext ? c.next : null,
                        icon: const Icon(Icons.fast_forward_rounded),
                      ),
                    ),
                  ],
                ),
              ),
              if (withModes) _repeatButton(c, t),
            ],
          );
        }
        final radius = math.min(32.0, LayoutPrefs.radius(32));
        return Row(
          children: [
            if (withModes) _shuffleButton(c, t),
            PartButton(
              icon: Icons.skip_previous_rounded,
              glass: LayoutPrefs.instance.glassTransport,
              tooltip: prev,
              look: PartLook.muted,
              round: true,
              size: 64,
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
                      height: 64,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          t.loading
                              ? SizedBox.square(
                                  dimension: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2.5, color: colors.onInverse),
                                )
                              : Icon(
                                  t.playing ? Icons.pause_rounded : Icons.play_arrow_outlined,
                                  color: colors.onInverse,
                                  // Dark on the white pill: no picture shadow (a black halo there).
                                  shadows: const [],
                                ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              t.playing ? tr.pause : tr.play,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(color: colors.onInverse, fontWeight: FontWeight.w700, shadows: const []),
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
              glass: LayoutPrefs.instance.glassTransport,
              tooltip: next,
              look: PartLook.muted,
              round: true,
              size: 64,
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

/// Where the song plays from, at the top of the desktop's expanded player and side panel, as Settings › Look & feel ›
/// Now Playing › Top of the player says: Classic is the plain line, the others are the phone's two lines or one.
class PlayerFromLabel extends StatelessWidget {
  const PlayerFromLabel({super.key, required this.from, this.album, this.classic = false});

  final String? from;

  /// Always the plain line, whatever the setting (the expanded player, which is Classic in every preset).
  final bool classic;

  /// What Classic shows when nothing says where the song plays from.
  final String? album;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: LayoutPrefs.instance,
    builder: (context, _) {
      final text = Theme.of(context).textTheme;
      final muted = AppColors.of(context).textSecondary;
      return switch (classic ? PlayerHeader.classic : LayoutPrefs.instance.playerHeader) {
        PlayerHeader.classic => Text(
          from ?? album ?? tr.nowPlaying,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        PlayerHeader.centered => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tr.nowPlayingTitle, style: text.labelSmall?.copyWith(color: muted)),
            Text(
              from ?? album ?? tr.yourLibrarySource,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        PlayerHeader.playingFrom => Text(
          tr.playingFrom(from ?? album ?? tr.yourLibraryInline),
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
List<Widget> desktopTitleActions(BuildContext context, Track track, {bool classic = false}) {
  final menu = TrackMenuButton(track: track, nowPlaying: true);
  return switch (classic ? TitleActions.classic : LayoutPrefs.instance.titleActions) {
    TitleActions.classic => [LikeButton(track: track, size: 26), menu],
    TitleActions.boxed => [
      SharePair(track: track, height: 40, segmentWidth: 42, iconSize: 20),
      const SizedBox(width: 4),
      menu,
    ],
    TitleActions.plain => [
      PlayerLike(
        track: track,
        builder: (context, liked, toggle) => PartButton(
          icon: liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          tooltip: liked ? tr.removeFromLiked : tr.addToLiked,
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
        final prev = tipWith(tr.previous, AppAction.previous);
        final next = tipWith(tr.next, AppAction.next);
        final play = tipWith(t.playing ? tr.pause : tr.play, AppAction.playPause);
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
                          shadows: const [],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          t.playing ? tr.pause : tr.play,
                          maxLines: 1,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(color: colors.onInverse, fontWeight: FontWeight.w700, shadows: const []),
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
    // Chips: the five buttons are one outlined group; More is its own white circle.
    return LayoutBuilder(
      builder: (context, box) {
        final more = withMore ? 48.0 : 0.0;
        final width = math.min(48.0, (box.maxWidth - more - 12) / 5);
        return PlayerSelect<_Transport>(
          select: _selectTransport,
          builder: (context, t, _) => Row(
            children: [
              ListenableBuilder(
                listenable: c.sleep,
                builder: (context, _) => JoinedButtons(
                  outlined: true,
                  height: 48,
                  segmentWidth: width,
                  iconSize: 22,
                  segments: [
                    joinedSegment(Icons.queue_music_rounded, tr.queue, shell.openQueue),
                    joinedSegment(
                      c.sleep.active ? Icons.bedtime_rounded : Icons.bedtime_outlined,
                      c.sleep.active ? tr.sleepTimerWith(SleepTimerLabel.of(c.sleep)) : tr.sleepTimer,
                      () => showSleepTimer(context),
                      lit: c.sleep.active,
                    ),
                    joinedSegment(
                      Icons.shuffle_rounded,
                      t.shuffle ? tr.disableShuffle : tr.enableShuffle,
                      t.hasQueue ? c.toggleShuffle : null,
                      lit: t.shuffle,
                    ),
                    joinedSegment(Icons.lyrics_outlined, tr.lyrics, shell.openLyrics),
                    joinedSegment(
                      t.loop == LoopMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                      switch (t.loop) {
                        LoopMode.off => tr.enableRepeat,
                        LoopMode.all => tr.enableRepeatOne,
                        LoopMode.one => tr.disableRepeat,
                      },
                      t.hasQueue ? c.cycleLoopMode : null,
                      lit: t.loop != LoopMode.off,
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (withMore) const PlayerMoreAction(size: 48, icon: Icons.more_vert_rounded),
            ],
          ),
        );
      },
    );
  }

  /// Lyrics, a capsule of two icons (the speaker opens the volume, the person Listen together or the output) and
  /// Queue. Icons only: a tooltip says what each is.
  Widget _minimal(BuildContext context, PlayerController c, ShellScope shell) {
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    Widget plain(IconData icon, String tooltip, VoidCallback onTap) =>
        PartButton(icon: icon, tooltip: tooltip, look: PartLook.plain, size: 48, iconSize: 26, onPressed: onTap);
    Widget segment(IconData icon, String tooltip, VoidCallback onTap) => PartButton(
      icon: icon,
      tooltip: tooltip,
      look: PartLook.plain,
      round: true,
      size: 44,
      iconSize: 22,
      onPressed: onTap,
      glass: LayoutPrefs.instance.glassVolume,
    );
    final together = Features.listenTogether;
    final output = Features.casting;
    return Row(
      children: [
        plain(Icons.lyrics_outlined, tr.lyrics, shell.openLyrics),
        Expanded(
          child: ListenableBuilder(
            listenable: c.cast,
            builder: (context, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // The volume's own pill: glass only with the Glass volume switch.
                PlayerGlassSurface(
                  radius: 25,
                  enabled: LayoutPrefs.instance.glassVolume,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: ShapeDecoration(
                      shape: const StadiumBorder(),
                      color: LayoutPrefs.instance.playerGlassControls && LayoutPrefs.instance.glassVolume
                          ? Colors.transparent
                          : colors.textPrimary.withValues(alpha: 0.14),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        segment(Icons.speaker_outlined, tr.volume, () => showVolumePopup(context)),
                        if (together || output) ...[
                          Container(width: 1, height: 20, color: colors.textPrimary.withValues(alpha: 0.22)),
                          if (together)
                            segment(
                              Icons.person_outline_rounded,
                              tr.listenTogether,
                              () => openListenTogether(context, closePlayer: true),
                            )
                          else
                            segment(Icons.person_outline_rounded, tr.playOnDevice, () => showCastPicker(context)),
                        ],
                      ],
                    ),
                  ),
                ),
                // Only where the sound goes elsewhere: "Speaker" under it said nothing on every song.
                if (c.cast.target case final target?) ...[
                  const SizedBox(height: 2),
                  Text(
                    target.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelSmall?.copyWith(color: colors.textSecondary, fontSize: 10),
                  ),
                ],
              ],
            ),
          ),
        ),
        plain(Icons.queue_music_rounded, tr.queue, shell.openQueue),
      ],
    );
  }
}

/// The volume as a small sheet from the speaker button: a slider in the Slider look (Settings › Now Playing), with a
/// mute and a speaker icon at its ends.
Future<void> showVolumePopup(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  backgroundColor: AppColors.of(context).elevated,
  showDragHandle: true,
  builder: (context) => const SafeArea(
    child: Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 16), child: PlayerVolumeRow(mute: true)),
  ),
);

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
  Widget build(BuildContext context) => PlayerGlassLayer(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final p = LayoutPrefs.instance;
    final moreElsewhere = p.titleActions == TitleActions.plain || p.bottomRow == PlayerBottomRow.chips;
    final full = p.playerCover == PlayerCover.background;
    final over = full ? Colors.white : null;
    final more = moreElsewhere
        ? null
        : const PlayerMoreAction(look: PartLook.plain, icon: Icons.more_horiz_rounded, size: 48, iconSize: 28);
    final header = p.playerHeader == PlayerHeader.classic
        ? classicTopBar(more: !moreElsewhere)
        : PlayerTopBar(from: from, trailing: more, color: over);
    final plainControls = p.transport == PlayerTransport.plain;
    // A tall phone gets a little more air between the parts, as in the reference; a short one keeps them tight.
    Widget controlsFor(bool roomy) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PlayerTitleBlock(track: track, showBadge: showBadge),
          SizedBox(height: roomy ? 20 : 16),
          PlayerGlassSurface(
            enabled: p.glassSeekBar,
            child: Padding(
              padding: p.playerGlassControls && p.glassSeekBar
                  ? const EdgeInsets.symmetric(horizontal: 12, vertical: 4)
                  : EdgeInsets.zero,
              child: SeekBar(
                phonePlayer: true,
                // Centred between the elapsed and the remaining time.
                middle: showBadge && p.qualityBadgePlace == QualityBadgePlace.timeRow
                    ? const QualityBadge(onDark: true, alignment: Alignment.center)
                    : null,
              ),
            ),
          ),
          SizedBox(height: roomy ? 24 : 14),
          switch (p.transport) {
            PlayerTransport.classic => const TransportControls(large: true),
            _ => PlayerControlsRow(plain: plainControls, withModes: p.bottomRow != PlayerBottomRow.chips),
          },
          SizedBox(height: roomy ? 20 : 10),
          if (p.bottomRow == PlayerBottomRow.classic)
            const _ClassicBottom()
          else
            PlayerBottomButtons(withMore: p.titleActions != TitleActions.plain),
          if (p.showVolumeRow) ...[
            if (p.playerGlassControls && p.glassVolume) const SizedBox(height: 8),
            PlayerVolumeRow(mute: plainControls),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
    if (full) {
      // The cover is the page behind (see NowPlayingPage); here only the header and the controls.
      return LayoutBuilder(
        builder: (context, box) => Column(
          children: [
            Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: header),
            // The cover shows through here: Detail stats sit over it, and a long-press opens their menu, as on a
            // cover card.
            const Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: NowPlayingCover(child: SizedBox.expand()),
              ),
            ),
            controlsFor(box.maxHeight >= 760),
          ],
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, outer) => Column(
        children: [
          Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: header),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                final art = math.min(box.maxWidth - 48, box.maxHeight - 16);
                if (art < 96) return const SizedBox.shrink();
                final card = cover(art, radius: LayoutPrefs.radius(8));
                if (p.playerCover != PlayerCover.square) return Center(child: card);
                // A card sits near the top, as in the reference: header, cover, then the title row.
                final top = math.min(64.0, math.max(8.0, (box.maxHeight - art) * 0.35));
                return Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: EdgeInsets.only(top: top),
                    child: card,
                  ),
                );
              },
            ),
          ),
          controlsFor(outer.maxHeight >= 760),
        ],
      ),
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
          tooltip: tr.lyrics,
          color: color,
          onPressed: shell.openLyrics,
          icon: const Icon(Icons.lyrics_outlined),
        ),
        IconButton(
          tooltip: tr.queue,
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
    final song = Expanded(
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
    );
    if (!desktop) {
      // The song, a joined white pair (open the player, More) and the progress bar, on the page itself.
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Artwork(track: track, size: 56, radius: LayoutPrefs.radius(8)),
              const SizedBox(width: 12),
              song,
              JoinedButtons(
                height: 44,
                segmentWidth: 46,
                segments: [
                  joinedSegment(Icons.fullscreen_rounded, tr.nowPlayingTitle, () => showNowPlayingFromLyrics(context)),
                  joinedSegment(Icons.more_horiz_rounded, tr.more, () => showPlayerMore(context, closePlayer: true)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          const SeekBar(phonePlayer: true),
        ],
      );
    }
    return PlayerGlassSurface(
      radius: 18,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: LayoutPrefs.instance.playerGlassControls
              ? Colors.transparent
              : colors.textPrimary.withValues(alpha: 0.08),
          borderRadius: LayoutPrefs.corner(18),
        ),
        child: Row(
          children: [
            Artwork(track: track, size: 44, radius: LayoutPrefs.radius(10)),
            const SizedBox(width: 10),
            song,
            PlayerSelect<({bool playing, bool canPlay})>(
              select: (c) => (playing: c.showsPlaying, canPlay: c.canPlay),
              builder: (context, s, _) => PartButton(
                icon: s.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                tooltip: tipWith(s.playing ? tr.pause : tr.play, AppAction.playPause),
                look: PartLook.muted,
                round: true,
                size: 40,
                onPressed: s.canPlay ? c.togglePlay : null,
              ),
            ),
            const SizedBox(width: 6),
            PartButton(
              icon: Icons.open_in_full_rounded,
              tooltip: tr.expandedPlayer,
              size: 40,
              iconSize: 20,
              onPressed: () {
                expandedPlayerPanel.value = ExpandedPanel.lyrics;
                showExpandedPlayer(true);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// The lyrics page's header as a song card: thumbnail, title, artist, a round close and More.
class LyricsTopHeader extends StatelessWidget {
  const LyricsTopHeader({super.key, required this.track, this.desktop = false});

  final Track track;

  /// On desktop the title bar goes back, so the card ends with the heart and the lyrics / player menu instead.
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
          // The lyrics options (translation, timing...) and the player's, in one ⋯: one row, as on a phone.
          LyricsMoreMenu(track: track),
        ] else ...[
          PartButton(
            icon: Icons.close_rounded,
            tooltip: tr.close,
            look: PartLook.muted,
            round: true,
            size: 44,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 8),
          // The translation and the other lyrics options are in this menu.
          LyricsMoreMenu(track: track),
        ],
      ],
    );
  }
}

/// Under the lyrics for the Top header layout: the seek bar, plain controls and the volume.
class LyricsPlainPlayer extends StatelessWidget {
  const LyricsPlainPlayer({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: LayoutPrefs.instance,
    builder: (context, _) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SeekBar(phonePlayer: true),
        const SizedBox(height: 8),
        // Three glyphs, as in the reference; shuffle and repeat are on Now Playing.
        const PlayerControlsRow(plain: true, withModes: false),
        PlayerVolumeRow(mute: true),
      ],
    ),
  );
}

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../../platform/features.dart';
import '../../services/layout_prefs.dart';
import '../../services/player_controller.dart';
import '../download_options.dart';
import '../player/player_parts.dart';
import '../shell_scope.dart';
import '../theme.dart';
import 'controls.dart';
import 'editable_title.dart';

/// The top of an album or playlist page with Settings › Layout › Album and playlist top set to Hero: the cover
/// across the whole width, fading into the page, with the title over its foot, then round buttons around a wide
/// Play. The page's own buttons ([actions], like a playlist's menu) join the row. On desktop the cover is a
/// shorter strip and the title can be renamed in place when [onRename] is given.
class CollectionHero extends StatelessWidget {
  const CollectionHero({super.key, required this.collection, required this.actions, this.onRename});

  final Collection collection;
  final List<Widget> actions;
  final FutureOr<void> Function(String name)? onRename;

  @override
  Widget build(BuildContext context) {
    final c = PlayerScope.identity(context);
    final shell = ShellScope.of(context);
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final tracks = collection.tracks;
    final isArtist = collection.kind == CollectionKind.artist;
    final total = formatTotal(tracks);
    final meta = ['${tracks.length} ${tracks.length == 1 ? 'song' : 'songs'}', if (total.isNotEmpty) total].join(' • ');
    final artist = collection.kind == CollectionKind.album ? c.artistNamed(collection.subtitle) : null;
    // The page behind the fade: the desktop's content panel, the phone's background.
    final fadeTo = shell.compact ? AppColors.solidBackground : AppColors.panel.withValues(alpha: 1);
    return LayoutBuilder(
      builder: (context, box) {
        final side = math.min(box.maxWidth, shell.compact ? 480.0 : 360.0);
        return Column(
          children: [
            SizedBox(
              height: side,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRect(
                    child: OverflowBox(
                      maxWidth: math.max(side, box.maxWidth),
                      maxHeight: math.max(side, box.maxWidth),
                      child: Artwork(track: collection.cover, size: math.max(side, box.maxWidth), radius: 0),
                    ),
                  ),
                  // A plain fade into the page: no blur, nothing animated.
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, fadeTo.withValues(alpha: 0.85), fadeTo],
                        stops: const [0.3, 0.8, 1],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 24,
                    right: 24,
                    bottom: 0,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (onRename case final rename?)
                          EditableTitle(
                            title: collection.title,
                            onRename: rename,
                            textAlign: TextAlign.center,
                            style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.5),
                          )
                        else
                          Text(
                            collection.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.5),
                          ),
                        if (collection.kind == CollectionKind.album && collection.subtitle.isNotEmpty)
                          GestureDetector(
                            onTap: artist == null ? null : () => shell.openCollection(artist),
                            child: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                collection.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.titleMedium?.copyWith(color: colors.accent, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                        const SizedBox(height: 4),
                        Text(meta, style: text.bodyMedium?.copyWith(color: colors.textSecondary)),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: PlayerSelect<(bool, bool, bool)>(
                select: (c) {
                  final here = c.isPlayingFrom(collection);
                  return (here, here && c.showsPlaying, here && c.shuffle);
                },
                builder: (context, s, _) {
                  final (playingHere, playing, shuffled) = s;
                  final empty = tracks.isEmpty;
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (collection.kind == CollectionKind.remote && !empty && Features.downloads) ...[
                        PartButton(
                          icon: Icons.download_for_offline_outlined,
                          tooltip: 'Download all for offline',
                          look: PartLook.muted,
                          round: true,
                          size: 48,
                          onPressed: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            final choice = await chooseDownload(context);
                            if (choice == null) return;
                            final n = c.youtube.enqueueTracks(tracks, choice: choice);
                            messenger.showSnackBar(
                              SnackBar(content: Text(n == 0 ? 'Already downloaded' : 'Downloading $n songs…')),
                            );
                          },
                        ),
                        const SizedBox(width: 12),
                      ],
                      PartButton(
                        icon: Icons.shuffle_rounded,
                        tooltip: playingHere ? (shuffled ? 'Disable shuffle' : 'Enable shuffle') : 'Shuffle play',
                        look: PartLook.muted,
                        lit: shuffled,
                        round: true,
                        size: 48,
                        onPressed: empty
                            ? null
                            : playingHere
                            ? c.toggleShuffle
                            : () => c.playCollection(collection, shuffled: true),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 160),
                          child: Tooltip(
                            message: playing ? 'Pause' : 'Play',
                            child: Material(
                              color: empty ? colors.inverse.withValues(alpha: 0.4) : colors.inverse,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(LayoutPrefs.radius(28)),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: empty
                                    ? null
                                    : playingHere
                                    ? c.togglePlay
                                    : () => c.playCollection(collection),
                                child: SizedBox(
                                  height: 56,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                        color: colors.onInverse,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        playing ? 'Pause' : 'Play',
                                        style: text.titleMedium?.copyWith(
                                          color: colors.onInverse,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      for (final a in actions) ...[const SizedBox(width: 12), a],
                    ],
                  );
                },
              ),
            ),
            if (!isArtist)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Songs',
                    style: text.titleLarge?.copyWith(color: colors.accent, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

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
import 'faded_cover.dart';
import 'menus.dart';
import '../ytmusic_edit.dart' show FollowButton, addToPlaylist;
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
    // An artist page: your own artist, or a YouTube Music one (it has a Follow button).
    final artistPage = isArtist || actions.any((a) => a is FollowButton);
    final radioSeed = tracks.where((t) => t.isRemote).firstOrNull;
    // An artist: how many songs and albums; an album or playlist: its songs and length.
    final albums = isArtist
        ? c.albums.where((a) => Track.splitArtists(a.subtitle).contains(collection.title)).length
        : 0;
    final meta = isArtist
        ? [
            '${tracks.length} ${tracks.length == 1 ? 'song' : 'songs'}',
            '$albums ${albums == 1 ? 'album' : 'albums'}',
          ].join(' • ')
        : ['${tracks.length} ${tracks.length == 1 ? 'song' : 'songs'}', if (total.isNotEmpty) total].join(' • ');
    final artist = collection.kind == CollectionKind.album ? c.artistNamed(collection.subtitle) : null;
    // The page behind the fade: the desktop's content panel, the phone's background.
    final fadeTo = AppColors.panel.withValues(alpha: 1);
    return LayoutBuilder(
      builder: (context, box) {
        final side = math.min(box.maxWidth, shell.compact ? 480.0 : 360.0);
        // On a phone the picture goes up under the status bar; the page's back button floats over it.
        final topInset = shell.compact ? MediaQuery.paddingOf(context).top : 0.0;
        return Column(
          children: [
            SizedBox(
              height: side + topInset,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // The cover is the whole header: sharp at the top, softer below, ending in the page's own colour.
                  FadedCover(track: collection.cover, fade: fadeTo, blurStart: 0.45, darken: 0.3),
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
                                style: text.titleMedium?.copyWith(
                                  color: colors.accent,
                                  fontWeight: FontWeight.w700,
                                  decoration: TextDecoration.underline,
                                  decorationColor: colors.accent,
                                ),
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
                  // Everything past shuffle, Play and the page's own buttons: shown while they fit beside a Play
                  // button that stays whole, the rest behind ⋯.
                  final extras = <({IconData icon, String label, VoidCallback onTap})>[
                    // An artist: all of their songs into one of your playlists, or a radio of them.
                    if (artistPage && !empty)
                      (
                        icon: Icons.library_add_rounded,
                        label: 'Add all to playlist',
                        onTap: () => addToPlaylist(context, tracks),
                      ),
                    if (artistPage && radioSeed != null)
                      (icon: Icons.sensors_rounded, label: 'Start radio', onTap: () => c.startRadio(radioSeed)),
                    // Albums and playlists: everything into the queue.
                    if (!artistPage && !empty)
                      (
                        icon: Icons.playlist_add_rounded,
                        label: 'Add all to queue',
                        onTap: () {
                          c.addToQueue(tracks);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added to queue')));
                        },
                      ),
                    if (collection.kind == CollectionKind.remote && !empty && Features.downloads)
                      (
                        icon: Icons.download_for_offline_outlined,
                        label: 'Download all for offline',
                        onTap: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final choice = await chooseDownload(context);
                          if (choice == null) return;
                          final n = c.youtube.enqueueTracks(tracks, choice: choice);
                          messenger.showSnackBar(
                            SnackBar(content: Text(n == 0 ? 'Already downloaded' : 'Downloading $n songs…')),
                          );
                        },
                      ),
                  ];
                  Widget round(IconData icon, String tooltip, VoidCallback onPressed) => PartButton(
                    icon: icon,
                    tooltip: tooltip,
                    look: PartLook.muted,
                    round: true,
                    size: 48,
                    onPressed: onPressed,
                  );
                  return LayoutBuilder(
                    builder: (context, box) {
                      const slot = 48.0 + 12; // a round button and the gap before it
                      const play = 132.0; // "Pause" whole, with its icon
                      final room = box.maxWidth - slot - play - actions.length * slot;
                      final fit = (room / slot).floor().clamp(0, extras.length);
                      // All of them, or one place fewer and ⋯ for the rest.
                      final shown = fit >= extras.length ? extras.length : math.max(0, fit - 1);
                      final hidden = extras.skip(shown).toList();
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
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
                              constraints: const BoxConstraints(minWidth: play, maxWidth: 160),
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
                          for (final e in extras.take(shown)) ...[
                            const SizedBox(width: 12),
                            round(e.icon, e.label, e.onTap),
                          ],
                          if (hidden.isNotEmpty) ...[
                            const SizedBox(width: 12),
                            PopupMenuButton<VoidCallback>(
                              // The round button inside says it.
                              tooltip: '',
                              color: AppColors.menu,
                              shape: menuShape,
                              onSelected: (act) => act(),
                              itemBuilder: (_) => [
                                for (final e in hidden)
                                  PopupMenuItem(
                                    value: e.onTap,
                                    child: MenuRow(leading: Icon(e.icon), title: Text(e.label)),
                                  ),
                              ],
                              child: IgnorePointer(child: round(Icons.more_horiz_rounded, 'More', () {})),
                            ),
                          ],
                        ],
                      );
                    },
                  );
                },
              ),
            ),
            // Room between the buttons and the first song.
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}

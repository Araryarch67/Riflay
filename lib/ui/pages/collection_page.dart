import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../../platform/features.dart';
import '../../services/artist_channels.dart';
import '../../services/flac_convert.dart';
import '../../services/language.dart';
import '../../services/layout_prefs.dart';
import '../../services/play_history.dart';
import '../../services/player_controller.dart';
import '../../services/smart_playlists.dart';
import '../download_options.dart';
import '../flac_convert_dialog.dart';
import '../shell_scope.dart';
import '../theme.dart';
import '../player/player_parts.dart' show PartButton, PartLook;
import '../widgets/collection_hero.dart';
import '../widgets/controls.dart';
import '../widgets/editable_title.dart';
import '../widgets/about_artist.dart';
import '../widgets/page_scaffold.dart';
import '../widgets/shelf.dart';
import '../widgets/track_row.dart';
import '../widgets/track_selection.dart';
import '../ytmusic_edit.dart';
import '../widgets/menus.dart';
import '../widgets/app_dialog.dart';

/// Album / artist / "All Songs" page with a colour-washed header.
class CollectionPage extends StatelessWidget {
  const CollectionPage({super.key, required this.collection, this.actions = const [], this.onRename, this.onReorder});

  final Collection collection;

  /// Makes the title rename in place (Riflay playlists always can; this is for others, like owned YouTube Music ones).
  final Future<void> Function(String name)? onRename;

  /// Makes the rows drag-to-reorder (Riflay playlists always can; this is for others, like owned YouTube Music ones).
  /// [to] is where the song ends up in the finished list.
  final void Function(int from, int to)? onReorder;

  /// Extra buttons next to Play / Shuffle (e.g. editing one of your playlists).
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    // Rebuilt when the library changes (and Liked music with every like,
    // wherever in the app it's made), not on every change of what's playing:
    // the buttons and rows that show that follow it themselves.
    final c = PlayerScope.identity(context);
    // Songs can be picked (hold a row) to add several to a playlist or the queue at once.
    Widget page([Track? picture]) => TrackSelectionHost(
      child: ListenableBuilder(
        listenable: collection.id == likedMusicId
            ? Listenable.merge([c.libraryRevision, c.ytMusic])
            : collection.kind == CollectionKind.smart
            ? Listenable.merge([c.libraryRevision, PlayHistory.instance])
            : c.libraryRevision,
        builder: (context, _) => _build(context, c, picture),
      ),
    );
    // An artist is pictured by their own photo, not by their first song's cover (a playlist keeps that); the
    // song's cover stays until the photo is found, and when there is none.
    if (collection.kind != CollectionKind.artist && !actions.any((a) => a is FollowButton)) return page();
    return FutureBuilder(
      future: ArtistChannels.picture(
        c.ytMusic,
        collection.title,
        channelId: actions.whereType<FollowButton>().firstOrNull?.artistId,
      ),
      builder: (context, snap) => page(snap.data),
    );
  }

  Widget _build(BuildContext context, PlayerController c, Track? picture) {
    final shell = ShellScope.of(context);
    // Re-resolve so tag scans / removals show up while the page is open.
    var live =
        switch (collection.kind) {
          CollectionKind.allSongs => c.allSongs,
          CollectionKind.youtube => c.youtubeDownloads,
          CollectionKind.remote => switch (c.ytMusic.libraryNow?.liked) {
            final liked? when collection.id == likedMusicId => Collection(
              kind: collection.kind,
              id: likedMusicId,
              title: collection.title,
              subtitle: collection.subtitle,
              tracks: liked,
            ),
            _ => null,
          },
          CollectionKind.smart => SmartPlaylists.of(c, PlayHistory.instance)[SmartList.byId(collection.id)],
          CollectionKind.playlist => c.playlistById(collection.id),
          CollectionKind.artist => c.artistNamed(collection.title),
          CollectionKind.remoteArtist => null,
          CollectionKind.folder => c.folderAt(collection.id),
          CollectionKind.album => c.albums.where((a) => a.title == collection.title).firstOrNull,
        } ??
        collection;
    if (picture != null) live = live.withPicture(picture);
    final tracks = live.tracks;
    final isArtist = live.kind == CollectionKind.artist;
    final isAll = live.kind == CollectionKind.allSongs;
    final multiDisc = live.kind == CollectionKind.album && tracks.map((t) => t.discNumber ?? 1).toSet().length > 1;
    // Song i is row i; a disc heading (multi-disc albums) is -1 - the index of the song it heads.
    final rows = multiDisc
        ? [
            for (var i = 0; i < tracks.length; i++) ...[
              if (i == 0 || tracks[i].discNumber != tracks[i - 1].discNumber) -1 - i,
              i,
            ],
          ]
        : List<int>.generate(tracks.length, (i) => i);
    final text = Theme.of(context).textTheme;
    final playlistId = live.kind == CollectionKind.playlist ? live.id : null;
    final reorder = playlistId != null ? (int from, int to) => c.movePlaylistTrack(playlistId, from, to) : onReorder;
    final actions = [
      ...this.actions,
      if (playlistId != null) _PlaylistMenu(id: playlistId, name: live.title, tracks: tracks),
    ];

    final hero = LayoutPrefs.instance.albumHeader == AlbumHeaderStyle.hero;
    // Desktop: the hero has no row for these, so they join its buttons.
    final heroActions = [
      ...actions,
      if (!shell.compact && isAll)
        PartButton(
          icon: Icons.add_circle_outline_rounded,
          tooltip: tr.addFiles,
          look: PartLook.muted,
          round: true,
          size: 48,
          onPressed: shell.addFiles,
        ),
      if (!shell.compact && live.kind == CollectionKind.youtube)
        PartButton(
          icon: Icons.add_link_rounded,
          tooltip: tr.importFromYouTube,
          look: PartLook.muted,
          round: true,
          size: 48,
          onPressed: shell.importFromYoutube,
        ),
    ];
    final page = AccentBuilder(
      track: live.cover,
      builder: (context, accent) {
        final headerColor = accent;
        return PageScaffold(
          // The hero's picture runs to the very top on desktop too; the bar fills in once it has scrolled away.
          overHero: hero,
          gradientColor: headerColor,
          title: live.title,
          slivers: [
            SliverToBoxAdapter(
              child: hero
                  ? CollectionHero(
                      collection: live,
                      actions: heroActions,
                      onRename: shell.compact
                          ? null
                          : (playlistId != null ? (name) => c.renamePlaylist(playlistId, name) : onRename),
                    )
                  : _Header(
                      collection: live,
                      accent: headerColor,
                      onRename: playlistId != null ? (name) => c.renamePlaylist(playlistId, name) : onRename,
                    ),
            ),
            if (!hero)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(shell.compact ? 16 : 24, 16, 24, 8),
                  child: Row(
                    children: [
                      PlayerSelect<(bool, bool, bool)>(
                        select: (c) {
                          final here = c.isPlayingFrom(live);
                          return (here, here && c.showsPlaying, here && c.shuffle);
                        },
                        builder: (context, s, _) {
                          final (playingHere, playing, shuffled) = s;
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              PlayButton(
                                size: 56,
                                color: AppColors.accent,
                                iconColor: AppColors.onAccent,
                                playing: playing,
                                onPressed: tracks.isEmpty
                                    ? null
                                    : playingHere
                                    ? c.togglePlay
                                    : () => c.playCollection(live),
                              ),
                              const SizedBox(width: 16),
                              // Lit while this collection plays shuffled; there it toggles shuffle.
                              ModeButton(
                                tooltip: playingHere
                                    ? (shuffled ? tr.disableShuffle : tr.enableShuffle)
                                    : tr.shufflePlay,
                                active: shuffled,
                                size: 30,
                                icon: Icons.shuffle_rounded,
                                onPressed: tracks.isEmpty
                                    ? null
                                    : playingHere
                                    ? c.toggleShuffle
                                    : () => c.playCollection(live, shuffled: true),
                              ),
                            ],
                          );
                        },
                      ),
                      ...actions,
                      // An artist (yours, or a YouTube Music one with Follow): all of their songs into a playlist.
                      if ((isArtist || actions.any((a) => a is FollowButton)) && tracks.isNotEmpty)
                        IconButton(
                          tooltip: tr.addAllToPlaylist,
                          onPressed: () => addToPlaylist(context, tracks),
                          icon: const Icon(Icons.library_add_rounded),
                        ),
                      if (isAll) ...[
                        const Spacer(),
                        IconButton(
                          tooltip: tr.addFiles,
                          onPressed: shell.addFiles,
                          icon: const Icon(Icons.add_circle_outline_rounded),
                        ),
                      ],
                      if (live.kind == CollectionKind.remote && tracks.isNotEmpty && Features.downloads) ...[
                        const Spacer(),
                        IconButton(
                          tooltip: tr.downloadAllOffline,
                          onPressed: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            final choice = await chooseDownload(context);
                            if (choice == null) return;
                            final n = c.youtube.enqueueTracks(tracks, choice: choice);
                            messenger.showSnackBar(
                              SnackBar(content: Text(n == 0 ? tr.alreadyDownloaded : tr.downloadingSongs(n))),
                            );
                          },
                          icon: const Icon(Icons.download_for_offline_outlined),
                        ),
                      ],
                      if (live.kind == CollectionKind.youtube) ...[
                        const Spacer(),
                        IconButton(
                          tooltip: tr.importFromYouTube,
                          onPressed: shell.importFromYoutube,
                          icon: const Icon(Icons.add_link_rounded),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            // An artist's page says who they are: yours by name, a YouTube Music one by its channel.
            if (isArtist || actions.any((a) => a is FollowButton))
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(shell.compact ? 16 : 24, 8, shell.compact ? 16 : 24, 8),
                  child: AboutArtist(
                    name: live.title,
                    channelId: actions.whereType<FollowButton>().firstOrNull?.artistId,
                    full: true,
                  ),
                ),
              ),
            if (!shell.compact) SliverToBoxAdapter(child: _ColumnHeader(showAlbum: live.kind != CollectionKind.album)),
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: shell.compact ? 12 : 16),
              // Rows are built as they scroll into view: All Songs can hold thousands.
              sliver: _rowsSliver(
                // Only your playlists (Riflay's, or your own on YouTube Music) are yours to reorder; albums keep their order.
                onReorder: reorder,
                itemCount: rows.length,
                prototype:
                    reorder == null &&
                        !multiDisc &&
                        tracks.isNotEmpty &&
                        tracks.every((t) => t.isRemote == tracks.first.isRemote)
                    ? TrackRow(
                        track: tracks.first,
                        index: 1,
                        showArtwork: live.kind != CollectionKind.album,
                        showAlbum: live.kind != CollectionKind.album,
                        onTap: () {},
                      )
                    : null,
                itemBuilder: (context, r) {
                  final i = rows[r];
                  // Multi-disc albums: a "Disc 2" heading where each disc starts.
                  if (i < 0) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: Row(
                        children: [
                          Icon(Icons.album_outlined, size: 18, color: AppColors.textSecondary),
                          const SizedBox(width: 12),
                          Text(
                            tr.disc(tracks[-1 - i].discNumber ?? 1),
                            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    );
                  }
                  final row = TrackRow(
                    track: tracks[i],
                    index: multiDisc ? (tracks[i].trackNumber ?? i + 1) : i + 1,
                    showArtwork: live.kind != CollectionKind.album,
                    showAlbum: live.kind != CollectionKind.album,
                    onTap: () => c.playCollection(live, index: i),
                  );
                  if (reorder == null) return row;
                  // The handle sits at the row's end; the list needs a key per song to follow it while dragging.
                  return Row(
                    key: ValueKey(tracks[i].id),
                    children: [
                      Expanded(child: row),
                      ReorderableDragStartListener(
                        index: i,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.grab,
                          child: Padding(
                            // A finger needs a bigger target than a pointer.
                            padding: EdgeInsets.all(shell.compact ? 12 : 8),
                            child: Icon(Icons.drag_handle_rounded, size: 22, color: AppColors.textSecondary),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            if (isArtist) ..._artistAlbums(context, c, live),
            // Room for the bar of picked songs, so it never covers the last ones.
            if (TrackSelectionScope.maybeOf(context) case final selection?)
              SliverToBoxAdapter(
                child: ListenableBuilder(
                  listenable: selection,
                  builder: (context, _) => SizedBox(height: selection.active ? 88 : 0),
                ),
              ),
          ],
        );
      },
    );
    final selection = TrackSelectionScope.maybeOf(context);
    final withBar = selection == null
        ? page
        : Stack(
            children: [
              page,
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: SafeArea(
                  top: false,
                  child: TrackSelectionBar(selection: selection, tracks: tracks),
                ),
              ),
            ],
          );
    if (playlistId == null) return withBar;
    // A Riflay playlist: every song in it can be taken out.
    return PlaylistEditScope(
      canRemove: (t) => tracks.any((x) => x.id == t.id),
      remove: (context, t) async {
        c.removeFromPlaylist(playlistId, t);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr.removedFrom(live.title)),
            action: SnackBarAction(label: tr.undo, onPressed: () => c.addToPlaylist(playlistId, [t])),
          ),
        );
      },
      child: withBar,
    );
  }

  /// The song rows: a plain lazy list, or for a playlist of yours a drag-to-reorder one (same sliver, so scrolling is unchanged).
  Widget _rowsSliver({
    required void Function(int from, int to)? onReorder,
    required int itemCount,
    required Widget Function(BuildContext, int) itemBuilder,
    Widget? prototype,
  }) {
    if (onReorder == null) {
      // Every row the same height (no disc headings; all local or all streamed, which decides the download button):
      // laid out from one measured row instead of each one, so a long list scrolls and jumps without measuring.
      return prototype == null
          ? SliverList.builder(itemCount: itemCount, itemBuilder: itemBuilder)
          : SliverPrototypeExtentList.builder(itemCount: itemCount, itemBuilder: itemBuilder, prototypeItem: prototype);
    }
    return SliverReorderableList(
      itemCount: itemCount,
      itemBuilder: itemBuilder,
      onReorderItem: onReorder,
      // Handles are ours, so a long press on the row still opens its menu.
      proxyDecorator: (child, _, _) => Material(color: AppColors.elevated, elevation: 6, child: child),
    );
  }

  List<Widget> _artistAlbums(BuildContext context, PlayerController c, Collection artist) {
    final albums = c.albums.where((a) => a.subtitle == artist.title).toList();
    if (albums.isEmpty) return const [];
    return [
      SliverToBoxAdapter(
        child: Shelf(
          title: tr.albums,
          cards: [
            for (final album in albums)
              MediaCard(
                track: album.cover,
                title: album.title,
                subtitle: tr.album,
                onTap: () => ShellScope.of(context).openCollection(album),
                onPlay: () => c.playCollection(album),
              ),
          ],
        ),
      ),
    ];
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.collection, required this.accent, this.onRename});

  final Collection collection;
  final Color accent;
  final FutureOr<void> Function(String name)? onRename;

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.of(context);
    final text = Theme.of(context).textTheme;
    final isArtist = collection.kind == CollectionKind.artist;
    final isAll = collection.kind == CollectionKind.allSongs;
    final total = formatTotal(collection.tracks);
    final count = tr.songsPlural(collection.tracks.length);
    final meta = [
      if (collection.kind == CollectionKind.album) collection.subtitle,
      count,
      if (total.isNotEmpty) total,
    ].join(' • ');

    final art = Container(
      decoration: BoxDecoration(
        shape: isArtist ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: isArtist ? null : BorderRadius.circular(6),
        boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 48, offset: Offset(0, 4))],
      ),
      child: isAll
          ? CoverMosaic(tracks: collection.tracks, size: shell.compact ? 200 : 220, radius: 6)
          : Artwork(track: collection.cover, size: shell.compact ? 200 : 220, radius: 6, circle: isArtist),
    );

    final titleSize = shell.compact
        ? 30.0
        : collection.title.length > 24
        ? 40.0
        : 64.0;
    final titleStyle = text.displaySmall?.copyWith(
      fontSize: titleSize,
      fontWeight: FontWeight.w900,
      letterSpacing: -1.5,
      height: 1.05,
    );
    final info = Column(
      crossAxisAlignment: shell.compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!shell.compact) Text(collection.kind.label, style: text.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        if (onRename != null)
          EditableTitle(
            title: collection.title,
            onRename: onRename!,
            textAlign: shell.compact ? TextAlign.center : TextAlign.start,
            style: titleStyle,
          )
        else
          Text(
            collection.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: shell.compact ? TextAlign.center : TextAlign.start,
            style: titleStyle,
          ),
        const SizedBox(height: 12),
        Text(meta, style: text.bodyMedium?.copyWith(color: AppColors.textPrimary.withValues(alpha: 0.8))),
      ],
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(shell.compact ? 16 : 24, shell.compact ? 8 : 32, 24, 8),
      child: shell.compact
          ? Column(children: [art, const SizedBox(height: 20), info])
          : Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                art,
                const SizedBox(width: 24),
                Expanded(child: info),
              ],
            ),
    );
  }
}

class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader({required this.showAlbum});

  final bool showAlbum;

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.of(context);
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 0),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 32,
                child: Center(child: Text('#', style: style)),
              ),
              const SizedBox(width: 12),
              Expanded(flex: 5, child: Text(tr.title, style: style)),
              if (showAlbum && shell.width > 900) ...[
                const SizedBox(width: 16),
                Expanded(flex: 4, child: Text(tr.album, style: style)),
              ],
              const SizedBox(
                width: 56,
                child: Align(alignment: Alignment.centerRight, child: Icon(Icons.schedule_rounded, size: 16)),
              ),
              const SizedBox(width: 40),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Rename / delete for a Riflay playlist.
class _PlaylistMenu extends StatelessWidget {
  const _PlaylistMenu({required this.id, required this.name, required this.tracks});

  final String id;
  final String name;
  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    final c = PlayerScope.read(context);
    // A streamed song counts through its downloaded file.
    final files = [for (final t in tracks) c.downloadedCopy(t) ?? t].where(FlacConvert.available).toList();
    return PopupMenuButton<VoidCallback>(
      // Over the whole window, so a click anywhere (sidebar included) closes it.
      useRootNavigator: true,
      tooltip: tr.editPlaylist,
      icon: const Icon(Icons.more_horiz_rounded, size: 30),
      onSelected: (action) => action(),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: () async {
            final answer = await askPlaylistName(context, initialTitle: name, askPrivacy: false);
            if (answer != null) c.renamePlaylist(id, answer.title);
          },
          child: MenuRow(leading: Icon(Icons.edit_outlined), title: Text(tr.rename)),
        ),
        if (files.isNotEmpty)
          PopupMenuItem(
            value: () => showFlacConvert(context, c, files),
            child: MenuRow(leading: Icon(Icons.graphic_eq_rounded), title: Text(tr.convertAllToFlac)),
          ),
        PopupMenuItem(
          value: () async {
            final history = ShellScope.of(context).history;
            final navigator = Navigator.of(context);
            final sure = await confirmDialog(
              context,
              title: tr.deletePlaylistQuestion,
              body: tr.deletePlaylistBody(name),
              confirmLabel: tr.delete,
              destructive: true,
            );
            if (sure != true) return;
            c.deletePlaylist(id);
            history != null ? history.back() : navigator.maybePop();
          },
          child: MenuRow(leading: Icon(Icons.delete_outline_rounded), title: Text(tr.deletePlaylist)),
        ),
      ],
    );
  }
}

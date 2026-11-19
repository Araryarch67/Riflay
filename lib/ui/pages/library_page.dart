import 'package:flutter/material.dart';

import 'home_page.dart' show openHomeArtist;
import '../../models/track.dart';
import '../../platform/features.dart';
import '../../services/beta_features.dart';
import '../../services/folder_watch.dart';
import '../../services/language.dart';
import '../../services/layout_prefs.dart';
import '../../services/play_history.dart';
import '../../services/player_controller.dart';
import '../../services/playlist_covers.dart';
import '../../services/smart_playlists.dart';
import '../../services/youtube_music_account.dart';
import '../ytmusic_edit.dart';
import '../playlist_cover_edit.dart';
import '../shell_scope.dart';
import '../theme.dart';
import '../widgets/controls.dart';
import 'listening_stats_page.dart';
import 'settings_page.dart';
import 'spotify_page.dart';
import 'youtube_music_page.dart';
import '../widgets/smooth_scroll.dart';
import '../navigation.dart';
import '../widgets/menus.dart';

/// [downloaded]: what was downloaded, grouped (the songs, and the albums and artists they're from), still in the
/// rest of the library too. [local]: what is on this device by where it is, each music folder the person added
/// (with the songs under it) and what was downloaded.
enum LibraryFilter { playlists, downloaded, albums, artists, local }

/// "Your Library": Riflay playlists, YouTube Music (liked songs and
/// playlists, marked with a cloud) and the files on this device, in one list.
/// Used both as the phone tab and (with [dense]) inside the desktop sidebar.
class LibraryList extends StatefulWidget {
  const LibraryList({super.key, this.dense = false, this.collapsed = false});

  final bool dense;

  /// Icon-only rail in the medium layout.
  final bool collapsed;

  @override
  State<LibraryList> createState() => _LibraryListState();
}

class _LibraryListState extends State<LibraryList> {
  bool _editingPlaylists = false;
  LibraryFilter? _filter = LibraryFilter.values.asNameMap()[LayoutPrefs.instance.libraryChip];

  @override
  Widget build(BuildContext context) {
    // The library and the YouTube Music account, not every change of what's
    // playing: this list sits in the sidebar the whole time.
    final c = PlayerScope.identity(context);
    return ListenableBuilder(
      // The music folders too: adding or forgetting one changes Local.
      listenable: Listenable.merge([
        c.libraryRevision,
        c.ytMusic,
        BetaFeatures.instance,
        PlayHistory.instance,
        FolderWatch.instance,
        LayoutPrefs.instance,
        PlaylistCovers.instance,
      ]),
      builder: (context, _) => _build(context, c, c.ytMusic.libraryNow),
    );
  }

  Widget _build(BuildContext context, PlayerController c, YoutubeMusicLibrary? online) {
    final shell = ShellScope.of(context);
    final text = Theme.of(context).textTheme;
    final account = c.ytMusic;
    bool show(LibraryFilter f) => _filter == null || _filter == f;

    final hidden = LayoutPrefs.instance.hiddenCollections;
    final downloads = c.youtubeDownloads;
    final local = switch (_filter) {
      null => c.albumsAndArtists,
      LibraryFilter.albums => c.albums,
      LibraryFilter.artists => c.artists,
      LibraryFilter.downloaded => [
        for (final a in c.albumsAndArtists)
          if (a.tracks.any((t) => t.sourceUrl != null)) a,
      ],
      LibraryFilter.playlists || LibraryFilter.local => const <Collection>[],
    };
    final folders = _filter == LibraryFilter.local ? c.folders : const <Collection>[];

    final prefs = LayoutPrefs.instance;
    final playlistRows = <Widget>[];
    final editing = _editingPlaylists && !widget.collapsed;
    if (show(LibraryFilter.playlists)) {
      final entries = <({String key, String title, Widget Function(Widget? action) row})>[
        for (final collection in [...c.playlists.map(c.playlistCollection), ...c.folderPlaylists])
          if (collection.coverKey case final key?)
            (
              key: key,
              title: collection.title,
              row: (action) => _LibraryRow(
                collection: collection,
                collapsed: widget.collapsed,
                folderPlaylist: collection.kind == CollectionKind.folder,
                action: action,
              ),
            ),
        for (final p in online?.playlists ?? const [])
          (
            key: PlaylistCovers.remoteKey(p.id),
            title: p.title,
            row: (action) => _SimpleRow(
              collapsed: widget.collapsed,
              art: Artwork(
                track: PlaylistCovers.instance.coverOr(PlaylistCovers.remoteKey(p.id), playlistCover(p)),
                size: 48,
              ),
              title: p.title,
              subtitle: p.count == 0
                  ? '${tr.playlist} • YouTube Music'
                  : '${tr.playlist} • YouTube Music • ${tr.songsCount(p.count)}',
              online: true,
              location: Locations.remotePlaylist(p.id),
              onTap: () => openRemotePlaylist(context, p),
              action: action,
            ),
          ),
      ];
      final order = prefs.playlistOrder;
      final rank = {for (final (index, key) in prefs.customPlaylistOrder.indexed) key: index};
      final original = {for (final (index, entry) in entries.indexed) entry.key: index};
      entries.sort((a, b) {
        final pin = (prefs.pinnedPlaylists.contains(b.key) ? 1 : 0) - (prefs.pinnedPlaylists.contains(a.key) ? 1 : 0);
        if (pin != 0) return pin;
        final result = switch (order) {
          PlaylistOrder.library => 0,
          PlaylistOrder.nameAscending => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
          PlaylistOrder.nameDescending => b.title.toLowerCase().compareTo(a.title.toLowerCase()),
          PlaylistOrder.custom => (rank[a.key] ?? rank.length).compareTo(rank[b.key] ?? rank.length),
        };
        return result == 0 ? original[a.key]!.compareTo(original[b.key]!) : result;
      });
      final visible = [for (final entry in entries) entry.key];
      if (editing) {
        final pinnedCount = visible.where(prefs.pinnedPlaylists.contains).length;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      tr.editPlaylists,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(onPressed: () => setState(() => _editingPlaylists = false), child: Text(tr.done)),
                ],
              ),
            ),
            Expanded(
              child: SmoothScroll(
                builder: (context, scroll) => CustomScrollView(
                  controller: scroll,
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      sliver: SliverReorderableList(
                        itemCount: entries.length,
                        onReorderItem: (from, to) {
                          final target = from < pinnedCount
                              ? to.clamp(0, pinnedCount - 1)
                              : to.clamp(pinnedCount, entries.length - 1);
                          if (target != from) prefs.movePlaylist(visible, visible[from], target - from);
                        },
                        // Flutter moves the drag proxy into the root overlay.
                        proxyDecorator: (child, _, _) => PlayerScope(
                          controller: c,
                          child: shell.wrap(
                            Material(
                              color: Theme.of(context).colorScheme.surfaceContainerHigh,
                              elevation: 6,
                              borderRadius: LayoutPrefs.corner(12),
                              child: child,
                            ),
                          ),
                        ),
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          final pinned = prefs.pinnedPlaylists.contains(entry.key);
                          return Row(
                            key: ValueKey(entry.key),
                            children: [
                              Expanded(
                                child: ExcludeFocus(child: IgnorePointer(child: entry.row(null))),
                              ),
                              IconButton(
                                tooltip: pinned ? tr.unpinPlaylist : tr.pinPlaylist,
                                isSelected: pinned,
                                onPressed: () => prefs.togglePinnedPlaylist(entry.key),
                                selectedIcon: const Icon(Icons.push_pin_rounded),
                                icon: const Icon(Icons.push_pin_outlined),
                              ),
                              ReorderableDragStartListener(
                                index: index,
                                child: Tooltip(
                                  message: tr.dragToMove,
                                  child: const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: Icon(Icons.drag_handle_rounded),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      }
      for (final entry in entries) {
        final pinned = prefs.pinnedPlaylists.contains(entry.key);
        playlistRows.add(
          entry.row(
            widget.collapsed
                ? null
                : PopupMenuButton<VoidCallback>(
                    tooltip: tr.playlistOptions,
                    icon: Icon(pinned ? Icons.push_pin_rounded : Icons.more_horiz_rounded, size: 18),
                    onSelected: (action) => action(),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: () => prefs.togglePinnedPlaylist(entry.key),
                        child: Text(pinned ? tr.unpinPlaylist : tr.pinPlaylist),
                      ),
                    ],
                  ),
          ),
        );
      }
    }

    final rows = <Widget>[
      // Local: each music folder, then what was downloaded.
      for (final f in folders) _LibraryRow(collection: f, collapsed: widget.collapsed),
      // First, so downloads are easy to find.
      if (!hidden.contains('downloaded') &&
          downloads != null &&
          (show(LibraryFilter.playlists) || _filter == LibraryFilter.downloaded || _filter == LibraryFilter.local))
        _LibraryRow(collection: downloads, collapsed: widget.collapsed),
      if (show(LibraryFilter.playlists)) ...[
        if (widget.collapsed)
          _SimpleRow(
            collapsed: true,
            art: const _IconArt(Icons.add_rounded),
            title: tr.newPlaylist,
            subtitle: tr.newPlaylistSubtitle,
            onTap: () => createPlaylist(context),
          ),
        ...playlistRows,
        if (online != null && !hidden.contains('liked') && online.liked.isNotEmpty)
          _LibraryRow(collection: likedCollection(online.liked), collapsed: widget.collapsed, online: true),
        if (c.library.isNotEmpty) _LibraryRow(collection: c.allSongs, collapsed: widget.collapsed),
        for (final entry in SmartPlaylists.of(c, PlayHistory.instance).entries)
          if (entry.key != SmartList.mostPlayed || !hidden.contains('top'))
            _SimpleRow(
              collapsed: widget.collapsed,
              art: _IconArt(_smartIcon(entry.key)),
              title: entry.value.title,
              subtitle: '${tr.smartPlaylist} • ${entry.value.subtitle}',
              location: Locations.collection(entry.value),
              onTap: () => shell.openCollection(entry.value),
            ),
        if (!PlayHistory.instance.isEmpty)
          _SimpleRow(
            collapsed: widget.collapsed,
            art: const _IconArt(Icons.insights_rounded),
            title: tr.yourListeningStats,
            subtitle: tr.yourListeningStatsSubtitle,
            location: Locations.stats,
            onTap: () => shell.open(const ListeningStatsPage(), location: Locations.stats),
          ),
      ],
    ];
    // Albums and artists (there can be thousands) are made as they scroll into view.
    final after = <Widget>[
      if (online != null && show(LibraryFilter.artists))
        for (final a in online.artists)
          _SimpleRow(
            collapsed: widget.collapsed,
            art: Artwork(track: playlistCover(a), size: 48, circle: true),
            title: a.title,
            subtitle: '${tr.artist} • YouTube Music',
            online: true,
            location: Locations.remotePlaylist(a.id),
            onTap: () => openRemotePlaylist(context, a),
          ),
    ];
    // The two invitations are taller than a row, so they sit apart from the rows' fixed height.
    final prompts = <Widget>[
      if (!widget.dense &&
          !widget.collapsed &&
          !account.isSignedIn &&
          Features.youtubeSignIn &&
          show(LibraryFilter.playlists))
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
          child: _Prompt(
            title: tr.yourYouTubeMusic,
            body: tr.yourYouTubeMusicBody,
            button: tr.signInWithGoogle,
            onPressed: account.connecting ? null : () => signInToYoutubeMusic(context),
          ),
        ),
      if (!widget.dense && !widget.collapsed && c.library.isEmpty && Features.localLibrary)
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
          child: _Prompt(
            title: tr.musicOnDevice,
            body: tr.musicOnDeviceBody,
            button: tr.addSongs,
            onPressed: shell.addFiles,
          ),
        ),
    ];

    final headerTitle = Row(
      children: [
        Icon(Icons.library_music_rounded, color: AppColors.textSecondary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            tr.yourLibrary,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: (widget.dense ? text.titleMedium : text.headlineSmall)?.copyWith(
              fontWeight: FontWeight.w800,
              color: widget.dense ? AppColors.textSecondary : null,
            ),
          ),
        ),
      ],
    );
    final actions = <Widget>[
      // The phone layout has Settings as a tab of its own.
      if (!widget.dense && !shell.compact)
        IconButton(
          tooltip: tr.navSettings,
          onPressed: () => shell.open(const SettingsPage()),
          icon: const Icon(Icons.settings_outlined),
        ),
      if (playlistRows.isNotEmpty)
        IconButton(
          tooltip: tr.editPlaylists,
          onPressed: () => setState(() => _editingPlaylists = true),
          icon: const Icon(Icons.edit_outlined),
        ),
      if (playlistRows.length > 1)
        PopupMenuButton<PlaylistOrder>(
          tooltip: tr.sortPlaylists,
          icon: const Icon(Icons.sort_rounded),
          onSelected: prefs.setPlaylistOrder,
          itemBuilder: (_) => [
            for (final (value, label) in [
              (PlaylistOrder.library, tr.playlistLibraryOrder),
              (PlaylistOrder.nameAscending, '${tr.name} A–Z'),
              (PlaylistOrder.nameDescending, '${tr.name} Z–A'),
              (PlaylistOrder.custom, tr.playlistCustomOrder),
            ])
              CheckedPopupMenuItem(value: value, checked: prefs.playlistOrder == value, child: Text(label)),
          ],
        ),
      if (!widget.dense && c.library.isNotEmpty)
        IconButton(
          tooltip: tr.addAllToPlaylist,
          onPressed: () => addToPlaylist(context, c.allSongs.tracks),
          icon: const Icon(Icons.playlist_add_rounded),
        ),
      PopupMenuButton<VoidCallback>(
        // Over the whole window, so a click anywhere (sidebar included) closes it.
        useRootNavigator: true,
        tooltip: tr.add,
        icon: const Icon(Icons.add_rounded),
        onSelected: (action) => action(),
        itemBuilder: (_) => [
          PopupMenuItem(
            value: () => createPlaylist(context),
            child: MenuRow(leading: Icon(Icons.playlist_add_rounded), title: Text(tr.newPlaylist)),
          ),
          if (account.canEdit)
            PopupMenuItem(
              value: () => joinSharedPlaylist(context),
              child: MenuRow(leading: Icon(Icons.group_add_outlined), title: Text(tr.joinSharedPlaylist)),
            ),
          if (Features.playlistImport) ...[
            PopupMenuItem(
              value: () => importPlaylist(context),
              child: MenuRow(leading: Icon(Icons.playlist_add_rounded), title: Text(tr.importPlaylist)),
            ),
            PopupMenuItem(
              value: () => shell.open(const SpotifyPage(), location: Locations.spotify),
              child: MenuRow(leading: Icon(Icons.library_music_outlined), title: Text(tr.spotifyLibrary)),
            ),
          ],
          if (widget.dense && c.library.isNotEmpty)
            PopupMenuItem(
              value: () => addToPlaylist(context, c.allSongs.tracks),
              child: MenuRow(leading: const Icon(Icons.playlist_add_rounded), title: Text(tr.addAllToPlaylist)),
            ),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: shell.addFiles,
            child: MenuRow(leading: Icon(Icons.audio_file_outlined), title: Text(tr.addSongs)),
          ),
          if (shell.addFolder != null)
            PopupMenuItem(
              value: shell.addFolder,
              child: MenuRow(leading: Icon(Icons.folder_open_rounded), title: Text(tr.addFolder)),
            ),
          PopupMenuItem(
            value: shell.importFromYoutube,
            child: MenuRow(leading: Icon(Icons.add_link_rounded), title: Text(tr.importFromYouTube)),
          ),
        ],
      ),
    ];
    final header = Padding(
      padding: EdgeInsets.fromLTRB(widget.collapsed ? 0 : 16, 12, widget.collapsed ? 0 : 8, 4),
      child: widget.collapsed
          ? Center(
              child: IconButton(
                tooltip: tr.yourLibrary,
                onPressed: () => shell.open(const LibraryPage()),
                icon: Icon(Icons.library_music_rounded, color: AppColors.textSecondary),
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final titleSpace = MediaQuery.textScalerOf(context).scale(154);
                if (constraints.maxWidth >= titleSpace + actions.length * 48) {
                  return Row(
                    children: [
                      Expanded(child: headerTitle),
                      ...actions,
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    headerTitle,
                    Wrap(alignment: WrapAlignment.end, children: actions),
                  ],
                );
              },
            ),
    );

    // Very short windows: drop the filter chips so the list keeps some room.
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          // Albums and artists are the device's own music (and the signed-in account's); the web build has playlists.
          if (!widget.collapsed && constraints.maxHeight >= 300 && Features.localLibrary)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final f in LibraryFilter.values)
                    if (f != LibraryFilter.downloaded || downloads != null || _filter == f)
                      FilterChip(
                        visualDensity: widget.dense && constraints.maxWidth < 270 ? VisualDensity.compact : null,
                        label: Text(switch (f) {
                          LibraryFilter.playlists => tr.playlists,
                          LibraryFilter.downloaded => tr.downloaded,
                          LibraryFilter.albums => tr.albums,
                          LibraryFilter.artists => tr.artists,
                          LibraryFilter.local => tr.local,
                        }),
                        selected: _filter == f,
                        onSelected: (on) => setState(() => _filter = on ? f : null),
                      ),
                ],
              ),
            ),
          Expanded(
            child: SmoothScroll(
              builder: (context, scroll) {
                final count = rows.length + local.length + after.length;
                return CustomScrollView(
                  controller: scroll,
                  slivers: [
                    if (count == 0 && (_filter == LibraryFilter.local || (widget.dense && prompts.isEmpty)))
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _filter == LibraryFilter.local ? tr.localEmpty : tr.libraryEmpty,
                            style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
                          ),
                        ),
                      ),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        8,
                        0,
                        8,
                        prompts.isEmpty ? (widget.dense ? 8 : 16) + MediaQuery.paddingOf(context).bottom : 0,
                      ),
                      // Every row is 48 px of art in padding, so the list is laid out from one measured row.
                      sliver: count == 0
                          ? null
                          : SliverPrototypeExtentList.builder(
                              itemCount: count,
                              prototypeItem: _SimpleRow(
                                collapsed: widget.collapsed,
                                art: const _IconArt(Icons.add_rounded),
                                title: tr.newPlaylist,
                                subtitle: tr.newPlaylistSubtitle,
                                onTap: () {},
                              ),
                              itemBuilder: (context, i) => i < rows.length
                                  ? rows[i]
                                  : i < rows.length + local.length
                                  ? _LibraryRow(collection: local[i - rows.length], collapsed: widget.collapsed)
                                  : after[i - rows.length - local.length],
                            ),
                    ),
                    if (prompts.isNotEmpty)
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          8,
                          0,
                          8,
                          (widget.dense ? 8 : 16) + MediaQuery.paddingOf(context).bottom,
                        ),
                        sliver: SliverList.list(children: prompts),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

IconData _smartIcon(SmartList l) => switch (l) {
  SmartList.mostPlayed => Icons.trending_up_rounded,
  SmartList.notPlayedForAWhile => Icons.history_toggle_off_rounded,
  SmartList.recentlyAdded => Icons.library_add_outlined,
  SmartList.recentlyPlayed => Icons.history_rounded,
  SmartList.lossless => Icons.graphic_eq_rounded,
};

class _IconArt extends StatelessWidget {
  const _IconArt(this.icon, {this.flat = false});

  final IconData icon;

  /// Just the icon, no tile behind it: in the narrow rail a column of grey tiles reads as clutter.
  final bool flat;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 48,
    child: flat
        ? Icon(icon, color: AppColors.textSecondary)
        : DecoratedBox(
            decoration: BoxDecoration(color: AppColors.hover, borderRadius: BorderRadius.circular(4)),
            child: Icon(icon, color: AppColors.textPrimary),
          ),
  );
}

/// A library entry that isn't a [Collection] (YouTube Music playlists, "New playlist").
class _SimpleRow extends StatelessWidget {
  const _SimpleRow({
    required this.collapsed,
    required this.art,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.location,
    this.online = false,
    this.action,
  });

  final bool collapsed;
  final Widget art;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? location;
  final bool online;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final shell = ShellScope.of(context);
    final tile = InkWell(
      borderRadius: BorderRadius.circular(6),
      hoverColor: AppColors.tile,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: collapsed
            ? Center(child: art is _IconArt ? _IconArt((art as _IconArt).icon, flat: true) : art)
            : Row(
                children: [
                  art,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (online) ...[const SourceMark(online: true, size: 13), const SizedBox(width: 4)],
                            Expanded(
                              child: Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  ?action,
                ],
              ),
      ),
    );
    final highlighted = location == null
        ? tile
        : SelectedHighlight(history: shell.history, location: location!, child: tile);
    return collapsed ? Tooltip(message: title, child: highlighted) : highlighted;
  }
}

class _LibraryRow extends StatelessWidget {
  const _LibraryRow({
    required this.collection,
    required this.collapsed,
    this.online = false,
    this.action,
    this.folderPlaylist = false,
  });

  final Collection collection;
  final bool collapsed;

  /// A music folder shown among the playlists (`FolderWatch.playlistFolders`).
  final bool folderPlaylist;

  /// A YouTube Music collection (Liked music): marked with a cloud.
  final bool online;
  final Widget? action;

  @override
  Widget build(BuildContext context) => PlayerSelect<(bool, bool)>(
    // Only what this row shows: whether its collection is what's playing.
    select: (c) {
      final here = c.isPlayingFrom(collection);
      return (here, here && c.showsPlaying);
    },
    builder: (context, s, _) => _row(context, playingHere: s.$1, playing: s.$2),
  );

  Widget _row(BuildContext context, {required bool playingHere, required bool playing}) {
    final shell = ShellScope.of(context);
    final text = Theme.of(context).textTheme;
    final isArtist = collection.kind == CollectionKind.artist;
    final art = collection.kind == CollectionKind.folder
        ? _IconArt(Icons.folder_rounded, flat: collapsed)
        : collection.kind == CollectionKind.allSongs
        ? PlaylistArtwork(
            coverKey: collection.coverKey,
            fallback: CoverMosaic(tracks: collection.tracks, size: 48),
            size: 48,
          )
        : Artwork(
            track: PlaylistCovers.instance.coverOr(collection.coverKey, collection.cover),
            size: 48,
            circle: isArtist,
          );

    final tile = InkWell(
      borderRadius: BorderRadius.circular(6),
      hoverColor: AppColors.tile,
      // An artist with songs from YouTube Music opens their YouTube Music page; one from your own files alone, the
      // library's page (as Home's Artists shelf does).
      onTap: isArtist
          ? openHomeArtist(context, PlayerScope.read(context), collection, shell: shell)
          : () => shell.openCollection(collection),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: collapsed
            ? Center(child: art)
            : Row(
                children: [
                  art,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          collection.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: playingHere ? AppColors.accent : AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (online) ...[const SourceMark(online: true, size: 13), const SizedBox(width: 4)],
                            Expanded(
                              child: Text(
                                switch (collection.kind) {
                                  CollectionKind.allSongs ||
                                  CollectionKind.youtube ||
                                  CollectionKind.remote => '${tr.playlist} • ${collection.subtitle}',
                                  CollectionKind.smart => '${tr.smartPlaylist} • ${collection.subtitle}',
                                  CollectionKind.folder =>
                                    '${folderPlaylist ? tr.folderPlaylist : tr.folder} • ${collection.subtitle}',
                                  CollectionKind.playlist => '${tr.playlist} • Riflay • ${collection.subtitle}',
                                  CollectionKind.album => '${tr.album} • ${collection.subtitle}',
                                  CollectionKind.artist || CollectionKind.remoteArtist => tr.artist,
                                },
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (playingHere)
                    Icon(
                      playing ? Icons.volume_up_rounded : Icons.volume_mute_rounded,
                      color: AppColors.accent,
                      size: 18,
                    ),
                  ?action,
                ],
              ),
      ),
    );
    final highlighted = SelectedHighlight(
      history: shell.history,
      location: Locations.collection(collection),
      child: tile,
    );
    return collapsed ? Tooltip(message: collection.title, child: highlighted) : highlighted;
  }
}

class _Prompt extends StatelessWidget {
  const _Prompt({required this.title, required this.body, required this.button, required this.onPressed});

  final String title;
  final String body;
  final String button;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.elevated, borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(body, style: text.bodySmall),
          const SizedBox(height: 14),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.inverse, foregroundColor: AppColors.onInverse),
            onPressed: onPressed,
            child: Text(button),
          ),
        ],
      ),
    );
  }
}

/// Phone tab wrapper around [LibraryList].
class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background,
      child: SafeArea(bottom: false, child: const LibraryList()),
    );
  }
}

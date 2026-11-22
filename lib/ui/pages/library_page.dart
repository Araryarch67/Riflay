import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
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
import '../widgets/track_row.dart' show TrackRow;
import 'listening_stats_page.dart';
import 'settings_index.dart';
import 'settings_page.dart';
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
  const LibraryList({
    super.key,
    this.dense = false,
    this.collapsed = false,
    this.full = false,
    this.initialFilter,
    this.initialQuery = '',
  });

  final bool dense;

  /// Icon-only rail in the medium layout.
  final bool collapsed;
  final bool full;
  final LibraryFilter? initialFilter;
  final String initialQuery;

  @override
  State<LibraryList> createState() => _LibraryListState();
}

class _LibraryListState extends State<LibraryList> {
  bool _editingPlaylists = false;
  late LibraryFilter? _filter = widget.full
      ? widget.initialFilter
      : LibraryFilter.values.asNameMap()[LayoutPrefs.instance.libraryChip];
  late final _search = TextEditingController(text: widget.initialQuery);
  late String _query = widget.initialQuery.trim().toLowerCase();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

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
    bool matches(String title, [String subtitle = '']) =>
        _query.isEmpty || title.toLowerCase().contains(_query) || subtitle.toLowerCase().contains(_query);

    final hidden = LayoutPrefs.instance.hiddenCollections;
    final downloads = c.youtubeDownloads;
    final localCollections = switch (_filter) {
      null when widget.full => c.artists,
      null => c.albumsAndArtists,
      LibraryFilter.albums => c.albums,
      LibraryFilter.artists => c.artists,
      LibraryFilter.downloaded => [
        for (final a in c.albumsAndArtists)
          if (a.tracks.any((t) => t.sourceUrl != null)) a,
      ],
      LibraryFilter.playlists || LibraryFilter.local => const <Collection>[],
    };
    List<Collection> matching(List<Collection> collections) => _query.isEmpty
        ? collections
        : [
            for (final item in collections)
              if (matches(item.title, item.subtitle)) item,
          ];
    final local = matching(localCollections);
    final albums = widget.full && _filter == null ? matching(c.albums) : const <Collection>[];
    final folderPlaylists = show(LibraryFilter.playlists) ? c.folderPlaylists : const <Collection>[];
    final playlistFolders = {for (final folder in folderPlaylists) folder.id};
    final folders = switch (_filter) {
      LibraryFilter.local => c.folders,
      null when widget.full => [
        for (final folder in c.folders)
          if (!playlistFolders.contains(folder.id)) folder,
      ],
      _ => const <Collection>[],
    };

    final prefs = LayoutPrefs.instance;
    final playlistRows = <Widget>[];
    final onlinePlaylistRows = <Widget>[];
    var playlistCount = 0;
    final editing = _editingPlaylists && !widget.collapsed;
    if (show(LibraryFilter.playlists)) {
      final entries = <({String key, String title, bool online, Widget Function(Widget? action) row})>[
        for (final collection in [...c.playlists.map(c.playlistCollection), ...folderPlaylists])
          // A folder playlist has no cover of its own: its folder is its key (for the order and pins).
          if (collection.coverKey ?? (collection.kind == CollectionKind.folder ? 'folder:${collection.id}' : null)
              case final key?)
            (
              key: key,
              title: collection.title,
              online: false,
              row: (action) => _LibraryRow(
                collection: collection,
                collapsed: widget.collapsed,
                folderPlaylist: collection.kind == CollectionKind.folder,
                grid: widget.full && !editing,
                action: action,
              ),
            ),
        for (final p in online?.playlists ?? const [])
          (
            key: PlaylistCovers.remoteKey(p.id),
            title: p.title,
            online: true,
            row: (action) => _SimpleRow(
              collapsed: widget.collapsed,
              art: Artwork(
                track: PlaylistCovers.instance.coverOr(PlaylistCovers.remoteKey(p.id), playlistCover(p)),
                size: widget.full && !editing ? null : 48,
              ),
              title: p.title,
              subtitle: p.count == 0
                  ? '${tr.playlist} • YouTube Music'
                  : '${tr.playlist} • YouTube Music • ${tr.songsCount(p.count)}',
              online: true,
              location: Locations.remotePlaylist(p.id),
              onTap: () => openRemotePlaylist(context, p),
              action: action,
              grid: widget.full && !editing,
            ),
          ),
      ];
      playlistCount = entries.length;
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
        if (!matches(entry.title)) continue;
        final pinned = prefs.pinnedPlaylists.contains(entry.key);
        final destination = widget.full && entry.online ? onlinePlaylistRows : playlistRows;
        destination.add(
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

    final folderRows = <Widget>[
      for (final f in folders)
        if (matches(f.title, f.subtitle)) _LibraryRow(collection: f, collapsed: widget.collapsed, grid: widget.full),
    ];
    final downloadRows = <Widget>[
      if (!hidden.contains('downloaded') &&
          downloads != null &&
          matches(downloads.title, downloads.subtitle) &&
          (show(LibraryFilter.playlists) || _filter == LibraryFilter.downloaded || _filter == LibraryFilter.local))
        _LibraryRow(collection: downloads, collapsed: widget.collapsed, grid: widget.full),
    ];
    final likedRows = <Widget>[
      if (show(LibraryFilter.playlists) &&
          online != null &&
          !hidden.contains('liked') &&
          online.liked.isNotEmpty &&
          matches(tr.likedMusic))
        _LibraryRow(
          collection: likedCollection(online.liked),
          collapsed: widget.collapsed,
          online: true,
          grid: widget.full,
        ),
    ];
    final allSongsRows = <Widget>[
      if (show(LibraryFilter.playlists) && c.library.isNotEmpty && matches(c.allSongs.title, c.allSongs.subtitle))
        _LibraryRow(collection: c.allSongs, collapsed: widget.collapsed, grid: widget.full),
    ];
    final smartRows = <Widget>[
      if (show(LibraryFilter.playlists)) ...[
        for (final entry in SmartPlaylists.of(c, PlayHistory.instance).entries)
          if ((entry.key != SmartList.mostPlayed || !hidden.contains('top')) &&
              matches(entry.value.title, entry.value.subtitle))
            _SimpleRow(
              collapsed: widget.collapsed,
              art: _IconArt(_smartIcon(entry.key)),
              title: entry.value.title,
              subtitle: '${tr.smartPlaylist} • ${entry.value.subtitle}',
              location: Locations.collection(entry.value),
              onTap: () => shell.openCollection(entry.value),
              grid: widget.full,
            ),
        if (!PlayHistory.instance.isEmpty && matches(tr.yourListeningStats))
          _SimpleRow(
            collapsed: widget.collapsed,
            art: const _IconArt(Icons.insights_rounded),
            title: tr.yourListeningStats,
            subtitle: tr.yourListeningStatsSubtitle,
            location: Locations.stats,
            onTap: () => shell.open(const ListeningStatsPage(), location: Locations.stats),
            grid: widget.full,
          ),
      ],
    ];
    final onlineArtistRows = <Widget>[
      if (online != null && show(LibraryFilter.artists))
        for (final a in online.artists)
          if (matches(a.title))
            _SimpleRow(
              collapsed: widget.collapsed,
              art: Artwork(track: playlistCover(a), size: widget.full ? null : 48, circle: true),
              title: a.title,
              subtitle: '${tr.artist} • YouTube Music',
              online: true,
              location: Locations.remotePlaylist(a.id),
              onTap: () => openRemotePlaylist(context, a),
              grid: widget.full,
              artist: true,
            ),
    ];
    final leading = widget.full
        ? onlineArtistRows
        : <Widget>[
            ...folderRows,
            ...downloadRows,
            if (widget.collapsed && show(LibraryFilter.playlists))
              _SimpleRow(
                collapsed: true,
                art: const _IconArt(Icons.add_rounded),
                title: tr.newPlaylist,
                subtitle: tr.newPlaylistSubtitle,
                onTap: () => createPlaylist(context),
              ),
            ...playlistRows,
            ...likedRows,
            ...allSongsRows,
            ...smartRows,
          ];
    final afterLocal = widget.full
        ? <Widget>[
            ...onlinePlaylistRows,
            ...likedRows,
            ...playlistRows,
            ...folderRows,
            ...downloadRows,
            ...allSongsRows,
            if (Features.localLibrary &&
                (_filter == null || _filter == LibraryFilter.local) &&
                matches(tr.musicFolders))
              _SimpleRow(
                collapsed: false,
                art: const _IconArt(Icons.create_new_folder_outlined),
                title: tr.musicFolders,
                subtitle: tr.navSettings,
                grid: true,
                onTap: () {
                  if (SettingsOptions.byId('keepLibrary') case final option?) {
                    openSettingsOption(shell, option);
                  } else {
                    SettingsPlace.library.open(shell);
                  }
                },
              ),
          ]
        : onlineArtistRows;
    final trailing = widget.full ? smartRows : const <Widget>[];
    // The two invitations are taller than a row, so they sit apart from the rows' fixed height.
    final prompts = <Widget>[
      if (_query.isEmpty &&
          !widget.dense &&
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
      if (_query.isEmpty && !widget.dense && !widget.collapsed && c.library.isEmpty && Features.localLibrary)
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

    final desktop = widget.dense || widget.full;
    final headerTitle = Row(
      children: [
        Icon(Icons.library_music_rounded, size: desktop ? 18 : null, color: AppColors.textSecondary),
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
    void openFullLibrary() => shell.open(
      LibraryPage(initialFilter: _filter, initialQuery: _search.text),
      location: Locations.library,
    );

    MenuItemButton item(IconData icon, String label, VoidCallback onPressed) =>
        MenuItemButton(leadingIcon: Icon(icon), onPressed: onPressed, child: Text(label));

    final menu = MenuAnchor(
      useRootOverlay: true,
      style: MenuStyle(shape: WidgetStatePropertyAll(menuShape)),
      menuChildren: [
        if (playlistCount != 0)
          item(Icons.edit_outlined, tr.editPlaylists, () => setState(() => _editingPlaylists = true)),
        if (playlistCount > 1)
          SubmenuButton(
            leadingIcon: const Icon(Icons.sort_rounded),
            menuChildren: [
              for (final (value, label) in [
                (PlaylistOrder.library, tr.playlistLibraryOrder),
                (PlaylistOrder.nameAscending, '${tr.name} A–Z'),
                (PlaylistOrder.nameDescending, '${tr.name} Z–A'),
                (PlaylistOrder.custom, tr.playlistCustomOrder),
              ])
                MenuItemButton(
                  leadingIcon: SizedBox(
                    width: 24,
                    child: prefs.playlistOrder == value ? const Icon(Icons.check) : null,
                  ),
                  onPressed: () => prefs.setPlaylistOrder(value),
                  child: Text(label),
                ),
            ],
            child: Text(tr.sortPlaylists),
          ),
        if (c.library.isNotEmpty)
          item(Icons.playlist_add_rounded, tr.addAllToPlaylist, () => addToPlaylist(context, c.allSongs.tracks)),
        const Divider(height: 8),
        item(Icons.add_rounded, tr.newPlaylist, () => createPlaylist(context)),
        if (SettingsPlace.library.available)
          item(Icons.settings_outlined, tr.manageLibrary, () => SettingsPlace.library.open(shell))
        else ...[
          item(Icons.audio_file_outlined, tr.addSongs, shell.addFiles),
          item(Icons.add_link_rounded, tr.importFromYouTube, shell.importFromYoutube),
          if (widget.full) item(Icons.settings_outlined, tr.navSettings, () => shell.open(const SettingsPage())),
        ],
      ],
      builder: (context, controller, _) => IconButton(
        tooltip: tr.moreOptions,
        iconSize: desktop ? 20 : null,
        icon: const Icon(Icons.more_horiz_rounded),
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
      ),
    );
    Widget search() => SearchBar(
      constraints: const BoxConstraints(minHeight: 40, maxHeight: 40, maxWidth: 248),
      elevation: const WidgetStatePropertyAll(0),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10)),
      textStyle: WidgetStatePropertyAll(text.bodyMedium),
      hintStyle: WidgetStatePropertyAll(text.bodyMedium?.copyWith(color: AppColors.textSecondary)),
      controller: _search,
      hintText: tr.searchYourLibrary,
      leading: const Icon(Icons.search_rounded, size: 18),
      trailing: [
        if (_query.isNotEmpty)
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: tr.clear,
            onPressed: () {
              _search.clear();
              setState(() => _query = '');
            },
            icon: const Icon(Icons.close_rounded, size: 16),
          ),
      ],
      onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
    );
    final header = Padding(
      padding: EdgeInsets.fromLTRB(widget.collapsed ? 0 : 16, 12, widget.collapsed ? 0 : 8, 4),
      child: widget.collapsed
          ? Center(
              child: IconButton(
                tooltip: tr.expandLibrary,
                iconSize: 16,
                onPressed: openFullLibrary,
                icon: const Icon(Icons.open_in_full_rounded),
              ),
            )
          : Row(
              children: [
                Expanded(child: headerTitle),
                if (widget.full)
                  Flexible(
                    child: Align(alignment: AlignmentDirectional.centerEnd, child: search()),
                  ),
                if (widget.dense && shell.history != null)
                  IconButton(
                    tooltip: tr.expandLibrary,
                    iconSize: 16,
                    onPressed: openFullLibrary,
                    icon: const Icon(Icons.open_in_full_rounded),
                  ),
                if (widget.full && shell.history?.canGoBack == true)
                  IconButton(
                    tooltip: tr.restoreLibrarySidebar,
                    iconSize: 16,
                    onPressed: shell.history!.back,
                    icon: const Icon(Icons.close_fullscreen_rounded),
                  ),
                menu,
              ],
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
          if (widget.dense && !widget.collapsed && constraints.maxHeight >= 300)
            Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: search()),
          Expanded(
            child: SmoothScroll(
              builder: (context, scroll) {
                final count = leading.length + local.length + afterLocal.length + albums.length + trailing.length;
                final searchSongs = _query.isNotEmpty && show(LibraryFilter.playlists);
                // Albums and artists are built only as they scroll into view.
                Widget rowAt(BuildContext context, int i) {
                  if (i < leading.length) return leading[i];
                  i -= leading.length;
                  if (i < local.length) {
                    return _LibraryRow(collection: local[i], collapsed: widget.collapsed, grid: widget.full);
                  }
                  i -= local.length;
                  if (i < afterLocal.length) return afterLocal[i];
                  i -= afterLocal.length;
                  if (i < albums.length) return _LibraryRow(collection: albums[i], collapsed: false, grid: true);
                  return trailing[i - albums.length];
                }

                return CustomScrollView(
                  controller: scroll,
                  slivers: [
                    if (searchSongs)
                      _LibrarySongSearch(
                        player: c,
                        remote: online,
                        query: _query,
                        grid: widget.full,
                        hasCollections: count > 0,
                      ),
                    if (!searchSongs &&
                        count == 0 &&
                        (_query.isNotEmpty ||
                            _filter == LibraryFilter.local ||
                            ((widget.dense || widget.full) && prompts.isEmpty)))
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _query.isNotEmpty
                                ? tr.noLibraryMatches
                                : _filter == LibraryFilter.local
                                ? tr.localEmpty
                                : tr.libraryEmpty,
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
                          : widget.full
                          ? SliverGrid.builder(
                              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 208 * prefs.coverSize.scale,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                childAspectRatio: .79,
                              ),
                              itemCount: count,
                              itemBuilder: rowAt,
                            )
                          : SliverPrototypeExtentList.builder(
                              itemCount: count,
                              prototypeItem: _SimpleRow(
                                collapsed: widget.collapsed,
                                art: const _IconArt(Icons.add_rounded),
                                title: tr.newPlaylist,
                                subtitle: tr.newPlaylistSubtitle,
                                onTap: () {},
                              ),
                              itemBuilder: rowAt,
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

/// Searches playlist contents lazily and fills remote results in small batches.
class _LibrarySongSearch extends StatefulWidget {
  const _LibrarySongSearch({
    required this.player,
    required this.remote,
    required this.query,
    required this.grid,
    required this.hasCollections,
  });

  final PlayerController player;
  final YoutubeMusicLibrary? remote;
  final String query;
  final bool grid;
  final bool hasCollections;

  @override
  State<_LibrarySongSearch> createState() => _LibrarySongSearchState();
}

class _LibrarySongSearchState extends State<_LibrarySongSearch> {
  Timer? _timer;
  int _generation = 0;
  bool _loading = false;
  bool _failed = false;

  List<String> _ids(YoutubeMusicLibrary? library) => [
    for (final playlist in library?.playlists ?? const <RemotePlaylist>[]) playlist.id,
  ];

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant _LibrarySongSearch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.player != oldWidget.player || !listEquals(_ids(widget.remote), _ids(oldWidget.remote))) _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    final generation = ++_generation;
    final account = widget.player.ytMusic;
    final pending = _ids(widget.remote).where((id) => account.cachedPlaylist(id) == null).toList();
    _loading = pending.isNotEmpty;
    _failed = false;
    if (_loading) _timer = Timer(const Duration(milliseconds: 250), () => _load(pending, account, generation));
  }

  Future<void> _load(List<String> pending, YoutubeMusicAccount account, int generation) async {
    var failed = false;
    const batchSize = 4;
    for (var start = 0; start < pending.length; start += batchSize) {
      final batch = pending.skip(start).take(batchSize);
      await Future.wait(
        batch.map((id) async {
          if (account.cachedPlaylist(id) != null) return;
          try {
            await account.playlistDetails(id);
          } catch (_) {
            failed = true;
          }
        }),
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = start + batchSize < pending.length;
        _failed = failed;
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _generation++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.player;
    final seen = <String>{};
    final candidates = c.library
        .followedBy(c.playlists.expand((playlist) => playlist.tracks))
        .followedBy(widget.remote?.liked ?? const [])
        .followedBy(_ids(widget.remote).expand((id) => c.ytMusic.cachedPlaylist(id)?.tracks ?? const []));
    final songs = [
      for (final track in candidates)
        if ('${track.title} ${track.artist}'.toLowerCase().contains(widget.query) && seen.add(track.id)) track,
    ];
    if (songs.isEmpty && !_loading && !_failed && widget.hasCollections) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    final shell = ShellScope.of(context);
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      sliver: SliverMainAxisGroup(
        slivers: [
          if (songs.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                child: Text(tr.songs, style: Theme.of(context).textTheme.titleMedium),
              ),
            ),
          SliverList.builder(
            itemCount: songs.length,
            itemBuilder: (context, i) {
              final track = songs[i];
              void play() => shell.playAndOpen(() => c.playList(songs, i, from: tr.searchYourLibrary));
              return widget.grid
                  ? TrackRow(track: track, onTap: play, showAlbum: false)
                  : ListTile(
                      dense: true,
                      leading: Artwork(track: track, size: 36),
                      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: play,
                    );
            },
          ),
          if (_loading || _failed || songs.isEmpty)
            SliverToBoxAdapter(
              child: ListTile(
                dense: true,
                title: Text(
                  _loading
                      ? tr.searching
                      : _failed
                      ? tr.ytLoadFailed
                      : tr.noLibraryMatches,
                ),
                trailing: _failed && !_loading
                    ? TextButton(onPressed: () => setState(_schedule), child: Text(tr.tryAgain))
                    : null,
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
    this.grid = false,
    this.artist = false,
    this.playingHere = false,
    this.playing = false,
  });

  final bool collapsed;
  final Widget art;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? location;
  final bool online;
  final Widget? action;
  final bool grid;
  final bool artist;
  final bool playingHere;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final shell = ShellScope.of(context);
    final name = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: text.bodyLarge?.copyWith(
        fontWeight: FontWeight.w600,
        color: playingHere ? AppColors.accent : AppColors.textPrimary,
      ),
    );
    if (grid && artist) {
      return _LibraryGridCard(
        art: art,
        labels: Center(child: name),
        action: null,
        onTap: onTap,
        artist: true,
      );
    }
    final labels = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        name,
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
            if (grid && playingHere)
              Icon(playing ? Icons.volume_up_rounded : Icons.volume_mute_rounded, color: AppColors.accent, size: 18),
          ],
        ),
      ],
    );
    if (grid) {
      return _LibraryGridCard(art: art, labels: labels, action: action, onTap: onTap);
    }
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
                  Expanded(child: labels),
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
    final highlighted = location == null
        ? tile
        : SelectedHighlight(history: shell.history, location: location!, child: tile);
    return collapsed ? Tooltip(message: title, child: highlighted) : highlighted;
  }
}

class _LibraryGridCard extends StatefulWidget {
  const _LibraryGridCard({
    required this.art,
    required this.labels,
    required this.action,
    required this.onTap,
    this.artist = false,
  });

  final Widget art;
  final Widget labels;
  final Widget? action;
  final VoidCallback onTap;
  final bool artist;

  @override
  State<_LibraryGridCard> createState() => _LibraryGridCardState();
}

class _LibraryGridCardState extends State<_LibraryGridCard> {
  final _states = WidgetStatesController();

  @override
  void dispose() {
    _states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final moves = LayoutPrefs.moves && !MediaQuery.disableAnimationsOf(context);
    final artwork = IconTheme.merge(data: const IconThemeData(size: 36), child: widget.art);
    final tile = InkWell(
      statesController: _states,
      onTap: widget.onTap,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: widget.artist
                  ? Center(child: AspectRatio(aspectRatio: 1, child: artwork))
                  : ClipRRect(
                      borderRadius: LayoutPrefs.corner(12),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (moves)
                            ValueListenableBuilder<Set<WidgetState>>(
                              valueListenable: _states,
                              builder: (context, states, child) {
                                final pressed = states.contains(WidgetState.pressed);
                                return AnimatedScale(
                                  scale: pressed ? .97 : (states.contains(WidgetState.hovered) ? 1.04 : 1),
                                  duration: Duration(milliseconds: pressed ? 100 : 180),
                                  curve: Curves.easeOutCubic,
                                  child: child,
                                );
                              },
                              child: artwork,
                            )
                          else
                            artwork,
                          if (widget.action case final action?)
                            PositionedDirectional(
                              end: 4,
                              top: 4,
                              child: Material(
                                color: colors.surfaceContainerHighest,
                                shape: const CircleBorder(),
                                child: action,
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 10),
            widget.labels,
          ],
        ),
      ),
    );
    return widget.artist
        ? Material(type: MaterialType.transparency, child: tile)
        : Card.filled(margin: EdgeInsets.zero, clipBehavior: Clip.antiAlias, child: tile);
  }
}

class _LibraryRow extends StatelessWidget {
  const _LibraryRow({
    required this.collection,
    required this.collapsed,
    this.online = false,
    this.action,
    this.folderPlaylist = false,
    this.grid = false,
  });

  final Collection collection;
  final bool collapsed;

  /// A music folder shown among the playlists (`FolderWatch.playlistFolders`).
  final bool folderPlaylist;
  final bool grid;

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
    final isArtist = collection.kind == CollectionKind.artist;
    final artworkSize = grid ? null : 48.0;
    final art = collection.kind == CollectionKind.folder
        ? _IconArt(Icons.folder_rounded, flat: collapsed)
        : collection.kind == CollectionKind.allSongs
        ? PlaylistArtwork(
            coverKey: collection.coverKey,
            fallback: CoverMosaic(tracks: collection.tracks, size: artworkSize),
            size: artworkSize,
          )
        : Artwork(
            track: PlaylistCovers.instance.coverOr(collection.coverKey, collection.cover),
            size: artworkSize,
            circle: isArtist,
          );
    final subtitle = switch (collection.kind) {
      CollectionKind.allSongs ||
      CollectionKind.youtube ||
      CollectionKind.remote => '${tr.playlist} • ${collection.subtitle}',
      CollectionKind.smart => '${tr.smartPlaylist} • ${collection.subtitle}',
      CollectionKind.radio => collection.kind.label,
      CollectionKind.folder => '${folderPlaylist ? tr.folderPlaylist : tr.folder} • ${collection.subtitle}',
      CollectionKind.playlist => '${tr.playlist} • Riflay • ${collection.subtitle}',
      CollectionKind.album => '${tr.album} • ${collection.subtitle}',
      CollectionKind.artist || CollectionKind.remoteArtist => tr.artist,
    };
    return _SimpleRow(
      collapsed: collapsed,
      art: art,
      title: collection.title,
      subtitle: subtitle,
      location: Locations.collection(collection),
      online: online,
      playingHere: playingHere,
      playing: playing,
      action: action,
      grid: grid,
      artist: isArtist,
      onTap: isArtist
          ? openHomeArtist(context, PlayerScope.read(context), collection, shell: shell)
          : () => shell.openCollection(collection),
    );
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

/// The library tab on a phone and the expanded library on desktop.
class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key, this.initialFilter, this.initialQuery = ''});

  final LibraryFilter? initialFilter;
  final String initialQuery;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background,
      child: SafeArea(
        bottom: false,
        child: LibraryList(
          full: !ShellScope.of(context).compact,
          initialFilter: initialFilter,
          initialQuery: initialQuery,
        ),
      ),
    );
  }
}

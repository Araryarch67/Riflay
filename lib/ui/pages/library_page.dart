import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../../platform/features.dart';
import '../../services/beta_features.dart';
import '../../services/language.dart';
import '../../services/play_history.dart';
import '../../services/player_controller.dart';
import '../../services/smart_playlists.dart';
import '../../services/youtube_music_account.dart';
import '../ytmusic_edit.dart';
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
/// rest of the library too.
enum LibraryFilter { playlists, downloaded, albums, artists }

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
  LibraryFilter? _filter;

  @override
  Widget build(BuildContext context) {
    // The library and the YouTube Music account, not every change of what's
    // playing: this list sits in the sidebar the whole time.
    final c = PlayerScope.identity(context);
    return ListenableBuilder(
      listenable: Listenable.merge([c.libraryRevision, c.ytMusic, BetaFeatures.instance, PlayHistory.instance]),
      builder: (context, _) => _build(context, c, c.ytMusic.libraryNow),
    );
  }

  Widget _build(BuildContext context, PlayerController c, YoutubeMusicLibrary? online) {
    final shell = ShellScope.of(context);
    final text = Theme.of(context).textTheme;
    final account = c.ytMusic;
    bool show(LibraryFilter f) => _filter == null || _filter == f;

    final downloads = c.youtubeDownloads;
    final local = switch (_filter) {
      null => c.albumsAndArtists,
      LibraryFilter.albums => c.albums,
      LibraryFilter.artists => c.artists,
      LibraryFilter.downloaded => [
        for (final a in c.albumsAndArtists)
          if (a.tracks.any((t) => t.sourceUrl != null)) a,
      ],
      LibraryFilter.playlists => const <Collection>[],
    };

    final rows = <Widget>[
      // First, so downloads are easy to find.
      if (downloads != null && (show(LibraryFilter.playlists) || _filter == LibraryFilter.downloaded))
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
        for (final p in c.playlists) _LibraryRow(collection: c.playlistCollection(p), collapsed: widget.collapsed),
        if (online != null) ...[
          if (online.liked.isNotEmpty)
            _LibraryRow(collection: likedCollection(online.liked), collapsed: widget.collapsed, online: true),
          for (final p in online.playlists)
            _SimpleRow(
              collapsed: widget.collapsed,
              art: Artwork(track: playlistCover(p), size: 48),
              title: p.title,
              subtitle: p.count == 0
                  ? '${tr.playlist} • YouTube Music'
                  : '${tr.playlist} • YouTube Music • ${tr.songsCount(p.count)}',
              online: true,
              location: Locations.remotePlaylist(p.id),
              onTap: () => openRemotePlaylist(context, p),
            ),
        ],
        if (c.library.isNotEmpty) _LibraryRow(collection: c.allSongs, collapsed: widget.collapsed),
        for (final entry in SmartPlaylists.of(c, PlayHistory.instance).entries)
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

    final header = Padding(
      padding: EdgeInsets.fromLTRB(widget.collapsed ? 0 : 16, 12, widget.collapsed ? 0 : 8, 4),
      child: widget.collapsed
          // Centred over the rows; New playlist is already the first of them.
          ? Center(
              child: IconButton(
                tooltip: tr.yourLibrary,
                onPressed: () => shell.open(const LibraryPage()),
                icon: Icon(Icons.library_music_rounded, color: AppColors.textSecondary),
              ),
            )
          : Row(
              children: [
                Icon(Icons.library_music_rounded, color: AppColors.textSecondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    tr.yourLibrary,
                    style: (widget.dense ? text.titleMedium : text.headlineSmall)?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: widget.dense ? AppColors.textSecondary : null,
                    ),
                  ),
                ),
                // The phone layout has Settings as a tab of its own.
                if (!widget.dense && !shell.compact)
                  IconButton(
                    tooltip: tr.navSettings,
                    onPressed: () => shell.open(const SettingsPage()),
                    icon: const Icon(Icons.settings_outlined),
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
                        label: Text(switch (f) {
                          LibraryFilter.playlists => tr.playlists,
                          LibraryFilter.downloaded => tr.downloaded,
                          LibraryFilter.albums => tr.albums,
                          LibraryFilter.artists => tr.artists,
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
                    if (widget.dense && count == 0 && prompts.isEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            tr.libraryEmpty,
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
  });

  final bool collapsed;
  final Widget art;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? location;
  final bool online;

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
  const _LibraryRow({required this.collection, required this.collapsed, this.online = false});

  final Collection collection;
  final bool collapsed;

  /// A YouTube Music collection (Liked music): marked with a cloud.
  final bool online;

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
    final art = collection.kind == CollectionKind.allSongs
        ? CoverMosaic(tracks: collection.tracks, size: 48)
        : Artwork(track: collection.cover, size: 48, circle: isArtist);

    final tile = InkWell(
      borderRadius: BorderRadius.circular(6),
      hoverColor: AppColors.tile,
      onTap: () => shell.openCollection(collection),
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
                                  CollectionKind.playlist => '${tr.playlist} • Riflay • ${collection.subtitle}',
                                  CollectionKind.album => '${tr.album} • ${collection.subtitle}',
                                  CollectionKind.artist => tr.artist,
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

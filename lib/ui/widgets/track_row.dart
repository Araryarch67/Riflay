import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/artist_channels.dart';
import '../../services/language.dart';
import '../../models/track.dart';
import '../../platform/browser_files.dart';
import '../../platform/features.dart';
import '../../platform/network.dart';
import '../../services/audio_engine.dart';
import '../../services/layout_prefs.dart';
import '../../services/flac_convert.dart';
import '../../services/listen_together/listen_together.dart';
import '../../services/metadata.dart';
import '../../services/player_controller.dart';
import '../../services/soundcloud.dart' show SoundcloudKind;
import '../../services/youtube_stream.dart';
import '../download_editor.dart';
import '../download_options.dart';
import '../flac_convert_dialog.dart';
import '../shell_scope.dart';
import '../soundcloud_pages.dart' show openSoundcloud;
import '../tag_editor.dart';
import '../../services/youtube_music_account.dart';
import '../../services/ytmusic_web.dart' show WebResultKind;
import '../pages/youtube_music_page.dart' show openRemotePlaylist, RemoteCollectionPage;
import '../ytmusic_edit.dart';
import '../player/player_parts.dart' show shareTrack;
import '../theme.dart';
import 'app_dialog.dart';
import 'controls.dart';
import 'menus.dart';
import 'stats_for_nerds.dart';
import 'track_selection.dart';

/// How a row of [width] px shows its download button.
enum RowDownload { full, compact, none }

/// Full from 300 px, an icon-only 40 px one from 240 px, none below.
RowDownload downloadButtonFor(double width) => width >= 300
    ? RowDownload.full
    : width >= 240
    ? RowDownload.compact
    : RowDownload.none;

/// One song in a list: number (or play icon on hover), cover, title, album, duration.
class TrackRow extends StatefulWidget {
  const TrackRow({
    super.key,
    required this.track,
    required this.onTap,
    this.index,
    this.showAlbum = true,
    this.showArtwork = true,
  });

  final Track track;

  /// Null for a shared queue that only the host controls. Row menus remain available.
  final VoidCallback? onTap;

  /// 1-based position shown in the leading column; null hides the column.
  final int? index;
  final bool showAlbum;
  final bool showArtwork;

  /// Row bodies built, and hover-only leaf rebuilds, for tests.
  @visibleForTesting
  static int debugRowBuilds = 0;
  @visibleForTesting
  static int debugHoverBuilds = 0;

  @override
  State<TrackRow> createState() => _TrackRowState();
}

class _TrackRowState extends State<TrackRow> {
  /// Whether the pointer is over the row. Only the few things that show it listen
  /// ([_Hovering]): moving over a long list used to rebuild each row it crossed,
  /// cover, texts and menu button included.
  final _hover = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _hover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    // Rebuilt when this row's own state changes (it starts or stops playing, it
    // gets downloaded), not for every change of the player: on a song change
    // only two rows of a long list differ.
    return PlayerSelect<(bool, bool, bool)>(
      select: (c) {
        final current = c.currentTrack?.id == t.id;
        return (current, current && c.showsPlaying, t.streams && !c.isOffline(t));
      },
      builder: (context, s, _) => _row(context, isCurrent: s.$1, playing: s.$2, online: s.$3),
    );
  }

  Widget _row(BuildContext context, {required bool isCurrent, required bool playing, required bool online}) {
    TrackRow.debugRowBuilds++;
    final c = PlayerScope.read(context);
    final shell = ShellScope.of(context);
    final text = Theme.of(context).textTheme;
    final t = widget.track;
    final wide = !shell.compact;
    // Settings > Layout > Player > Song that is playing: a filled card instead of coloured text.
    final card = isCurrent && LayoutPrefs.instance.playingRow == PlayingRowStyle.card;
    // A page where songs can be picked (see TrackSelection): hold to pick; while picking, a tap picks too.
    final selection = TrackSelectionScope.maybeOf(context);

    Widget? leading;
    if (widget.index != null && wide) {
      leading = SizedBox(
        width: 32,
        child: Center(
          child: _Hovering(
            hover: _hover,
            builder: (context, hover, _) => isCurrent && !hover
                ? EqualizerIcon(playing: playing, size: 14)
                : hover
                ? Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: AppColors.textPrimary, size: 20)
                : Text(
                    '${widget.index}',
                    style: text.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
          ),
        ),
      );
    }

    final body = LayoutBuilder(
      builder: (context, box) => Padding(
        padding: EdgeInsets.symmetric(horizontal: wide ? 12 : 4, vertical: LayoutPrefs.dense(6, 2)),
        child: Row(
          children: [
            if (selection != null) TrackSelectMark(selection: selection, track: t),
            if (leading != null) ...[leading, const SizedBox(width: 12)],
            if (card && leading == null && !widget.showArtwork) ...[
              EqualizerIcon(playing: playing, size: 18, color: AppColors.textPrimary),
              const SizedBox(width: 14),
            ],
            if (widget.showArtwork) ...[
              Artwork(track: t, size: LayoutPrefs.dense(wide ? 40 : 48, wide ? 34 : 40)),
              const SizedBox(width: 12),
            ],
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyLarge?.copyWith(
                      color: isCurrent && !card ? AppColors.accent : AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (isCurrent && !wide && !(card && !widget.showArtwork)) ...[
                        EqualizerIcon(playing: playing, size: 10),
                        const SizedBox(width: 6),
                      ],
                      // Streamed songs: the service they stream from; green pin = downloaded, plays offline.
                      if (t.streams) ...[
                        SourceMark(online: online, source: t.source, size: 14),
                        const SizedBox(width: 4),
                      ],
                      Flexible(
                        child: Text(
                          t.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (wide && widget.showAlbum && shell.width > 900) ...[
              const SizedBox(width: 16),
              Expanded(
                flex: 4,
                child: Text(
                  t.album ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
                ),
              ),
            ],
            if (wide)
              SizedBox(
                width: 56,
                child: Text(
                  t.duration == null ? '' : formatDuration(t.duration),
                  textAlign: TextAlign.right,
                  style: text.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            // Streamed songs: download right here (ring while it runs, a check once saved). Under 300 px an
            // icon-only one; on a row too narrow even for that, only the menu has it.
            if (t.isRemote && downloadButtonFor(box.maxWidth) != RowDownload.none)
              downloadButtonFor(box.maxWidth) == RowDownload.compact
                  ? SizedBox.square(
                      dimension: 40,
                      child: FittedBox(child: DownloadButton(track: t)),
                    )
                  : DownloadButton(track: t),
            // Shown on hover on a wide row; the button itself is made once.
            if (wide)
              _Hovering(
                hover: _hover,
                child: TrackMenuButton(track: t),
                builder: (context, hover, child) => Opacity(opacity: hover ? 1 : 0, child: child),
              )
            else
              TrackMenuButton(track: t),
          ],
        ),
      ),
    );

    return MouseRegion(
      onEnter: (_) => _hover.value = true,
      onExit: (_) => _hover.value = false,
      // The only part that changes with hover: the tint and what a tap does.
      child: ListenableBuilder(
        listenable: selection == null ? _hover : Listenable.merge([_hover, selection]),
        child: body,
        builder: (context, child) {
          TrackRow.debugHoverBuilds++;
          final hover = _hover.value;
          final picking = selection?.active ?? false;
          final picked = selection?.contains(t) ?? false;
          return Material(
            color: picked
                ? AppColors.accent.withValues(alpha: 0.18)
                : card
                ? AppColors.accent.withValues(alpha: 0.3)
                : (hover ? AppColors.tile : Colors.transparent),
            borderRadius: LayoutPrefs.corner(card ? 16 : 6),
            child: InkWell(
              borderRadius: LayoutPrefs.corner(card ? 16 : 6),
              hoverColor: Colors.transparent,
              onTap: picking
                  ? () => selection!.toggle(t)
                  : widget.onTap == null
                  ? null
                  : (isCurrent && wide && hover ? c.togglePlay : widget.onTap),
              onLongPress: selection == null ? null : () => selection.toggle(t),
              child: child,
            ),
          );
        },
      ),
    );
  }
}

/// A small leaf that rebuilds with the row's hover and nothing else.
class _Hovering extends StatelessWidget {
  const _Hovering({required this.hover, required this.builder, this.child});

  final ValueListenable<bool> hover;
  final Widget? child;
  final Widget Function(BuildContext context, bool hover, Widget? child) builder;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: hover,
    child: child,
    builder: (context, value, child) {
      TrackRow.debugHoverBuilds++;
      return builder(context, value, child);
    },
  );
}

/// Opens [track]'s artist. A song from YouTube Music, streamed or downloaded, opens the artist's page there
/// (their albums and singles, About, Follow), never the few downloads of theirs the library holds; a file of
/// your own opens the library's artist. [name] picks one of a song's several artists (the first when null).
/// Null when there's none to open. [host] must outlive the caller.
VoidCallback? openArtist(BuildContext host, PlayerController c, Track track, {ShellScope? shell, String? name}) {
  final navigation = shell ?? ShellScope.of(host);
  final names = track.artists;
  final who = name ?? names.firstOrNull;
  // The channel YouTube Music gives is the first artist's.
  final id = who == names.firstOrNull ? track.artistId : null;
  final fromYoutube = track.isRemote || track.isDownload;
  final local = c.artistNamed(who ?? '');
  // A SoundCloud track: its uploader's page there (the profile the track came from).
  if (track.soundcloudId != null && id != null) {
    return () => openSoundcloud(host, kind: SoundcloudKind.user, id: id, title: who ?? track.artist, shell: navigation);
  }
  void remote(String id, String title) => openRemotePlaylist(
    host,
    RemotePlaylist(id: id, browseId: id, title: title, count: 0),
    shell: navigation,
    account: c.ytMusic,
  );
  if (fromYoutube && who != null) {
    if (id != null) return () => remote(id, who);
    // Known by name only (a second artist, an older download): their channel is looked up, once per name.
    return () async {
      final found = await ArtistChannels.find(c.ytMusic, who);
      if (found != null) return remote(found, who);
      // Offline, or no artist of exactly that name: what the library has of them, else a search.
      if (local != null) return navigation.openCollection(local);
      navigation.open(
        RemoteCollectionPage(
          title: who,
          load: () async {
            final matches = await c.ytMusic.searchOnly(who, WebResultKind.artist);
            final artist =
                matches.where((a) => a.title.toLowerCase() == who.toLowerCase()).firstOrNull ?? matches.firstOrNull;
            if (artist == null) throw StateError('No artist result for $who');
            return Collection(
              kind: CollectionKind.remote,
              title: artist.title,
              subtitle: tr.artist,
              tracks: await c.ytMusic.collectionTracks(artist),
            );
          },
        ),
        location: 'artist:$who',
      );
    };
  }
  if (local != null) return () => navigation.openCollection(local);
  return id == null ? null : () => remote(id, who ?? track.artist);
}

/// Entries this menu can leave out, for a host surface that already lists them
/// itself (the player's More sheet has Add to playlist and the download states).
enum TrackMenuEntry { addToPlaylist, download, share }

/// The ⋯ menu of a song: play next, add to playlist, like, download, go to artist…
class TrackMenuButton extends StatelessWidget {
  const TrackMenuButton({
    super.key,
    required this.track,
    this.visible = true,
    this.color,
    this.nowPlaying = false,
    this.hide = const {},
  });

  static Future<void> _queued(BuildContext context, Future<void> change, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    await change;
    messenger.showSnackBar(SnackBar(content: Text(done), duration: const Duration(seconds: 2)));
  }

  /// A guest of a session whose host takes suggestions.
  static bool _canSuggest(PlayerController c) {
    final s = ListenTogether.of(c);
    return s.role == ListenRole.guest && s.suggestionsAllowed;
  }

  /// Queues [tracks] for download. A plain tap follows Settings (and asks only if
  /// "Ask every time" is on); [force] always asks, for "Download as…".
  static Future<void> download(BuildContext host, PlayerController c, List<Track> tracks, {bool force = false}) async {
    final one = tracks.length == 1 ? tracks.first : null;
    final choice = await chooseDownload(host, force: force, videoId: one?.videoId, track: one);
    if (choice == null) return;
    c.youtube.enqueueTracks(tracks, choice: choice);
  }

  /// The web build: [track]'s audio as a browser download (see [Features.saveToDevice]).
  static void saveToDevice(BuildContext host, Track track) {
    final url = webSaveUri(track.videoId!, [if (track.artist.isNotEmpty) track.artist, track.title].join(' - '));
    if (url == null) return;
    BrowserFiles.saveUrl(url, track.title);
    ScaffoldMessenger.of(host).showSnackBar(SnackBar(content: Text(tr.savingToDevice(track.title))));
  }

  final Track track;
  final bool visible;
  final Color? color;

  /// In a now-playing view: adds Detail stats and Signal path.
  final bool nowPlaying;

  /// Entries the host already lists, so one menu does not repeat another.
  final Set<TrackMenuEntry> hide;

  @override
  Widget build(BuildContext context) {
    final c = PlayerScope.read(context);
    final shell = ShellScope.of(context);
    return Opacity(
      opacity: visible ? 1 : 0,
      child: PopupMenuButton<void>(
        // Over the whole window, so a click anywhere (sidebar included) closes it.
        useRootNavigator: true,
        tooltip: tr.moreOptionsFor(track.title),
        icon: Icon(Icons.more_horiz_rounded, color: color),
        // The row can be rebuilt away while the menu is open (a list refreshing),
        // so actions run against the navigator's context, which outlives it.
        // Worked out when the menu opens, not for every row on every rebuild.
        itemBuilder: (_) {
          // The menu is open: the download choices are likely next, so their formats are looked up now.
          if (track.isRemote && track.videoId != null) YoutubeStream.prefetchDownloadCandidates(track.videoId!);
          final host = Navigator.of(context).context;
          final editScope = PlaylistEditScope.maybeOf(context);
          final selection = TrackSelectionScope.maybeOf(context);
          final artist = openArtist(host, c, track, shell: shell);
          final album = c.albumOf(track);
          // A song downloaded from YouTube, or the download of a streamed one: "Edit" with the artist locked.
          final downloaded = track.isRemote ? c.downloadedCopy(track) : (track.isDownload ? track : null);
          // A streamed song that was downloaded converts its file; one with no file has nothing to convert.
          final convertible = downloaded ?? track;
          return [
            PopupMenuItem(
              enabled: ListenTogether.of(c).role != ListenRole.guest || (_canSuggest(c) && track.videoId != null),
              onTap: () => _canSuggest(c)
                  ? _queued(host, ListenTogether.of(c).suggest(track), tr.toastRequestedNext)
                  : _queued(host, c.playNext([track]), tr.toastPlaysNext),
              child: MenuRow(leading: const Icon(Icons.playlist_play_rounded), title: Text(tr.playNext)),
            ),
            PopupMenuItem(
              onTap: () => _queued(host, c.addToQueue([track]), tr.toastAddedToQueue),
              child: MenuRow(leading: const Icon(Icons.queue_music_rounded), title: Text(tr.addToQueue)),
            ),
            // A song by several artists: one entry each, so any of them can be opened.
            if (track.artists.length > 1) ...[
              for (final name in track.artists)
                if (openArtist(host, c, track, shell: shell, name: name) case final open?)
                  PopupMenuItem(
                    onTap: open,
                    child: MenuRow(
                      leading: const Icon(Icons.person_outline_rounded),
                      title: Text(tr.goToNamedArtist(name)),
                    ),
                  ),
            ] else if (artist != null)
              PopupMenuItem(
                onTap: artist,
                child: MenuRow(leading: const Icon(Icons.person_outline_rounded), title: Text(tr.goToArtist)),
              ),
            if (album != null)
              PopupMenuItem(
                onTap: () => shell.openCollection(album),
                child: MenuRow(leading: const Icon(Icons.album_outlined), title: Text(tr.goToAlbum)),
              ),
            // The song's YouTube Music link, or its name and artist for a file here.
            if (!hide.contains(TrackMenuEntry.share))
              PopupMenuItem(
                onTap: () => shareTrack(host, track),
                child: MenuRow(leading: const Icon(Icons.share_outlined), title: Text(tr.share)),
              ),
            if (!hide.contains(TrackMenuEntry.addToPlaylist))
              PopupMenuItem(
                onTap: () => addToPlaylist(host, [track]),
                child: MenuRow(leading: const Icon(Icons.playlist_add_rounded), title: Text(tr.addToPlaylist)),
              ),
            if (selection != null)
              PopupMenuItem(
                onTap: () => selection.toggle(track),
                child: MenuRow(
                  leading: const Icon(Icons.check_circle_outline_rounded),
                  title: Text(selection.contains(track) ? tr.unselect : tr.select),
                ),
              ),
            if (editScope?.canRemove(track) ?? false)
              PopupMenuItem(
                onTap: () => editScope!.remove(host, track),
                child: MenuRow(
                  leading: const Icon(Icons.playlist_remove_rounded),
                  title: Text(tr.removeFromThisPlaylist),
                ),
              ),
            if (track.soundcloudId != null) ...[
              PopupMenuItem(
                onTap: () => c.startRadio(track),
                child: MenuRow(leading: const Icon(Icons.radio_rounded), title: Text(tr.startRadio)),
              ),
              // A SoundCloud track streams; saving it lists it in the library beside the songs on this device.
              if (c.inLibrary(track))
                PopupMenuItem(
                  onTap: () => _queued(host, c.removeTrack(track), tr.removedFromLibrary),
                  child: MenuRow(
                    leading: const Icon(Icons.remove_circle_outline_rounded),
                    title: Text(tr.removeFromLibrary),
                  ),
                )
              else
                PopupMenuItem(
                  onTap: () => _queued(host, c.saveToLibrary([track]), tr.savedToLibrary),
                  child: MenuRow(leading: const Icon(Icons.library_add_outlined), title: Text(tr.saveToLibrary)),
                ),
            ] else if (track.isRemote) ...[
              if (c.ytMusic.canEdit)
                PopupMenuItem(
                  onTap: () => toggleLike(host, track),
                  child: MenuRow(
                    leading: Icon(c.ytMusic.isLiked(track) ? Icons.favorite_rounded : Icons.favorite_border_rounded),
                    title: Text(c.ytMusic.isLiked(track) ? tr.removeFromLiked : tr.addToLiked),
                  ),
                ),
              PopupMenuItem(
                onTap: () => c.startRadio(track),
                child: MenuRow(leading: const Icon(Icons.radio_rounded), title: Text(tr.startRadio)),
              ),
              if (_canSuggest(c))
                PopupMenuItem(
                  onTap: () => ListenTogether.of(c).suggest(track),
                  child: MenuRow(
                    leading: const Icon(Icons.group_add_outlined),
                    title: Text(tr.addToHostQueue(ListenTogether.of(c).hostName ?? tr.theHost)),
                  ),
                ),
              if (c.downloadedCopy(track) == null && Features.downloads && !hide.contains(TrackMenuEntry.download)) ...[
                PopupMenuItem(
                  onTap: () => download(host, c, [track]),
                  child: MenuRow(leading: const Icon(Icons.download_rounded), title: Text(tr.downloadForOffline)),
                ),
                PopupMenuItem(
                  onTap: () => download(host, c, [track], force: true),
                  child: MenuRow(leading: const Icon(Icons.tune_rounded), title: Text(tr.downloadAs)),
                ),
              ],
              if (track.isRemote && Features.saveToDevice && !hide.contains(TrackMenuEntry.download))
                PopupMenuItem(
                  onTap: () => saveToDevice(host, track),
                  child: MenuRow(leading: const Icon(Icons.download_rounded), title: Text(tr.saveToDevice)),
                ),
              if (downloaded != null)
                PopupMenuItem(
                  onTap: () => showDownloadEditor(host, downloaded, compact: shell.compact),
                  child: MenuRow(leading: const Icon(Icons.edit_outlined), title: Text(tr.edit)),
                ),
            ] else ...[
              if (downloaded != null)
                PopupMenuItem(
                  onTap: () => showDownloadEditor(host, downloaded, compact: shell.compact),
                  child: MenuRow(leading: const Icon(Icons.edit_outlined), title: Text(tr.edit)),
                )
              else if (Metadata.canEditTags(track))
                PopupMenuItem(
                  onTap: () => showTagEditor(host, track),
                  child: MenuRow(leading: const Icon(Icons.edit_outlined), title: Text(tr.editInfo)),
                ),
              PopupMenuItem(
                onTap: () => c.removeTrack(track),
                child: MenuRow(
                  leading: const Icon(Icons.remove_circle_outline_rounded),
                  title: Text(tr.removeFromLibrary),
                ),
              ),
            ],
            if (c.recentlyPlayed.any((recent) => recent.id == track.id))
              PopupMenuItem(
                onTap: () => c.removeFromRecentlyPlayed(track),
                child: MenuRow(leading: const Icon(Icons.history_rounded), title: Text(tr.removeFromRecentlyPlayed)),
              ),
            if (downloaded != null)
              PopupMenuItem(
                onTap: () => confirmDeleteDownload(host, c, downloaded),
                child: MenuRow(leading: const Icon(Icons.delete_outline_rounded), title: Text(tr.deleteDownload)),
              ),
            if (FlacConvert.available(convertible))
              PopupMenuItem(
                onTap: () => showFlacConvert(host, c, [convertible]),
                child: MenuRow(leading: const Icon(Icons.graphic_eq_rounded), title: Text(tr.convertToFlac)),
              ),
            if (nowPlaying && AudioEngine.supported) ...[
              const PopupMenuDivider(),
              for (final e in NowPlayingCover.menuItems())
                PopupMenuItem(onTap: () => NowPlayingCover.handle(host, e.value), child: e.child),
            ],
          ];
        },
      ),
    );
  }
}

/// Asks first, then deletes a downloaded song: out of the library and off this device.
Future<void> confirmDeleteDownload(BuildContext context, PlayerController c, Track download) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final ok = await confirmDialog(
    context,
    title: tr.deleteDownloadQuestion,
    body: tr.deleteDownloadBody(download.title),
    confirmLabel: tr.delete,
    destructive: true,
  );
  if (!ok) return;
  final failed = await c.deleteDownloads([download]);
  messenger?.showSnackBar(SnackBar(content: Text(failed > 0 ? tr.removedFileNotDeleted : tr.downloadDeleted)));
}

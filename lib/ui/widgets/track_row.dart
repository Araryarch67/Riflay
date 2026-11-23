import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

import 'glass_toast.dart';

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
import '../../services/smart_merge.dart';
import '../../services/soundcloud.dart' show SoundcloudKind;
import '../../services/video_mode.dart';
import '../../services/youtube_stream.dart';
import '../download_editor.dart';
import '../download_options.dart';
import '../download_source_dialog.dart';
import '../flac_convert_dialog.dart';
import '../shell_scope.dart';
import '../soundcloud_pages.dart' show openSoundcloud;
import '../tag_editor.dart';
import '../../services/youtube_music_account.dart';
import '../../services/ytmusic_web.dart' show WebResultKind;
import '../pages/youtube_music_page.dart' show openRemotePlaylist, RemoteCollectionPage;
import '../ytmusic_edit.dart';
import '../player/player_parts.dart' show shareTrack, copySongTitle;
import '../theme.dart';
import '../playlist_tools.dart';
import 'item_picker.dart';
import 'app_dialog.dart';
import 'audio_source_picker.dart';
import 'controls.dart';
import 'marquee_text.dart';
import 'menus.dart';
import 'stats_for_nerds.dart';
import 'track_selection.dart';
import 'frosted.dart';

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
    this.currentOccurrence,
    this.pinned = false,
    this.onTogglePin,
    this.marquee = false,
  });

  final Track track;

  /// Title and artist scroll when they don't fit, instead of being cut short (a narrow panel).
  final bool marquee;

  /// Null for a shared queue that only the host controls. Row menus remain available.
  final VoidCallback? onTap;

  /// 1-based position shown in the leading column; null hides the column.
  final int? index;
  final bool showAlbum;
  final bool showArtwork;

  /// Queue entries are occurrences, so an upcoming copy must not inherit the
  /// current song's highlight or pause-on-click behavior just because IDs match.
  final bool? currentOccurrence;
  final bool pinned;
  final VoidCallback? onTogglePin;

  /// Row bodies built, and hover-only leaf rebuilds, for tests.
  @visibleForTesting
  static int debugRowBuilds = 0;
  @visibleForTesting
  static int debugHoverBuilds = 0;

  @override
  State<TrackRow> createState() => _TrackRowState();
}

class _TrackRowState extends State<TrackRow> {
  /// Whether the pointer is over the row. Only the few things that show it listen ([_Hovering]), so moving over a
  /// long list doesn't rebuild every row it crosses.
  final _hover = ValueNotifier<bool>(false);
  double _swipeDistance = 0;

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
    return PlayerSelect<(bool, bool, bool, String?)>(
      select: (c) {
        final current = widget.currentOccurrence ?? (c.currentTrack?.id == t.id);
        return (current, current && c.showsPlaying, t.streams && !c.isOffline(t), c.qualityOf(t));
      },
      builder: (context, s, _) => _row(context, isCurrent: s.$1, playing: s.$2, online: s.$3, quality: s.$4),
    );
  }

  Widget _row(
    BuildContext context, {
    required bool isCurrent,
    required bool playing,
    required bool online,
    String? quality,
  }) {
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
                  if (widget.marquee)
                    MarqueeText(
                      t.title,
                      style: text.bodyLarge?.copyWith(
                        color: isCurrent && !card ? AppColors.accent : AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  else
                    Text(
                      t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyLarge?.copyWith(
                        color: isCurrent && !card ? AppColors.accent : AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                      // The line keeps the app font's height: a symbol drawn from a taller fallback font ("♡" from
                      // Segoe UI Symbol on Windows) made the row a pixel too tall for its room.
                      strutStyle: _line(text.bodyLarge),
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
                        // Smart merge: one badge for the song's service and the one its sound comes from.
                        if (online)
                          SmartMergeMark(
                            track: t,
                            fallback: SourceMark(online: true, source: t.source, size: 14),
                          )
                        else
                          SourceMark(online: false, source: t.source, size: 14),
                        const SizedBox(width: 4),
                      ],
                      Flexible(
                        child: widget.marquee
                            ? MarqueeText(t.artist, style: text.bodyMedium?.copyWith(color: AppColors.textSecondary))
                            : Text(
                                t.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
                                strutStyle: _line(text.bodyMedium),
                              ),
                      ),
                      if (quality != null) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Container(
                            // No vertical padding: with the border it made this line taller than the artist's,
                            // and the row overflowed by a pixel.
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            decoration: BoxDecoration(
                              border: Border.all(color: AppColors.textSecondary.withValues(alpha: 0.4)),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              quality,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.labelSmall?.copyWith(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
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
            if ((t.isRemote || t.monochromeId != null || t.extensionId != null) &&
                Features.downloads &&
                downloadButtonFor(box.maxWidth) != RowDownload.none)
              downloadButtonFor(box.maxWidth) == RowDownload.compact
                  ? SizedBox.square(
                      dimension: 40,
                      child: FittedBox(child: DownloadButton(track: t)),
                    )
                  : DownloadButton(track: t),
            if (widget.pinned)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(Icons.push_pin_rounded, size: 16, color: AppColors.accent),
              ),
            // Shown on hover on a wide row; the button itself is made once.
            if (wide)
              _Hovering(
                hover: _hover,
                child: TrackMenuButton(track: t, pinned: widget.pinned, onTogglePin: widget.onTogglePin),
                builder: (context, hover, child) => Opacity(opacity: hover ? 1 : 0, child: child),
              )
            else
              TrackMenuButton(track: t, pinned: widget.pinned, onTogglePin: widget.onTogglePin),
          ],
        ),
      ),
    );

    final row = MouseRegion(
      onEnter: (_) {
        _hover.value = true;
        SmartMerge.instance.pointerOn(t);
      },
      onExit: (_) {
        _hover.value = false;
        SmartMerge.instance.pointerOff();
      },
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
                  : t.extensionId != null && online
                  ? () async {
                      final download = await confirmDialog(
                        context,
                        title: t.title,
                        body: tr.spotiflacDownloadToPlay,
                        confirmLabel: tr.download,
                      );
                      if (download && context.mounted) await downloadExtensionTracks(context, c, [t]);
                    }
                  : (isCurrent && wide && hover ? c.togglePlay : widget.onTap),
              onLongPress: selection == null ? null : () => selection.toggle(t),
              child: child,
            ),
          );
        },
      ),
    );
    if (wide || widget.onTap == null) return row;
    final edit = PlaylistEditScope.maybeOf(context);
    return GestureDetector(
      supportedDevices: const {PointerDeviceKind.touch, PointerDeviceKind.stylus},
      onHorizontalDragStart: (_) => _swipeDistance = 0,
      onHorizontalDragUpdate: (details) => _swipeDistance += details.primaryDelta ?? 0,
      onHorizontalDragEnd: (_) async {
        if (_swipeDistance.abs() < 48 || selection?.active == true || ListenTogether.of(c).role == ListenRole.guest) {
          return;
        }
        if (_swipeDistance > 0) {
          if (c.canQueue(t)) {
            await TrackMenuButton._queued(context, c.playNext([t]), tr.toastPlaysNext, shell.openQueue);
          }
          return;
        }
        if (edit == null || !edit.canRemove(t)) {
          if (c.canQueue(t)) {
            await TrackMenuButton._queued(context, c.addToQueue([t]), tr.toastAddedToQueue, shell.openQueue);
          }
          return;
        }
        final remove = await showAppSheet<bool>(
          context: context,
          builder: (sheet) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  enabled: c.canQueue(t),
                  leading: const Icon(Icons.queue_music_rounded),
                  title: Text(tr.addToQueue),
                  onTap: () => Navigator.pop(sheet, false),
                ),
                ListTile(
                  leading: const Icon(Icons.playlist_remove_rounded),
                  title: Text(tr.removeFromThisPlaylist),
                  onTap: () => Navigator.pop(sheet, true),
                ),
              ],
            ),
          ),
        );
        if (!context.mounted || remove == null) return;
        if (remove) {
          if (edit.canRemove(t)) await edit.remove(context, t);
        } else if (c.canQueue(t)) {
          await TrackMenuButton._queued(context, c.addToQueue([t]), tr.toastAddedToQueue, shell.openQueue);
        }
      },
      child: row,
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
            final channel = artist.browseId;
            if (channel == null) throw StateError('No artist channel for $who');
            final catalog = await c.ytMusic.artistTracks(channel);
            return Collection(
              kind: CollectionKind.remoteArtist,
              id: channel,
              title: artist.title,
              subtitle: tr.artist,
              tracks: catalog.songs,
              artistVideos: catalog.videos,
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
enum TrackMenuEntry { addToPlaylist, download, share, audioSource, copySongTitle }

/// The ⋯ menu of a song: play next, add to playlist, like, download, go to artist…
class TrackMenuButton extends StatelessWidget {
  const TrackMenuButton({
    super.key,
    required this.track,
    this.pinned = false,
    this.onTogglePin,
    this.visible = true,
    this.color,
    this.nowPlaying = false,
    this.hide = const {},
  });

  static Future<void> _queued(BuildContext context, Future<void> change, String done, [VoidCallback? openQueue]) async {
    final messenger = ScaffoldMessenger.of(context);
    await change;
    messenger.showSnackBar(
      openQueue == null
          ? SnackBar(content: Text(done), duration: const Duration(seconds: 2))
          : LinkedToast(done, label: tr.openQueue, open: openQueue),
    );
  }

  /// A guest of a session whose host takes suggestions.
  static bool _canSuggest(PlayerController c) {
    final s = ListenTogether.of(c);
    return s.role == ListenRole.guest && s.suggestionsAllowed;
  }

  /// Queues [tracks] for download. A plain tap follows Settings (and asks only if
  /// "Ask every time" is on); [force] always asks, for "Download as…". [withVideo] is "Download with MV": the
  /// song's music video is saved beside it too.
  static Future<void> download(
    BuildContext host,
    PlayerController c,
    List<Track> tracks, {
    bool force = false,
    bool withVideo = false,
  }) async {
    final one = tracks.length == 1 ? tracks.first : null;
    if (tracks.isNotEmpty && tracks.every((t) => t.monochromeId != null || t.extensionId != null)) {
      final extensions = tracks.where((track) => track.extensionId != null).toList();
      if (extensions.isNotEmpty && !await downloadExtensionTracks(host, c, extensions)) return;
      c.youtube.enqueueTracks(tracks.where((track) => track.monochromeId != null).toList());
      return;
    }
    if (one?.isRemote == true && !withVideo) {
      await downloadFromSource(host, c, one!, force: force);
      return;
    }
    final choice = await chooseDownload(host, force: force, videoId: one?.videoId, track: one);
    if (choice == null) return;
    c.youtube.enqueueTracks(tracks, choice: choice, withVideo: withVideo);
  }

  /// Whether "Download with MV" is offered for [track]: a streamed song not downloaded yet that is known to have a
  /// music video (asked with [VideoMode.lookUp]), in a build with downloads and Video mode, with Video mode on.
  static bool offersMvDownload(PlayerController c, Track track) =>
      Features.downloads &&
      Features.videoMode &&
      track.isRemote &&
      c.downloadedCopy(track) == null &&
      VideoMode.instance.videoOf(track) != null;

  /// The web build: [track]'s audio as a browser download (see [Features.saveToDevice]).
  static void saveToDevice(BuildContext host, Track track) {
    final url = webSaveUri(track.videoId!, [if (track.artist.isNotEmpty) track.artist, track.title].join(' - '));
    if (url == null) return;
    BrowserFiles.saveUrl(url, track.title);
    ScaffoldMessenger.of(host).showSnackBar(SnackBar(content: Text(tr.savingToDevice(track.title))));
  }

  final Track track;
  final bool pinned;
  final VoidCallback? onTogglePin;
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
          final overlay = Navigator.of(context, rootNavigator: true).overlay!.context.findRenderObject()! as RenderBox;
          final anchor = context.findRenderObject()! as RenderBox;
          final position = RelativeRect.fromSize(
            anchor.localToGlobal(Offset.zero, ancestor: overlay) & anchor.size,
            overlay.size,
          );
          final lists = c.playlists.where((p) => p.tracks.any((t) => t.id == track.id)).toList();
          final secondary = <PopupMenuEntry<void>>[
            if (lists.isNotEmpty)
              PopupMenuItem(
                onTap: () async {
                  final list = await pickListItem(host, tr.inPlaylists, lists, (p) => p.name);
                  if (list != null) shell.openCollection(c.playlistCollection(list));
                },
                child: MenuRow(leading: const Icon(Icons.playlist_play), title: Text(tr.inPlaylists)),
              ),
            if (nowPlaying && c.currentTrack?.id == track.id) ...[
              PopupMenuItem(
                onTap: () => songBookmarks(host, c, track),
                child: MenuRow(leading: const Icon(Icons.bookmark_outline), title: Text(tr.songBookmarks)),
              ),
              if ((track.videoId ?? track.onYoutube?.videoId) != null)
                PopupMenuItem(
                  onTap: () => copyTrackTime(c, track),
                  child: MenuRow(leading: const Icon(Icons.link), title: Text(tr.copyAtTime)),
                ),
            ],
            if (track.isRemote && Features.smartMerge && !c.casting && !hide.contains(TrackMenuEntry.audioSource))
              PopupMenuItem(
                onTap: () => showAudioSourcePicker(host, track),
                child: MenuRow(leading: const Icon(Icons.swap_horiz_rounded), title: Text(tr.audioSource)),
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
            if (!hide.contains(TrackMenuEntry.copySongTitle))
              PopupMenuItem(
                onTap: () => copySongTitle(host, track),
                child: MenuRow(leading: const Icon(Icons.content_copy_rounded), title: Text(tr.copySongTitle)),
              ),
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
              // The phone's More sheet already has Tempo & pitch in Sound.
              for (final e in NowPlayingCover.menuItems(includeTempoPitch: !shell.compact))
                PopupMenuItem(onTap: () => NowPlayingCover.handle(host, e.value), child: e.child),
            ],
          ];
          return [
            PopupMenuItem(
              enabled:
                  c.canQueue(track) &&
                  (ListenTogether.of(c).role != ListenRole.guest || (_canSuggest(c) && track.videoId != null)),
              onTap: () => _canSuggest(c)
                  ? _queued(host, ListenTogether.of(c).suggest(track), tr.toastRequestedNext, shell.openQueue)
                  : _queued(host, c.playNext([track]), tr.toastPlaysNext, shell.openQueue),
              child: MenuRow(leading: const Icon(Icons.playlist_play_rounded), title: Text(tr.playNext)),
            ),
            PopupMenuItem(
              enabled: c.canQueue(track),
              onTap: () => _queued(host, c.addToQueue([track]), tr.toastAddedToQueue, shell.openQueue),
              child: MenuRow(leading: const Icon(Icons.queue_music_rounded), title: Text(tr.addToQueue)),
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
            if (c.resumePosition(track) case final position?)
              PopupMenuItem(
                onTap: () => c.resumeLongTrack(track),
                child: MenuRow(
                  leading: const Icon(Icons.play_circle_outline),
                  title: Text(tr.resumeAt(formatDuration(position))),
                ),
              ),
            if (ExtraFeature.hideRecommendations.enabled && c.isAutoplayed(track))
              PopupMenuItem(
                onTap: () => c.hideRecommendedTrack(track),
                child: MenuRow(leading: const Icon(Icons.not_interested_rounded), title: Text(tr.dontRecommendAgain)),
              ),
            if (onTogglePin != null)
              PopupMenuItem(
                onTap: onTogglePin,
                child: MenuRow(
                  leading: Icon(pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined),
                  title: Text(pinned ? tr.unpinTrack : tr.pinTrack),
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
            if (track.soundcloudId != null ||
                track.monochromeId != null ||
                track.extensionId != null ||
                track.spotifyId != null) ...[
              if ((track.monochromeId != null || track.extensionId != null) && Features.downloads)
                PopupMenuItem(
                  onTap: () => download(host, c, [track]),
                  child: MenuRow(leading: const Icon(Icons.download_rounded), title: Text(tr.download)),
                ),
              if (track.soundcloudId != null)
                PopupMenuItem(
                  onTap: () => shell.startRadio(host, c, track),
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
                onTap: () => shell.startRadio(host, c, track),
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
                if (Features.videoMode)
                  _DownloadWithMvEntry(
                    track: track,
                    controller: c,
                    onTap: () => download(host, c, [track], withVideo: true),
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
              // A song on this device: its radio mixes the library with YouTube Music's picks for its match.
              PopupMenuItem(
                onTap: () => shell.startRadio(host, c, track),
                child: MenuRow(leading: const Icon(Icons.radio_rounded), title: Text(tr.startRadio)),
              ),
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
            if (secondary.isNotEmpty)
              PopupMenuItem(
                onTap: () =>
                    showMenu<void>(context: host, useRootNavigator: true, position: position, items: secondary),
                child: MenuRow(leading: const Icon(Icons.more_horiz_rounded), title: Text(tr.moreOptions)),
              ),
          ];
        },
      ),
    );
  }
}

/// "Download with MV" in a song's menu. Only songs with a music video have it, and whether one does is asked as the
/// menu opens (the request the download choices already make), so the entry takes no room until the answer is yes.
class _DownloadWithMvEntry extends PopupMenuEntry<void> {
  const _DownloadWithMvEntry({required this.track, required this.controller, required this.onTap});

  final Track track;
  final PlayerController controller;
  final VoidCallback onTap;

  @override
  double get height => kMinInteractiveDimension;

  @override
  bool represents(void value) => false;

  @override
  State<_DownloadWithMvEntry> createState() => _DownloadWithMvEntryState();
}

class _DownloadWithMvEntryState extends State<_DownloadWithMvEntry> {
  @override
  void initState() {
    super.initState();
    VideoMode.instance
      ..follow(widget.controller)
      ..lookUp(widget.track);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: VideoMode.instance,
    builder: (context, _) => TrackMenuButton.offersMvDownload(widget.controller, widget.track)
        ? PopupMenuItem<void>(
            onTap: widget.onTap,
            child: MenuRow(leading: const Icon(Icons.video_library_outlined), title: Text(tr.downloadWithMv)),
          )
        : const SizedBox.shrink(),
  );
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

/// A line exactly as tall as [style]'s own font, whatever fallback font a character is drawn from.
StrutStyle? _line(TextStyle? style) => style == null ? null : StrutStyle.fromTextStyle(style, forceStrutHeight: true);

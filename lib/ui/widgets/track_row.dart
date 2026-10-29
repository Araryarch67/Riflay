import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../../services/audio_engine.dart';
import '../../services/layout_prefs.dart';
import '../../services/download_edit.dart';
import '../../services/flac_convert.dart';
import '../../services/listen_together/listen_together.dart';
import '../../services/metadata.dart';
import '../../services/player_controller.dart';
import '../../services/youtube_stream.dart';
import '../download_editor.dart';
import '../download_options.dart';
import '../flac_convert_dialog.dart';
import '../shell_scope.dart';
import '../tag_editor.dart';
import '../../services/youtube_music_account.dart';
import '../pages/youtube_music_page.dart' show openRemotePlaylist;
import '../ytmusic_edit.dart';
import '../theme.dart';
import 'controls.dart';
import 'menus.dart';
import 'stats_for_nerds.dart';

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
  final VoidCallback onTap;

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
        return (current, current && c.showsPlaying, t.isRemote && !c.isOffline(t));
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
            if (leading != null) ...[leading, const SizedBox(width: 12)],
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
                      color: isCurrent ? AppColors.accent : AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (isCurrent && !wide) ...[EqualizerIcon(playing: playing, size: 10), const SizedBox(width: 6)],
                      // YouTube songs: cloud = streams, green pin = downloaded, plays offline.
                      if (t.isRemote) ...[SourceMark(online: online, size: 14), const SizedBox(width: 4)],
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
      child: _Hovering(
        hover: _hover,
        child: body,
        builder: (context, hover, child) => Material(
          color: hover ? AppColors.tile : Colors.transparent,
          borderRadius: LayoutPrefs.corner(6),
          child: InkWell(
            borderRadius: LayoutPrefs.corner(6),
            hoverColor: Colors.transparent,
            onTap: isCurrent && wide && hover ? c.togglePlay : widget.onTap,
            child: child,
          ),
        ),
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

/// Opens [track]'s artist: YouTube Music's page for a streamed song (all of
/// its songs, not only the ones here), the library's for a file on this
/// device. Null when there's none to open. [host] must outlive the caller.
VoidCallback? openArtist(BuildContext host, PlayerController c, Track track) {
  final id = track.artistId;
  void remote(String id) =>
      openRemotePlaylist(host, RemotePlaylist(id: id, browseId: id, title: track.artist.split(', ').first, count: 0));
  if (track.isRemote && id != null) return () => remote(id);
  if (c.artistNamed(track.artist) case final local?) return () => ShellScope.of(host).openCollection(local);
  return id == null ? null : () => remote(id);
}

/// The ⋯ menu of a song: play next, add to playlist, like, download, go to artist…
class TrackMenuButton extends StatelessWidget {
  const TrackMenuButton({super.key, required this.track, this.visible = true, this.color, this.nowPlaying = false});

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
    final choice = await chooseDownload(host, force: force, videoId: tracks.length == 1 ? tracks.first.videoId : null);
    if (choice == null) return;
    c.youtube.enqueueTracks(tracks, choice: choice);
  }

  final Track track;
  final bool visible;
  final Color? color;

  /// In a now-playing view: adds Stats for nerds and Signal path.
  final bool nowPlaying;

  @override
  Widget build(BuildContext context) {
    final c = PlayerScope.read(context);
    final shell = ShellScope.of(context);
    return Opacity(
      opacity: visible ? 1 : 0,
      child: PopupMenuButton<void>(
        // Over the whole window, so a click anywhere (sidebar included) closes it.
        useRootNavigator: true,
        tooltip: 'More options for ${track.title}',
        icon: Icon(Icons.more_horiz_rounded, color: color),
        // The row can be rebuilt away while the menu is open (a list refreshing),
        // so actions run against the navigator's context, which outlives it.
        // Worked out when the menu opens, not for every row on every rebuild.
        itemBuilder: (_) {
          // The menu is open: the download choices are likely next, so their formats are looked up now.
          if (track.isRemote && track.videoId != null) YoutubeStream.prefetchDownloadCandidates(track.videoId!);
          final host = Navigator.of(context).context;
          final editScope = PlaylistEditScope.maybeOf(context);
          final artist = openArtist(host, c, track);
          final album = c.albumOf(track);
          // A song downloaded from YouTube, or the download of a streamed one: "Edit" with the artist locked.
          final downloaded = track.isRemote ? c.downloadedCopy(track) : (DownloadEdit.isDownload(track) ? track : null);
          // A streamed song that was downloaded converts its file; one with no file has nothing to convert.
          final convertible = downloaded ?? track;
          return [
            PopupMenuItem(
              onTap: () => _queued(host, c.playNext([track]), 'Plays next'),
              child: const MenuRow(leading: Icon(Icons.playlist_play_rounded), title: Text('Play next')),
            ),
            PopupMenuItem(
              onTap: () => _queued(host, c.addToQueue([track]), 'Added to queue'),
              child: const MenuRow(leading: Icon(Icons.queue_music_rounded), title: Text('Add to queue')),
            ),
            if (artist != null)
              PopupMenuItem(
                onTap: artist,
                child: const MenuRow(leading: Icon(Icons.person_outline_rounded), title: Text('Go to artist')),
              ),
            if (album != null)
              PopupMenuItem(
                onTap: () => shell.openCollection(album),
                child: const MenuRow(leading: Icon(Icons.album_outlined), title: Text('Go to album')),
              ),
            PopupMenuItem(
              onTap: () => addToPlaylist(host, [track]),
              child: const MenuRow(leading: Icon(Icons.playlist_add_rounded), title: Text('Add to playlist')),
            ),
            if (editScope?.canRemove(track) ?? false)
              PopupMenuItem(
                onTap: () => editScope!.remove(host, track),
                child: const MenuRow(
                  leading: Icon(Icons.playlist_remove_rounded),
                  title: Text('Remove from this playlist'),
                ),
              ),
            if (track.isRemote) ...[
              if (c.ytMusic.canEdit)
                PopupMenuItem(
                  onTap: () => toggleLike(host, track),
                  child: MenuRow(
                    leading: Icon(c.ytMusic.isLiked(track) ? Icons.favorite_rounded : Icons.favorite_border_rounded),
                    title: Text(c.ytMusic.isLiked(track) ? 'Remove from Liked music' : 'Add to Liked music'),
                  ),
                ),
              PopupMenuItem(
                onTap: () => c.startRadio(track),
                child: const MenuRow(leading: Icon(Icons.radio_rounded), title: Text('Start radio')),
              ),
              if (_canSuggest(c))
                PopupMenuItem(
                  onTap: () => ListenTogether.of(c).suggest(track),
                  child: MenuRow(
                    leading: const Icon(Icons.group_add_outlined),
                    title: Text('Suggest to ${ListenTogether.of(c).hostName ?? 'the host'}'),
                  ),
                ),
              if (c.downloadedCopy(track) == null) ...[
                PopupMenuItem(
                  onTap: () => download(host, c, [track]),
                  child: const MenuRow(leading: Icon(Icons.download_rounded), title: Text('Download for offline')),
                ),
                PopupMenuItem(
                  onTap: () => download(host, c, [track], force: true),
                  child: const MenuRow(leading: Icon(Icons.tune_rounded), title: Text('Download as…')),
                ),
              ],
              if (downloaded != null)
                PopupMenuItem(
                  onTap: () => showDownloadEditor(host, downloaded, compact: shell.compact),
                  child: const MenuRow(leading: Icon(Icons.edit_outlined), title: Text('Edit')),
                ),
            ] else ...[
              if (downloaded != null)
                PopupMenuItem(
                  onTap: () => showDownloadEditor(host, downloaded, compact: shell.compact),
                  child: const MenuRow(leading: Icon(Icons.edit_outlined), title: Text('Edit')),
                )
              else if (Metadata.canEditTags(track))
                PopupMenuItem(
                  onTap: () => showTagEditor(host, track),
                  child: const MenuRow(leading: Icon(Icons.edit_outlined), title: Text('Edit info')),
                ),
              PopupMenuItem(
                onTap: () => c.removeTrack(track),
                child: const MenuRow(
                  leading: Icon(Icons.remove_circle_outline_rounded),
                  title: Text('Remove from library'),
                ),
              ),
            ],
            if (FlacConvert.available(convertible))
              PopupMenuItem(
                onTap: () => showFlacConvert(host, c, [convertible]),
                child: const MenuRow(leading: Icon(Icons.graphic_eq_rounded), title: Text('Convert to FLAC')),
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

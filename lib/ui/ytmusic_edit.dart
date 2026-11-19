import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/track.dart';
import '../platform/features.dart';
import '../services/download_prefs.dart';
import '../services/language.dart';
import '../services/layout_prefs.dart';
import '../services/player_controller.dart';
import '../services/youtube_importer.dart';
import '../services/monochrome_download.dart';
import '../services/spotiflac.dart';
import '../services/youtube_music_account.dart';
import '../services/ytmusic_web.dart';
import 'download_options.dart';
import 'download_source_dialog.dart';
import 'pages/youtube_music_page.dart' show openRemotePlaylist;
import 'shell_scope.dart';
import 'theme.dart';
import 'widgets/app_dialog.dart';
import 'widgets/glass_toast.dart';

/// Marks the songs below as rows of a playlist the user can edit (an
/// Riflay playlist or their own YouTube Music one), so each song's menu
/// can offer "Remove from this playlist".
class PlaylistEditScope extends InheritedWidget {
  const PlaylistEditScope({
    super.key,
    required this.canRemove,
    required this.remove,
    this.removeMany,
    required super.child,
  });

  final bool Function(Track track) canRemove;
  final Future<void> Function(BuildContext context, Track track) remove;
  final Future<bool> Function(BuildContext context, List<Track> tracks)? removeMany;

  static PlaylistEditScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PlaylistEditScope>();

  @override
  bool updateShouldNotify(PlaylistEditScope old) => true;
}

/// Runs a library change and reports how it went, in plain words.
Future<bool> _report(BuildContext context, Future<void> Function() change, String done) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await change();
    messenger.showSnackBar(SnackBar(content: Text(done)));
    return true;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(YoutubeMusicAccount.describe(e))));
    return false;
  }
}

Future<void> toggleLike(BuildContext context, Track track) {
  final account = PlayerScope.read(context).ytMusic;
  final liked = account.isLiked(track);
  return _report(context, () => account.setLiked(track, !liked), liked ? tr.removedFromLiked : tr.addedToLiked);
}

/// Name + privacy for a new playlist (or a rename when [initialTitle] is set).
Future<({String title, PlaylistPrivacy privacy, PlaylistHome home})?> askPlaylistName(
  BuildContext context, {
  String? initialTitle,
  PlaylistPrivacy initialPrivacy = PlaylistPrivacy.private,
  bool askPrivacy = true,
  bool offerYoutube = false,
}) => showDialog<({String title, PlaylistPrivacy privacy, PlaylistHome home})>(
  context: context,
  builder: (_) => _PlaylistNameDialog(
    initialTitle: initialTitle,
    initialPrivacy: initialPrivacy,
    askPrivacy: askPrivacy,
    offerYoutube: offerYoutube,
  ),
);

/// Owns its text controller, so it lives exactly as long as the dialog
/// (including its closing animation).
class _PlaylistNameDialog extends StatefulWidget {
  const _PlaylistNameDialog({
    required this.initialTitle,
    required this.initialPrivacy,
    required this.askPrivacy,
    required this.offerYoutube,
  });

  final String? initialTitle;
  final PlaylistPrivacy initialPrivacy;
  final bool askPrivacy;
  final bool offerYoutube;

  @override
  State<_PlaylistNameDialog> createState() => _PlaylistNameDialogState();
}

class _PlaylistNameDialogState extends State<_PlaylistNameDialog> {
  late final name = TextEditingController(text: widget.initialTitle);
  late var privacy = widget.initialPrivacy;
  var home = PlaylistHome.riflay;

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  void submit() {
    final t = name.text.trim();
    if (t.isNotEmpty) Navigator.pop(context, (title: t, privacy: privacy, home: home));
  }

  @override
  Widget build(BuildContext context) {
    final initialTitle = widget.initialTitle;
    final askPrivacy = widget.askPrivacy;
    final offerYoutube = widget.offerYoutube;
    return AppDialog(
      title: Text(initialTitle == null ? tr.newPlaylist : tr.renamePlaylist),
      width: DialogWidth.regular,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: name,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => submit(),
            decoration: InputDecoration(labelText: tr.name, border: OutlineInputBorder()),
          ),
          if (offerYoutube) ...[
            const SizedBox(height: 16),
            SegmentedButton<PlaylistHome>(
              segments: const [
                ButtonSegment(
                  value: PlaylistHome.riflay,
                  icon: Icon(Icons.offline_pin_outlined),
                  label: Text('Riflay'),
                ),
                ButtonSegment(
                  value: PlaylistHome.youtubeMusic,
                  icon: Icon(Icons.cloud_outlined),
                  label: Text('YouTube Music'),
                ),
              ],
              selected: {home},
              onSelectionChanged: (v) => setState(() => home = v.first),
            ),
            const SizedBox(height: 8),
            Text(
              home == PlaylistHome.riflay ? tr.playlistOnDeviceNote : tr.playlistOnYtNote,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ],
          if (askPrivacy || home == PlaylistHome.youtubeMusic) ...[
            const SizedBox(height: 16),
            SegmentedButton<PlaylistPrivacy>(
              segments: [for (final p in PlaylistPrivacy.values) ButtonSegment(value: p, label: Text(p.label))],
              selected: {privacy},
              onSelectionChanged: (v) => setState(() => privacy = v.first),
            ),
            const SizedBox(height: 8),
            Text(switch (privacy) {
              PlaylistPrivacy.private => tr.privacyPrivate,
              PlaylistPrivacy.unlisted => tr.privacyUnlisted,
              PlaylistPrivacy.public => tr.privacyPublic,
            }, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr.cancel)),
        FilledButton(onPressed: submit, child: Text(initialTitle == null ? tr.create : tr.save)),
      ],
    );
  }
}

/// Where a new playlist goes.
enum PlaylistHome { riflay, youtubeMusic }

/// "New playlist": a Riflay playlist on this device by default. Signed in,
/// it can be made in YouTube Music instead when some of the songs are there
/// (streamed or downloaded from it); files from this device are left out.
Future<void> createPlaylist(BuildContext context, {List<Track> tracks = const []}) async {
  final c = PlayerScope.read(context);
  final onYoutube = YoutubeMusicAccount.youtubeSongs(tracks);
  final canYoutube = c.ytMusic.canEdit && (tracks.isEmpty || onYoutube.songs.isNotEmpty);
  final answer = await askPlaylistName(context, askPrivacy: false, offerYoutube: canYoutube);
  if (answer == null || !context.mounted) return;
  if (answer.home == PlaylistHome.youtubeMusic) {
    await _report(
      context,
      () => c.ytMusic.createPlaylist(answer.title, privacy: answer.privacy, tracks: onYoutube.songs),
      withSkipped(tr.createdInYt(answer.title), onYoutube.skipped),
    );
    return;
  }
  final playlist = c.createPlaylist(answer.title, tracks: tracks);
  final shell = context.getInheritedWidgetOfExactType<ShellScope>();
  ScaffoldMessenger.of(context).showSnackBar(
    _playlistToast(
      tracks.isEmpty ? tr.createdPlaylist(answer.title) : tr.createdPlaylistWith(answer.title, tracks.length),
      shell == null ? null : () => shell.openCollection(c.playlistCollection(playlist)),
    ),
  );
}

/// [done], plus how many songs were left out for not being on YouTube Music.
String withSkipped(String done, int skipped) => skipped == 0 ? done : '$done. ${tr.skippedNotOnYoutubeMusic(skipped)}';

/// What adding [added] of [tracks] to playlist [name] did, in words: [skipped] of them weren't on YouTube Music.
@visibleForTesting
String addedMessage({required String name, required int tracks, required int added, int skipped = 0}) {
  if (skipped > 0 && skipped == tracks) return tracks == 1 ? tr.notOnYoutubeMusic : tr.noneOnYoutubeMusic;
  final done = added == 0 ? tr.alreadyIn(name) : (tracks == 1 ? tr.addedTo(name) : tr.addedSongsTo(added, name));
  return withSkipped(done, skipped);
}

/// "Add to playlist": Riflay playlists, then (signed in) the YouTube Music
/// ones, each marked with where it lives. A download goes into a YouTube Music
/// playlist by the video it came from; a file that never came from YouTube
/// can't, so those playlists say so instead of failing quietly.
Future<void> addToPlaylist(BuildContext context, List<Track> tracks) async {
  final c = PlayerScope.read(context);
  final account = c.ytMusic;
  final onYoutube = YoutubeMusicAccount.youtubeSongs(tracks);
  final remote = account.canEdit
      ? (await account.library().catchError(
          (Object _) => const YoutubeMusicLibrary(liked: [], playlists: [], recent: []),
        )).playlists
      : const <RemotePlaylist>[];
  if (!context.mounted) return;
  final text = Theme.of(context).textTheme;
  final noneThere = onYoutube.songs.isEmpty;
  final notThere = tracks.length == 1 ? tr.notOnYoutubeMusic : tr.noneOnYoutubeMusic;
  final remember = ExtraFeature.recentPlaylist.enabled;
  final choices = <({Object entry, String key, String title, String detail, bool remote})>[
    for (final p in c.playlists)
      (entry: p, key: 'local:${p.id}', title: p.name, detail: tr.playlistOnRiflay(p.tracks.length), remote: false),
    for (final p in remote)
      (
        entry: p,
        key: 'youtube:${p.id}',
        title: p.title,
        detail: noneThere
            ? notThere
            : p.count == 0
            ? 'YouTube Music'
            : tr.playlistOnYoutubeMusic(p.count),
        remote: true,
      ),
  ];
  if (remember) {
    final recent = choices.indexWhere((p) => p.key == LayoutPrefs.instance.lastPlaylistChoice);
    if (recent > 0) choices.insert(0, choices.removeAt(recent));
  }
  var query = '';
  final choice = await showDialog<Object>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (context, update) {
        final visible = query.isEmpty ? choices : choices.where((p) => p.title.toLowerCase().contains(query)).toList();
        return AppDialog(
          title: tr.addToPlaylist,
          scrollable: false,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          content: SizedBox(
            height: 360,
            child: Column(
              children: [
                if (remember)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: SearchBar(
                      hintText: tr.searchPlaylists,
                      leading: const Icon(Icons.search_rounded),
                      onChanged: (value) => update(() => query = value.trim().toLowerCase()),
                    ),
                  ),
                Expanded(
                  child: ListView.builder(
                    itemCount: 1 + visible.length,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return ListTile(
                          leading: const Icon(Icons.add_rounded),
                          title: Text(tr.newPlaylist),
                          onTap: () => Navigator.pop(dialog, #create),
                        );
                      }
                      final p = visible[index - 1];
                      final enabled = !p.remote || !noneThere;
                      return ListTile(
                        enabled: enabled,
                        leading: Icon(p.remote ? Icons.cloud_outlined : Icons.queue_music_rounded),
                        title: Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(p.detail, style: text.bodySmall),
                        onTap: enabled ? () => Navigator.pop(dialog, p.entry) : null,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: Text(tr.cancel))],
        );
      },
    ),
  );
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final shell = context.getInheritedWidgetOfExactType<ShellScope>();
  switch (choice) {
    case #create:
      return createPlaylist(context, tracks: tracks);
    case final UserPlaylist p:
      final n = c.addToPlaylist(p.id, tracks);
      if (remember) await LayoutPrefs.instance.rememberPlaylist('local:${p.id}');
      messenger.showSnackBar(
        _playlistToast(
          addedMessage(name: p.name, tracks: tracks.length, added: n),
          shell == null
              ? null
              : () {
                  final updated = c.playlistById(p.id);
                  if (updated != null) shell.openCollection(updated);
                },
        ),
      );
    case final RemotePlaylist p:
      if (noneThere) {
        messenger.showSnackBar(SnackBar(content: Text(notThere)));
        return;
      }
      try {
        final n = await account.addToPlaylist(p.id, onYoutube.songs);
        if (remember) await LayoutPrefs.instance.rememberPlaylist('youtube:${p.id}');
        messenger.showSnackBar(
          _playlistToast(
            addedMessage(name: p.title, tracks: tracks.length, added: n, skipped: onYoutube.skipped),
            shell == null ? null : () => openRemotePlaylist(context, p, shell: shell, account: account),
          ),
        );
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(YoutubeMusicAccount.describe(e))));
      }
  }
}

SnackBar _playlistToast(String message, VoidCallback? open) =>
    open == null ? SnackBar(content: Text(message)) : LinkedToast(message, label: tr.openPlaylist, open: open);

Future<void> removeFromPlaylist(BuildContext context, Track track) async {
  final scope = PlaylistEditScope.maybeOf(context);
  if (scope != null) await scope.remove(context, track);
}

/// Removing a row from one of the user's YouTube Music playlists.
Future<bool> removeFromRemotePlaylist(BuildContext context, String playlistId, Track track, String rowId) => _report(
  context,
  () => PlayerScope.read(context).ytMusic.removeFromPlaylist(playlistId, track, rowId),
  tr.removedFromThisPlaylist,
);

Future<bool> removeSelectedFromRemotePlaylist(
  BuildContext context,
  String playlistId,
  List<Track> tracks,
  Map<String, String> rowIds,
) async {
  final account = PlayerScope.read(context).ytMusic;
  final rows = {
    for (final track in tracks)
      if (track.videoId != null && rowIds.containsKey(track.id)) track: rowIds[track.id]!,
  };
  if (rows.isEmpty) return false;
  final confirmed = await confirmDialog(
    context,
    title: tr.removeFromThisPlaylist,
    body: tr.removeSelectedTracksBody(rows.length),
    confirmLabel: tr.remove,
    destructive: true,
  );
  if (!confirmed || !context.mounted) return false;
  return _report(context, () => account.removePlaylistTracks(playlistId, rows), tr.removedFromThisPlaylist);
}

/// "Invite friends": turns on collaboration and hands over the link to send.
/// A private playlist has to become unlisted first, so that's asked.
/// Returns whether the playlist is now shared.
Future<bool> inviteToPlaylist(BuildContext context, String playlistId, PlaylistPrivacy? privacy) async {
  final account = PlayerScope.read(context).ytMusic;
  final messenger = ScaffoldMessenger.of(context);
  if (privacy == PlaylistPrivacy.private) {
    final ok = await confirmDialog(
      context,
      title: tr.makeUnlistedQuestion,
      body: tr.makeUnlistedBody,
      confirmLabel: tr.makeUnlisted,
    );
    if (ok != true) return false;
  }
  final String link;
  try {
    link = await account.inviteLink(playlistId, privacy: privacy);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(YoutubeMusicAccount.describe(e))));
    return false;
  }
  await Clipboard.setData(ClipboardData(text: link));
  if (!context.mounted) return true;
  await showDialog<void>(
    context: context,
    builder: (_) => _InviteDialog(link: link),
  );
  return true;
}

class _InviteDialog extends StatelessWidget {
  const _InviteDialog({required this.link});

  final String link;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AppDialog(
      title: Text(tr.inviteFriends),
      width: DialogWidth.regular,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr.inviteLinkCopied),
          const SizedBox(height: 16),
          DecoratedBox(
            decoration: BoxDecoration(color: AppColors.hover, borderRadius: BorderRadius.circular(6)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SelectableText(link, maxLines: 2, style: text.bodySmall),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: link));
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.linkCopied)));
          },
          child: Text(tr.copyAgain),
        ),
        FilledButton(onPressed: () => Navigator.pop(context), child: Text(tr.done)),
      ],
    );
  }
}

/// "Stop sharing": every friend loses access and old links stop working.
Future<bool> stopSharingPlaylist(BuildContext context, String playlistId) async {
  final sure = await confirmDialog(
    context,
    title: tr.stopSharingQuestion,
    body: tr.stopSharingBody,
    confirmLabel: tr.stopSharing,
    destructive: true,
  );
  if (sure != true || !context.mounted) return false;
  return _report(context, () => PlayerScope.read(context).ytMusic.stopCollaboration(playlistId), tr.onlyYouCanAdd);
}

/// Asks for a friend's invite link (filled in from the clipboard when one is
/// there) and joins it. Returns the playlist's id once joined.
Future<String?> askToJoinPlaylist(BuildContext context) async {
  final account = PlayerScope.read(context).ytMusic;
  final messenger = ScaffoldMessenger.of(context);
  final copied = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim();
  if (!context.mounted) return null;
  final link = await showDialog<String>(
    context: context,
    builder: (_) => _JoinDialog(initial: copied != null && YtMusicWeb.parseInvite(copied) != null ? copied : null),
  );
  if (link == null) return null;
  try {
    return await account.joinPlaylist(link);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(YoutubeMusicAccount.describe(e))));
    return null;
  }
}

class _JoinDialog extends StatefulWidget {
  const _JoinDialog({required this.initial});

  final String? initial;

  @override
  State<_JoinDialog> createState() => _JoinDialogState();
}

class _JoinDialogState extends State<_JoinDialog> {
  late final link = TextEditingController(text: widget.initial);
  late bool valid = widget.initial != null;

  @override
  void dispose() {
    link.dispose();
    super.dispose();
  }

  void submit() {
    if (valid) Navigator.pop(context, link.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: Text(tr.joinSharedPlaylist),
      width: DialogWidth.regular,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr.joinSharedPlaylistBody),
          const SizedBox(height: 16),
          TextField(
            controller: link,
            autofocus: widget.initial == null,
            textInputAction: TextInputAction.done,
            onChanged: (v) => setState(() => valid = YtMusicWeb.parseInvite(v) != null),
            onSubmitted: (_) => submit(),
            decoration: InputDecoration(
              labelText: tr.inviteLink,
              border: const OutlineInputBorder(),
              errorText: link.text.trim().isNotEmpty && !valid ? tr.notAnInviteLink : null,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr.cancel)),
        FilledButton(onPressed: valid ? submit : null, child: Text(tr.join)),
      ],
    );
  }
}

/// The ♥ button for the song that's playing.
class LikeButton extends StatelessWidget {
  const LikeButton({super.key, required this.track, this.size = 20, this.color});

  final Track track;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final account = PlayerScope.of(context).ytMusic;
    if (!track.isRemote || !account.canEdit) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: account,
      builder: (context, _) {
        final liked = account.isLiked(track);
        return IconButton(
          tooltip: liked ? tr.removeFromLiked : tr.addToLiked,
          iconSize: size,
          color: liked ? AppColors.accent : color,
          onPressed: () => toggleLike(context, track),
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
            child: Icon(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, key: ValueKey(liked)),
          ),
        );
      },
    );
  }
}

/// A round, translucent icon button, for the buttons of a page whose top is the Hero header.
Widget heroRoundButton({required IconData icon, required String tooltip, required VoidCallback? onPressed}) =>
    IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        backgroundColor: AppColors.textPrimary.withValues(alpha: 0.1),
        foregroundColor: AppColors.textPrimary,
        fixedSize: const Size.square(48),
        shape: const CircleBorder(),
      ),
    );

/// "Follow" / "Following" for a YouTube Music artist (signed in through the app).

class FollowButton extends StatelessWidget {
  const FollowButton({super.key, required this.artistId, required this.name});

  final String artistId;
  final String name;

  @override
  Widget build(BuildContext context) {
    final account = PlayerScope.of(context).ytMusic;
    if (!account.canEdit) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: account,
      builder: (context, _) {
        final following = account.isFollowing(artistId);
        void toggle() => _report(
          context,
          () => account.setFollowing(artistId, !following),
          following ? tr.unfollowedName(name) : tr.followingName(name),
        );
        if (LayoutPrefs.instance.albumHeader == AlbumHeaderStyle.hero) {
          return heroRoundButton(
            icon: following ? Icons.check_rounded : Icons.person_add_alt_1_outlined,
            tooltip: following ? tr.following : tr.follow,
            onPressed: toggle,
          );
        }
        return OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            side: BorderSide(color: following ? AppColors.textSecondary : AppColors.textPrimary),
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 18),
          ),
          onPressed: () => _report(
            context,
            () => account.setFollowing(artistId, !following),
            following ? tr.unfollowedName(name) : tr.followingName(name),
          ),
          child: Text(following ? tr.following : tr.follow),
        );
      },
    );
  }
}

/// Download for offline, for a streamed song: an arrow, a progress ring while
/// it downloads (tap to stop), a check once it's on the device.
class DownloadButton extends StatelessWidget {
  const DownloadButton({super.key, required this.track, this.size = 20, this.color});

  final Track track;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = PlayerScope.of(context);
    if ((!track.isRemote && track.monochromeId == null && track.extensionId == null) || !Features.downloads) {
      return const SizedBox.shrink();
    }
    return ListenableBuilder(
      listenable: c.youtube,
      builder: (context, _) {
        final job = c.youtube.jobFor(
          track.extensionId != null
              ? Spotiflac.jobId(track)
              : track.monochromeId != null
              ? MonochromeDownload.jobId(track)
              : track.videoId!,
        );
        if (c.downloadedCopy(track) != null || job?.status == DownloadStatus.done) {
          return IconButton(
            tooltip: tr.downloaded,
            iconSize: size,
            color: AppColors.accent,
            onPressed: null,
            disabledColor: AppColors.accent,
            icon: const Icon(Icons.download_done_rounded),
          );
        }
        if (job != null && job.isActive) {
          return IconButton(
            tooltip: tr.stopDownload,
            iconSize: size,
            onPressed: () => c.youtube.cancel(job),
            icon: SizedBox.square(
              dimension: size,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: job.status == DownloadStatus.downloading && job.progress > 0 && !job.converting
                        ? job.progress
                        : null,
                    strokeWidth: 2,
                    color: AppColors.accent,
                    backgroundColor: AppColors.textPrimary.withValues(alpha: 0.24),
                  ),
                  Icon(Icons.stop_rounded, size: size * 0.5, color: color),
                ],
              ),
            ),
          );
        }
        final failed = job?.status == DownloadStatus.failed;
        final prefs = DownloadPrefs.instance..load().ignore();
        // Hold: download now in the saved format, never asking. The tooltip stays hover-only so a touch
        // long-press means this, not "show the tooltip".
        return ListenableBuilder(
          listenable: prefs,
          builder: (context, _) => Tooltip(
            message: failed
                ? tr.downloadFailedTryAgain
                : tr.downloadHoldTooltip(
                    track.extensionId != null
                        ? tr.spotiflacOriginal
                        : track.monochromeId != null
                        ? 'FLAC'
                        : describeChoice(prefs.choice),
                  ),
            triggerMode: TooltipTriggerMode.manual,
            child: GestureDetector(
              behavior: HitTestBehavior.deferToChild,
              onLongPress: () async {
                final messenger = ScaffoldMessenger.of(context);
                if (track.extensionId != null) {
                  if (await downloadExtensionTracks(context, c, [track])) {
                    messenger.showSnackBar(SnackBar(content: Text(tr.downloadingTitle(track.title))));
                  }
                  return;
                }
                await prefs.load();
                if (!context.mounted) return;
                if (track.isRemote && prefs.source != 'youtube') {
                  if (await downloadFromSource(context, c, track)) {
                    messenger.showSnackBar(SnackBar(content: Text(tr.downloadingTitle(track.title))));
                  }
                  return;
                }
                final choice = track.monochromeId != null ? const DownloadChoice(DownloadFormat.flac) : prefs.choice;
                c.youtube.enqueueTracks([track], choice: choice);
                messenger.showSnackBar(SnackBar(content: Text(tr.downloadingIn(describeChoice(choice)))));
              },
              child: IconButton(
                iconSize: size,
                color: failed ? Theme.of(context).colorScheme.error : color,
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  if (track.extensionId != null) {
                    if (await downloadExtensionTracks(context, c, [track])) {
                      messenger.showSnackBar(SnackBar(content: Text(tr.downloadingTitle(track.title))));
                    }
                    return;
                  }
                  if (track.isRemote) {
                    final queued = await downloadFromSource(context, c, track);
                    if (queued) messenger.showSnackBar(SnackBar(content: Text(tr.downloadingTitle(track.title))));
                    return;
                  }
                  final choice = track.monochromeId != null || track.extensionId != null
                      ? const DownloadChoice(DownloadFormat.flac)
                      : await chooseDownload(context, videoId: track.videoId, track: track);
                  if (choice == null) return;
                  c.youtube.enqueueTracks([track], choice: choice);
                  messenger.showSnackBar(SnackBar(content: Text(tr.downloadingTitle(track.title))));
                },
                icon: Icon(failed ? Icons.error_outline_rounded : Icons.download_rounded),
              ),
            ),
          ),
        );
      },
    );
  }
}

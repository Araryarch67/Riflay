import 'package:flutter/material.dart';

import '../models/track.dart';
import '../services/language.dart';
import '../services/layout_prefs.dart';
import '../services/player_controller.dart';
import '../services/soundcloud.dart';
import 'pages/youtube_music_page.dart' show RemoteCollectionPage;
import 'shell_scope.dart';
import 'theme.dart';
import 'widgets/controls.dart';
import 'ytmusic_edit.dart' show heroRoundButton;

/// Opens a SoundCloud playlist or profile as a page of its tracks, with Save to library (and, for a playlist,
/// Save as playlist) beside Play. [shell] when the caller's context may be gone by then (a menu).
void openSoundcloud(
  BuildContext context, {
  required SoundcloudKind kind,
  required String id,
  required String title,
  ShellScope? shell,
}) {
  final navigation = shell ?? ShellScope.of(context);
  final c = PlayerScope.read(context);
  final page = kind == SoundcloudKind.user ? c.soundcloud.user(id) : c.soundcloud.playlist(id);
  navigation.open(
    RemoteCollectionPage(
      title: title,
      load: () async => soundcloudCollection(await page),
      actions: [
        _SaveTracksButton(page: page),
        if (kind == SoundcloudKind.playlist) _SaveAsPlaylistButton(page: page),
      ],
    ),
    location: 'soundcloud:${kind.name}:$id',
  );
}

/// A playlist or profile's page, as the collection pages show it.
Collection soundcloudCollection(SoundcloudPage page) {
  final cover = SoundcloudCollection(
    kind: page.kind,
    id: page.id,
    title: page.title,
    subtitle: page.subtitle,
    artworkUrl: page.artworkUrl,
  ).cover;
  return Collection(
    kind: page.kind == SoundcloudKind.user ? CollectionKind.remoteArtist : CollectionKind.remote,
    title: page.title,
    subtitle: page.kind == SoundcloudKind.user
        ? tr.sourceSoundcloud
        : tr.soundcloudLine(page.tracks.length, page.subtitle),
    tracks: page.tracks,
    picture: page.artworkUrl == null ? null : cover,
  );
}

/// A SoundCloud playlist or profile as a card (search shelves): opens its page, plays it from the card.
class SoundcloudCard extends StatelessWidget {
  const SoundcloudCard({super.key, required this.collection});

  final SoundcloudCollection collection;

  @override
  Widget build(BuildContext context) {
    final user = collection.kind == SoundcloudKind.user;
    return MediaCard(
      track: collection.cover,
      title: collection.title,
      subtitle: user ? tr.artist : collection.subtitle,
      circle: user,
      online: true,
      onTap: () => openSoundcloud(context, kind: collection.kind, id: collection.id, title: collection.title),
      onPlay: () => _play(context),
    );
  }

  Future<void> _play(BuildContext context) async {
    final c = PlayerScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final page = collection.kind == SoundcloudKind.user
          ? await c.soundcloud.user(collection.id)
          : await c.soundcloud.playlist(collection.id);
      if (page.tracks.isNotEmpty) await c.playList(page.tracks, 0, from: page.title);
    } catch (e) {
      debugPrint('Playing ${collection.title} failed: $e');
      messenger.showSnackBar(SnackBar(content: Text(tr.couldntPlay(collection.title))));
    }
  }
}

/// Saves every playable track of the page into the library.
class _SaveTracksButton extends StatelessWidget {
  const _SaveTracksButton({required this.page});

  final Future<SoundcloudPage> page;

  Future<void> _save(BuildContext context) async {
    final c = PlayerScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await c.saveToLibrary((await page).tracks);
      messenger.showSnackBar(SnackBar(content: Text(tr.savedToLibrary)));
    } catch (e) {
      debugPrint('Saving SoundCloud tracks failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) =>
      _action(icon: Icons.library_add_outlined, label: tr.saveToLibrary, onPressed: () => _save(context));
}

/// Makes a Riflay playlist of a SoundCloud playlist's tracks.
class _SaveAsPlaylistButton extends StatelessWidget {
  const _SaveAsPlaylistButton({required this.page});

  final Future<SoundcloudPage> page;

  Future<void> _save(BuildContext context) async {
    final c = PlayerScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final p = await page;
      c.createPlaylist(p.title, tracks: p.tracks);
      messenger.showSnackBar(SnackBar(content: Text(tr.createdPlaylistWith(p.title, p.tracks.length))));
    } catch (e) {
      debugPrint('Saving a SoundCloud playlist failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) =>
      _action(icon: Icons.playlist_add_rounded, label: tr.saveAsPlaylist, onPressed: () => _save(context));
}

/// The collection header's button look: a round icon on the hero header, an outlined pill otherwise.
Widget _action({required IconData icon, required String label, required VoidCallback onPressed}) {
  if (LayoutPrefs.instance.albumHeader == AlbumHeaderStyle.hero) {
    return heroRoundButton(icon: icon, tooltip: label, onPressed: onPressed);
  }
  return OutlinedButton(
    style: OutlinedButton.styleFrom(
      foregroundColor: AppColors.textPrimary,
      side: BorderSide(color: AppColors.textPrimary),
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 18),
    ),
    onPressed: onPressed,
    child: Text(label),
  );
}

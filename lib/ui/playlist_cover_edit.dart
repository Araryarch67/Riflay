import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/language.dart';
import '../services/playlist_covers.dart';
import 'widgets/controls.dart';
import 'widgets/menus.dart';

/// Picks a picture for [key]'s playlist (or Liked music) and keeps a copy in the app's own folder.
Future<void> choosePlaylistCover(BuildContext context, String key, String name) async {
  final messenger = ScaffoldMessenger.of(context);
  final picked = (await FilePicker.pickFiles(type: FileType.image, dialogTitle: tr.chooseCoverArt)).firstOrNull;
  if (picked == null) return;
  final Uint8List bytes;
  try {
    bytes = await picked.readAsBytes();
  } catch (e) {
    debugPrint('Playlist cover not read for $name: $e');
    messenger.showSnackBar(SnackBar(content: Text(tr.couldntUsePicture)));
    return;
  }
  try {
    await PlaylistCovers.instance.setCover(key, bytes);
    messenger.showSnackBar(SnackBar(content: Text(tr.playlistCoverUpdated)));
  } catch (e) {
    debugPrint('Playlist cover not saved for $name: $e');
    messenger.showSnackBar(SnackBar(content: Text(tr.couldntUsePicture)));
  }
}

/// Drops the picture chosen for [key], bringing back the automatic cover.
Future<void> removePlaylistCover(BuildContext context, String key) async {
  final messenger = ScaffoldMessenger.of(context);
  await PlaylistCovers.instance.removeCover(key);
  messenger.showSnackBar(SnackBar(content: Text(tr.playlistCoverRemoved)));
}

/// "Change cover" / "Remove cover" for a playlist or Liked music, beside the page's other buttons.
class PlaylistCoverMenu extends StatelessWidget {
  const PlaylistCoverMenu({super.key, required this.coverKey, required this.name});

  final String coverKey;

  /// The playlist's name, for the error message if its picture can't be read.
  final String name;

  @override
  Widget build(BuildContext context) {
    final has = PlaylistCovers.instance.has(coverKey);
    return PopupMenuButton<VoidCallback>(
      // Over the whole window, so a click anywhere (sidebar included) closes it.
      useRootNavigator: true,
      tooltip: tr.playlistCover,
      icon: const Icon(Icons.image_outlined, size: 30),
      onSelected: (action) => action(),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: () => choosePlaylistCover(context, coverKey, name),
          child: MenuRow(leading: const Icon(Icons.add_photo_alternate_outlined), title: Text(tr.changeCover)),
        ),
        if (has)
          PopupMenuItem(
            value: () => removePlaylistCover(context, coverKey),
            child: MenuRow(leading: const Icon(Icons.hide_image_outlined), title: Text(tr.removeCover)),
          ),
      ],
    );
  }
}

/// [fallback] (a mosaic, or a song's cover), replaced by the picture chosen for [coverKey] when there is one.
class PlaylistArtwork extends StatelessWidget {
  const PlaylistArtwork({
    super.key,
    required this.coverKey,
    required this.fallback,
    this.size,
    this.radius = 4,
    this.circle = false,
  });

  final String? coverKey;
  final Widget fallback;
  final double? size;
  final double radius;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final own = PlaylistCovers.instance.coverOf(coverKey);
    if (own == null) return fallback;
    return Artwork(track: own, size: size, radius: radius, circle: circle);
  }
}

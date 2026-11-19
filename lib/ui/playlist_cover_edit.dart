import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import 'dart:math' as math;

import '../models/track.dart';
import '../services/metadata.dart';
import 'widgets/item_picker.dart';
import 'widgets/app_dialog.dart';

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
    if (!context.mounted) return;
    final cropped = await previewCover(context, bytes);
    if (cropped == null) return;
    await PlaylistCovers.instance.setCover(key, cropped);
    messenger.showSnackBar(SnackBar(content: Text(tr.playlistCoverUpdated)));
  } catch (e) {
    debugPrint('Playlist cover not saved for $name: $e');
    messenger.showSnackBar(SnackBar(content: Text(tr.couldntUsePicture)));
  }
}

Uint8List _square((Uint8List, double, double) input) {
  final original = img.decodeImage(input.$1);
  if (original == null) throw const FormatException();
  final photo = img.bakeOrientation(original);
  final side = math.min(photo.width, photo.height);
  final crop = img.copyCrop(
    photo,
    x: ((photo.width - side) * input.$2).round(),
    y: ((photo.height - side) * input.$3).round(),
    width: side,
    height: side,
  );
  return img.encodeJpg(img.copyResize(crop, width: 900), quality: 92);
}

Future<Uint8List?> previewCover(BuildContext context, Uint8List bytes) async {
  var x = 0.5, y = 0.5;
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (_, update) {
        Widget preview(double side) => Image.memory(
          bytes,
          width: side,
          height: side,
          fit: BoxFit.cover,
          alignment: Alignment(x * 2 - 1, y * 2 - 1),
        );
        return AppDialog(
          title: tr.changeCover,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onPanUpdate: (d) => update(() {
                  x = (x - d.delta.dx / 200).clamp(0, 1);
                  y = (y - d.delta.dy / 200).clamp(0, 1);
                }),
                child: preview(200),
              ),
              Text(tr.dragCover),
              const SizedBox(height: 12),
              preview(40),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog), child: Text(tr.cancel)),
            FilledButton(onPressed: () => Navigator.pop(dialog, true), child: Text(tr.save)),
          ],
        );
      },
    ),
  );
  return ok == true ? compute(_square, (bytes, x, y)) : null;
}

Uint8List _collage(List<Uint8List> parts) {
  final image = img.Image(width: 900, height: 900);
  for (var i = 0; i < 4; i++) {
    final part = img.decodeImage(parts[i]);
    if (part == null) throw const FormatException();
    img.compositeImage(
      image,
      img.copyResizeCropSquare(img.bakeOrientation(part), size: 450),
      dstX: i % 2 * 450,
      dstY: i ~/ 2 * 450,
    );
  }
  return img.encodeJpg(image, quality: 92);
}

Future<void> collageCover(BuildContext context, String key, List<Track> tracks) async {
  final remaining = tracks.toList(), parts = <Uint8List>[];
  try {
    while (parts.length < 4) {
      if (!context.mounted) return;
      final pick = await pickListItem(
        context,
        '${tr.coverCollage} (${parts.length + 1}/4)',
        remaining,
        (t) => t.title,
        subtitle: (t) => t.artist,
      );
      if (pick == null) return;
      final art = await Metadata.artwork(pick);
      if (art == null) throw const FormatException();
      parts.add(art);
      remaining.remove(pick);
    }
    if (!context.mounted) return;
    final bytes = await compute(_collage, parts);
    if (!context.mounted) return;
    final confirmed = await previewCover(context, bytes);
    if (confirmed != null) await PlaylistCovers.instance.setCover(key, confirmed);
  } catch (_) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.couldntUsePicture)));
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
  const PlaylistCoverMenu({super.key, required this.coverKey, required this.name, this.tracks = const []});
  final List<Track> tracks;

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
      icon: const Icon(Icons.edit_outlined),
      onSelected: (action) => action(),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: () => choosePlaylistCover(context, coverKey, name),
          child: MenuRow(leading: const Icon(Icons.add_photo_alternate_outlined), title: Text(tr.changeCover)),
        ),
        if (tracks.length >= 4)
          PopupMenuItem(
            value: () => collageCover(context, coverKey, tracks),
            child: MenuRow(leading: const Icon(Icons.grid_view), title: Text(tr.coverCollage)),
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

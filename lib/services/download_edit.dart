import 'dart:io';
import 'dart:typed_data';

import '../models/track.dart';
import 'metadata.dart';
import 'player_controller.dart';

/// Edits to a song that was downloaded from YouTube: its title, album and
/// cover. The artist is not among them: a download keeps the artist's name
/// as the artist released it.
abstract final class DownloadEdit {
  /// A library song made by a download (not a file the person added themselves).
  static bool isDownload(Track t) => t.sourceUrl != null && t.path != null && !t.isRemote;

  /// Saves the new [title] and [album] and, if given, [cover]. Written into the
  /// file's tags where the format has a tag writer (M4A), else kept in the library.
  static Future<void> apply(
    PlayerController c,
    Track track, {
    required String title,
    String? album,
    Uint8List? cover,
    String coverMime = 'image/jpeg',
  }) async {
    final newTitle = title.trim().isEmpty ? track.title : title.trim();
    final newAlbum = (album ?? '').trim().isEmpty ? null : album!.trim();
    if (Metadata.canEditTags(track)) {
      final tags = await Metadata.readTags(track);
      final edit = TagEdit(
        title: newTitle,
        // Written back as it already is, never changed.
        artist: track.artist,
        album: newAlbum,
        year: tags.year,
        trackNumber: tags.trackNumber,
        discNumber: tags.discNumber,
        genre: tags.genre,
      );
      if (cover != null) {
        edit.cover = cover;
        edit.coverMime = coverMime;
      }
      await c.editTags(track, edit);
      return;
    }
    if (cover != null) {
      final path = track.path!;
      final stem = path.substring(0, path.lastIndexOf('.'));
      // The picture sitting next to the song, which is where a download's cover is read from.
      await File('$stem.jpg').writeAsBytes(cover);
      for (final ext in ['jpeg', 'png', 'webp']) {
        final other = File('$stem.$ext');
        if (other.existsSync()) other.deleteSync();
      }
      Metadata.forgetArtwork(track);
    }
    await c.replaceTrack(withNames(track, newTitle, newAlbum));
  }

  /// [t] with a new title and album; copyWith can't clear an album, so a removed one is rebuilt.
  static Track withNames(Track t, String title, String? album) => album != null
      ? t.copyWith(title: title, album: album)
      : Track(
          id: t.id,
          uri: t.uri,
          title: title,
          artist: t.artist,
          album: null,
          duration: t.duration,
          trackNumber: t.trackNumber,
          discNumber: t.discNumber,
          start: t.start,
          end: t.end,
          addedAt: t.addedAt,
          tagged: t.tagged,
          sourceUrl: t.sourceUrl,
          videoId: t.videoId,
          artworkUrl: t.artworkUrl,
          artistId: t.artistId,
        );
}

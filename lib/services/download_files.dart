import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/track.dart';

export '../models/track.dart' show youtubeVideoIdOf;

/// What the files of the songs downloaded from YouTube look like on disk.
class DownloadScan {
  const DownloadScan({required this.bytes, required this.missing});

  /// Total size of the downloaded files that are still there.
  final int bytes;

  /// Downloaded songs whose file is gone (deleted elsewhere, or lost with a reinstall).
  final List<Track> missing;
}

/// The songs of [library] that were downloaded from YouTube: a file on this
/// device that remembers the video it came from. Streamed songs are not files.
List<Track> downloadedFrom(Iterable<Track> library) => [
  for (final t in library)
    if (!t.streams && t.path != null && t.offlineId != null) t,
];

/// Looks at the files of [downloads] without blocking: sums the sizes of the
/// ones that exist and lists the ones that don't.
///
/// A song counts as missing only when no other entry for the same video has a
/// file: downloading again in another format makes a new entry, and the old
/// one is then just a leftover, not something to fix.
Future<DownloadScan> scanDownloads(Iterable<Track> downloads) async {
  final tracks = downloads.toList();
  final sizes = await Future.wait([for (final t in tracks) _sizeOf(t.path!)]);
  final present = <String>{};
  var bytes = 0;
  for (var i = 0; i < tracks.length; i++) {
    final size = sizes[i];
    if (size == null) continue;
    bytes += size;
    if (tracks[i].offlineId case final id?) present.add(id);
  }
  return DownloadScan(
    bytes: bytes,
    missing: [
      for (var i = 0; i < tracks.length; i++)
        if (sizes[i] == null && !present.contains(tracks[i].offlineId)) tracks[i],
    ],
  );
}

/// The size of a file, or null when it isn't there or can't be read.
Future<int?> _sizeOf(String path) async {
  try {
    return await File(path).length();
  } on FileSystemException {
    return null;
  }
}

/// A size for people: "850 KB", "12.4 MB", "1.2 GB".
String formatFileSize(int bytes) {
  const kb = 1024;
  const mb = kb * 1024;
  const gb = mb * 1024;
  if (bytes < kb) return '$bytes B';
  if (bytes < mb) return '${(bytes / kb).round()} KB';
  if (bytes < gb) return '${(bytes / mb).toStringAsFixed(1)} MB';
  return '${(bytes / gb).toStringAsFixed(1)} GB';
}

/// "Artist - Title" for a downloaded file: what people recognise in their music folder, without the characters
/// Windows, macOS, Android or Linux refuse in a file name, and not too long for any of them.
String readableDownloadName({required String artist, required String title}) {
  String clean(String s) => s
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final a = clean(artist), t = clean(title);
  var name = a.isEmpty || a == Track.unknownArtist ? t : (t.isEmpty ? a : '$a - $t');
  if (name.length > 150) name = name.substring(0, 150).trim();
  // Windows drops trailing dots and spaces, and reserves a few device names.
  name = name.replaceAll(RegExp(r'[. ]+$'), '');
  if (RegExp(r'^(con|prn|aux|nul|com\d|lpt\d)$', caseSensitive: false).hasMatch(name)) name = '$name song';
  return name.isEmpty ? 'Song' : name;
}

/// [file] moved, in its folder, to the [readableDownloadName] of the song, "(2)", "(3)"... added when the name is
/// taken. The song's identity lives in its tags and the library, never in the file name, so any name works; when
/// the rename fails the file keeps its own.
Future<File> nameDownload(File file, {required String artist, required String title}) async {
  final dir = file.parent.path;
  final ext = p.extension(file.path);
  final base = readableDownloadName(artist: artist, title: title);
  for (var n = 1; n < 100; n++) {
    final target = File(p.join(dir, n == 1 ? '$base$ext' : '$base ($n)$ext'));
    if (target.path == file.path) return file;
    if (await target.exists()) continue;
    try {
      return await file.rename(target.path);
    } on FileSystemException {
      return file;
    }
  }
  return file;
}

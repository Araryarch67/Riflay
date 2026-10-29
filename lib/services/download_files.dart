import 'dart:io';

import '../models/track.dart';

/// What the files of the songs downloaded from YouTube look like on disk.
class DownloadScan {
  const DownloadScan({required this.bytes, required this.missing});

  /// Total size of the downloaded files that are still there.
  final int bytes;

  /// Downloaded songs whose file is gone (deleted elsewhere, or lost with a reinstall).
  final List<Track> missing;
}

/// The video id in a YouTube link: `watch?v=<id>` or `youtu.be/<id>`.
String? youtubeVideoIdOf(String? url) {
  final u = url == null ? null : Uri.tryParse(url);
  if (u == null) return null;
  return u.queryParameters['v'] ?? (u.host.endsWith('youtu.be') ? u.pathSegments.firstOrNull : null);
}

/// The songs of [library] that were downloaded from YouTube: a file on this
/// device that remembers the video it came from. Streamed songs are not files.
List<Track> downloadedFrom(Iterable<Track> library) => [
  for (final t in library)
    if (!t.isRemote && t.path != null && youtubeVideoIdOf(t.sourceUrl) != null) t,
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
    if (youtubeVideoIdOf(tracks[i].sourceUrl) case final id?) present.add(id);
  }
  return DownloadScan(
    bytes: bytes,
    missing: [
      for (var i = 0; i < tracks.length; i++)
        if (sizes[i] == null && !present.contains(youtubeVideoIdOf(tracks[i].sourceUrl))) tracks[i],
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

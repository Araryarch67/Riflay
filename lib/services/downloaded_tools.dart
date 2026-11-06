import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'executable_store.dart';
import 'ffmpeg.dart';
import 'ytdlp.dart';

class DownloadedTool {
  const DownloadedTool({required this.name, required this.path, required this.bytes});

  final String name;
  final String path;
  final int bytes;
}

class DeleteToolsResult {
  const DeleteToolsResult({required this.removed, required this.failed});

  final int removed;
  final int failed;
}

/// Only Riflay's downloaded tools in its own bin folder; never scans PATH or installation folders.
class DownloadedTools {
  DownloadedTools({Future<Directory> Function()? directory}) : _directory = directory ?? ExecutableStore.directory;

  final Future<Directory> Function() _directory;
  static const _names = {
    'ffmpeg': 'FFmpeg',
    'ffmpeg.exe': 'FFmpeg',
    'yt-dlp.exe': 'yt-dlp',
    'yt-dlp_linux': 'yt-dlp',
    'yt-dlp_macos': 'yt-dlp',
  };

  Future<List<DownloadedTool>> scan() => ExecutableStore.run(_scan);

  Future<List<DownloadedTool>> _scan() async {
    final dir = await _directory();
    if (await FileSystemEntity.type(dir.path, followLinks: false) != FileSystemEntityType.directory) return [];
    final found = <DownloadedTool>[];
    await for (final entry in dir.list(followLinks: false)) {
      if (entry is! File) continue;
      final fileName = p.basename(entry.path);
      final name = _names[fileName.endsWith('.part') ? fileName.substring(0, fileName.length - 5) : fileName];
      if (name == null) continue;
      final stat = await entry.stat();
      found.add(DownloadedTool(name: name, path: entry.path, bytes: stat.size));
    }
    found.sort((a, b) => a.path.compareTo(b.path));
    return found;
  }

  Future<DeleteToolsResult> deleteAll() => ExecutableStore.run(() async {
    var removed = 0, failed = 0;
    for (final tool in await _scan()) {
      try {
        await File(tool.path).delete();
        removed++;
      } on FileSystemException catch (e) {
        failed++;
        debugPrint('Could not remove downloaded tool: $e');
      }
    }
    // A completed download's cached Future must not keep handing out a now-deleted path.
    Ffmpeg.forgetExecutable();
    YtDlp.forgetExecutable();
    return DeleteToolsResult(removed: removed, failed: failed);
  });
}

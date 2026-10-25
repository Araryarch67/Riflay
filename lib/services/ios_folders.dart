import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/track.dart';

/// Folders picked on iOS. The app may only read them through a security-scoped
/// bookmark, which the native side (`FolderAccess.swift`) keeps and reopens.
class IosFolders {
  static const _channel = MethodChannel('riflay/folders');

  /// The folder the user picked, readable from now on; null when they cancelled.
  static Future<String?> pick() => _channel.invokeMethod<String>('pick');

  /// Reopens every remembered folder. Returns old path -> current path (iOS can
  /// move a folder between launches); empty when nothing is remembered.
  static Future<Map<String, String>> restore() async {
    try {
      return await _channel.invokeMapMethod<String, String>('restore') ?? const {};
    } catch (e) {
      debugPrint('Could not reopen the music folders: $e');
      return const {};
    }
  }

  /// Points local [tracks] that live under an old folder in [moved] at that folder's current path.
  static List<Track> repoint(List<Track> tracks, Map<String, String> moved) {
    final changed = {
      for (final e in moved.entries)
        if (e.key != e.value) e.key: e.value,
    };
    if (changed.isEmpty) return tracks;
    return [for (final t in tracks) t.uri.isScheme('file') ? t.copyWith(uri: _repointUri(t.uri, changed)) : t];
  }

  static Uri _repointUri(Uri uri, Map<String, String> changed) {
    final path = uri.toFilePath();
    for (final e in changed.entries) {
      final dir = e.key.endsWith('/') ? e.key : '${e.key}/';
      if (path.startsWith(dir)) return Uri.file(e.value + path.substring(e.key.length));
    }
    return uri;
  }
}

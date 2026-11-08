import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_version.dart';
import '../platform/background.dart';
import 'play_history.dart';

/// A backup the user can keep and bring back: settings, playlists, the listening history and their own lyrics,
/// in one JSON file. Sign-ins (YouTube Music, Spotify, Last.fm, keys for lyrics services) are never in it, so the
/// file is safe to keep in a synced folder; they are connected again after a restore.
///
/// ```
/// {"riflay_backup":1, "version":"1.6.4", "created":"2026-10-31T…",
///  "prefs":{"playlists.v1":{"s":"…"}, "volume.v1":{"d":0.8}, …},
///  "history":"<listening_history.jsonl>",
///  "lyrics":{"<video id>.lrc":"…"}}
/// ```
abstract final class Backup {
  static const format = 1;

  /// Preferences that are secrets or belong to this one device, and so are left out of a backup and kept as they
  /// are by a restore.
  static const _kept = {
    'appearance.matugenPath',
    'lyrics.betterLyricsKey',
    'youtube.visitor.v1',
    'power.batteryAsked.v1',
    'wrap.scheduled',
    'library.v1',
    'library.file.v1',
    'soundcloud.clientId.v1',
  };
  static const _keptPrefixes = ['musixmatch.'];

  static bool _backedUp(String key) => !_kept.contains(key) && !_keptPrefixes.any(key.startsWith);

  /// Lyrics files past this size aren't lyrics and stay out.
  static const _maxLyrics = 1 << 20;

  /// The backup's file name for [now], such as `riflay-backup-2026-10-31.json`.
  static String fileName([DateTime? now]) {
    final d = now ?? DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return 'riflay-backup-${d.year}-${two(d.month)}-${two(d.day)}.json';
  }

  /// Tests point this at a folder of their own (the lyrics folder lives in it).
  @visibleForTesting
  static Directory? dirOverride;

  static Future<Directory?> _lyricsDir() async {
    try {
      final base = dirOverride ?? await getApplicationSupportDirectory();
      return Directory(p.join(base.path, 'my-lyrics'));
    } catch (_) {
      return null;
    }
  }

  /// Everything to back up, as the file's text.
  static Future<String> create({PlayHistory? history}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final saved = <String, Object>{};
    for (final key in prefs.getKeys().toList()..sort()) {
      if (!_backedUp(key)) continue;
      final v = prefs.get(key);
      final typed = switch (v) {
        final bool b => {'b': b},
        final int i => {'i': i},
        final double d => {'d': d},
        final String s => {'s': s},
        final List<dynamic> l => {'l': l.cast<String>()},
        _ => null,
      };
      if (typed != null) saved[key] = typed;
    }
    final path = (await _lyricsDir())?.path;
    final lyrics = path == null ? const <String, String>{} : await inBackground(() => _readLyrics(path));
    final data = {
      'riflay_backup': format,
      'version': appVersion,
      'created': DateTime.now().toUtc().toIso8601String(),
      'prefs': saved,
      'history': await (history ?? PlayHistory.instance).exportText(),
      'lyrics': lyrics,
    };
    // The history alone can be a few megabytes of text.
    return inBackground(() => jsonEncode(data));
  }

  /// The user's own lyrics files in [path], by name (run in the background).
  static Map<String, String> _readLyrics(String path) {
    final dir = Directory(path);
    if (!dir.existsSync()) return const {};
    return {
      for (final f in dir.listSync().whereType<File>())
        if (f.path.endsWith('.lrc') && f.lengthSync() <= _maxLyrics) p.basename(f.path): f.readAsStringSync(),
    };
  }

  /// What a backup holds, to show before it is restored. Throws [FormatException] when [text] isn't a backup.
  static BackupSummary read(String text) {
    final Object? j;
    try {
      j = jsonDecode(text);
    } catch (_) {
      throw const FormatException('Not a Riflay backup');
    }
    if (j is! Map<String, dynamic> || j['riflay_backup'] is! int || j['prefs'] is! Map) {
      throw const FormatException('Not a Riflay backup');
    }
    if ((j['riflay_backup'] as int) > format) throw const FormatException('Made by a newer Riflay');
    final prefs = j['prefs'] as Map;
    final playlists = switch (prefs['playlists.v1']) {
      {'s': final String s} => _count(s),
      _ => 0,
    };
    final history = j['history'] is String ? PlayHistory.playsIn(j['history'] as String) : 0;
    return BackupSummary(
      created: DateTime.tryParse(j['created'] as String? ?? '')?.toLocal(),
      playlists: playlists,
      plays: history,
      lyrics: (j['lyrics'] as Map?)?.length ?? 0,
      data: j,
    );
  }

  static int _count(String json) {
    try {
      final v = jsonDecode(json);
      return v is List ? v.length : 0;
    } catch (_) {
      return 0;
    }
  }

  /// Puts [backup] in place of this device's settings, playlists, history and lyrics. Settings the backup doesn't
  /// name go back to their defaults; sign-ins stay. The app should start again afterwards, so every part reads it.
  static Future<void> restore(BackupSummary backup, {PlayHistory? history}) async {
    final j = backup.data;
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().toList()) {
      if (_backedUp(key)) await prefs.remove(key);
    }
    for (final MapEntry(:key, :value) in (j['prefs'] as Map).entries) {
      if (key is! String || !_backedUp(key) || value is! Map || value.length != 1) continue;
      switch (value.entries.single) {
        case MapEntry(key: 'b', value: final bool v):
          await prefs.setBool(key, v);
        case MapEntry(key: 'i', value: final int v):
          await prefs.setInt(key, v);
        case MapEntry(key: 'd', value: final num v):
          await prefs.setDouble(key, v.toDouble());
        case MapEntry(key: 's', value: final String v):
          await prefs.setString(key, v);
        case MapEntry(key: 'l', value: final List<dynamic> v):
          await prefs.setStringList(key, v.whereType<String>().toList());
      }
    }
    if (j['history'] case final String text) await (history ?? PlayHistory.instance).replaceWith(text);
    if (j['lyrics'] case final Map<String, dynamic> lyrics) {
      final dir = await _lyricsDir();
      if (dir != null) {
        await dir.create(recursive: true);
        for (final MapEntry(:key, :value) in lyrics.entries) {
          // Only a plain file name: a backup never writes outside the lyrics folder.
          if (value is! String || p.basename(key) != key || !key.endsWith('.lrc')) continue;
          await File(p.join(dir.path, key)).writeAsString(value);
        }
      }
    }
  }
}

/// What [Backup.read] found in a backup file.
class BackupSummary {
  const BackupSummary({
    required this.created,
    required this.playlists,
    required this.plays,
    required this.lyrics,
    required this.data,
  });

  final DateTime? created;
  final int playlists;
  final int plays;
  final int lyrics;
  final Map<String, dynamic> data;
}

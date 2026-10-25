import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Riflay was called OpenMusic before 2.0, under other app ids, so its files
/// live in other folders. On a computer, Riflay's first start brings them
/// over: settings, library, playlists, the YouTube Music sign-in, the room
/// correction file and the plugins project are copied, and the downloads
/// folder (`Documents/OpenMusic`) becomes `Documents/Riflay`. Paths saved in
/// them are pointed at the new places. Android and iOS keep each app's files
/// to itself, so a phone starts afresh.
abstract final class LegacyData {
  static const _oldId = 'dev.openmusic.openmusic';
  static const _marker = '.from-old-name';

  /// Runs once, before anything reads the settings. Never throws: a failure
  /// only means starting afresh, as on a phone.
  static Future<void> bringOver() async {
    if (!(Platform.isLinux || Platform.isWindows || Platform.isMacOS)) return;
    try {
      final support = await getApplicationSupportDirectory();
      final old = Directory(oldSupportPath(support.path));
      if (!old.existsSync() || File(p.join(support.path, _marker)).existsSync()) return;
      final docs = (await getApplicationDocumentsDirectory()).path;
      await bringOverFrom(
        old,
        support,
        oldDownloads: Directory(p.join(docs, 'OpenMusic')),
        downloads: Directory(p.join(docs, 'Riflay')),
      );
      if (Platform.isMacOS) await _bringOverMacPreferences(old.path, support.path);
      if (Platform.isLinux) await _bringOverPluginsProject();
    } catch (e) {
      debugPrint('Bringing over the old app\'s data: $e');
    }
  }

  /// The old app's support folder beside Riflay's [support]: `…/dev.openmusic.openmusic`
  /// on Linux and macOS, `…\dev.openmusic\openmusic` on Windows (company \ product).
  @visibleForTesting
  static String oldSupportPath(String support, {bool? windows}) => (windows ?? Platform.isWindows)
      ? p.windows.join(p.windows.dirname(p.windows.dirname(support)), 'dev.openmusic', 'openmusic')
      : p.join(p.dirname(support), _oldId);

  /// Copies [old] into [support] and moves [oldDownloads] to [downloads], then
  /// points the paths saved in the copied files at the new places. Leaves
  /// everything as it is when Riflay already has a library or settings there.
  @visibleForTesting
  static Future<void> bringOverFrom(
    Directory old,
    Directory support, {
    required Directory oldDownloads,
    required Directory downloads,
  }) async {
    await support.create(recursive: true);
    final marker = File(p.join(support.path, _marker));
    final ownData = ['library.json', 'shared_preferences.json', 'youtube_music_account.json'];
    if (ownData.any((f) => File(p.join(support.path, f)).existsSync())) {
      await marker.writeAsString('');
      return;
    }
    await _copy(old, support);
    final moves = <String, String>{old.path: support.path};
    if (oldDownloads.existsSync() && !downloads.existsSync()) {
      try {
        await oldDownloads.rename(downloads.path);
        moves[oldDownloads.path] = downloads.path;
      } catch (e) {
        debugPrint('Moving the downloads folder: $e'); // the songs stay where they were, and still play
      }
    }
    for (final f in support.listSync().whereType<File>().where((f) => f.path.endsWith('.json'))) {
      final text = await f.readAsString();
      final moved = moves.entries.fold(text, (t, m) => repoint(t, m.key, m.value));
      if (moved != text) await f.writeAsString(moved, flush: true);
    }
    await marker.writeAsString('');
  }

  /// Every file under [from] into [to]. On Linux and macOS with `cp`, which
  /// keeps each file's mode: the sign-in stays readable by this user only.
  static Future<void> _copy(Directory from, Directory to) async {
    if (!Platform.isWindows) {
      final r = await Process.run('cp', ['-pR', '${from.path}/.', to.path]);
      if (r.exitCode == 0) return;
    }
    await for (final e in from.list(recursive: true, followLinks: false)) {
      final target = p.join(to.path, p.relative(e.path, from: from.path));
      if (e is Directory) {
        await Directory(target).create(recursive: true);
      } else if (e is File) {
        await File(target).parent.create(recursive: true);
        await e.copy(target);
      }
    }
  }

  /// [text] (JSON, maybe holding JSON in its strings, or a property list) with
  /// paths under [from] moved under [to]: as plain paths, escaped once or twice
  /// (settings keep JSON inside JSON), and as `file://` URIs (song ids).
  @visibleForTesting
  static String repoint(String text, String from, String to, {bool? windows}) {
    final win = windows ?? Platform.isWindows;
    final sep = win ? r'\' : '/';
    String escaped(String s) {
      final e = jsonEncode(s);
      return e.substring(1, e.length - 1);
    }

    final fromDir = '$from$sep', toDir = '$to$sep';
    final forms = <(String, String)>[
      (escaped(escaped(fromDir)), escaped(escaped(toDir))),
      (escaped(fromDir), escaped(toDir)),
      (fromDir, toDir),
      (Uri.file(fromDir, windows: win).toString(), Uri.file(toDir, windows: win).toString()),
    ];
    for (final (a, b) in forms) {
      text = text.replaceAll(a, b);
    }
    return text;
  }

  /// macOS keeps the settings in the user defaults of each app id.
  static Future<void> _bringOverMacPreferences(String oldSupport, String support) async {
    final file = File(p.join(Directory.systemTemp.path, 'riflay-defaults-$pid.plist'));
    try {
      if ((await Process.run('defaults', ['export', _oldId, file.path])).exitCode != 0) return;
      // As text, to point the paths in it at the new folder.
      if ((await Process.run('plutil', ['-convert', 'xml1', file.path])).exitCode != 0) return;
      await file.writeAsString(repoint(await file.readAsString(), oldSupport, support));
      await Process.run('defaults', ['import', 'dev.riflay.riflay', file.path]);
    } finally {
      if (file.existsSync()) file.deleteSync();
    }
  }

  /// Linux: the audio plugins project Carla edits (see AudioEngine.pluginsProject).
  static Future<void> _bringOverPluginsProject() async {
    final env = Platform.environment;
    final config = (env['XDG_CONFIG_HOME'] ?? '').isNotEmpty ? env['XDG_CONFIG_HOME']! : '${env['HOME']}/.config';
    final old = Directory(p.join(config, 'openmusic')), now = Directory(p.join(config, 'riflay'));
    if (old.existsSync() && !now.existsSync()) await _copy(old, await now.create(recursive: true));
  }
}

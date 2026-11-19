import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';
import '../services/player_controller.dart';
import '../services/language.dart';
import '../platform/host.dart';
import 'widgets/item_picker.dart';
import 'widgets/app_dialog.dart';
import 'widgets/controls.dart';

Future<String?> _input(BuildContext context, String label, String initial) {
  var value = initial;
  return showDialog<String>(
    context: context,
    builder: (dialog) => AppDialog(
      title: label,
      content: TextFormField(initialValue: initial, autofocus: true, onChanged: (v) => value = v),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialog), child: Text(tr.cancel)),
        FilledButton(onPressed: () => Navigator.pop(dialog, value.trim()), child: Text(tr.save)),
      ],
    ),
  );
}

Future<void> playlistTools(BuildContext context, PlayerController c, String id, String name, List<Track> tracks) async {
  final options = [
    if (tracks.isNotEmpty) ...[tr.copyThrough, tr.trackNote],
    if (c.playlists.length > 1) tr.compareLists,
    if (!Host.isWeb &&
        (Host.isWindows || Host.isMacOS || Host.isLinux) &&
        tracks.any((t) => (c.downloadedCopy(t) ?? t).path != null))
      tr.exportRelative,
  ];
  final action = await pickListItem(context, tr.playlistTools, options, (s) => s);
  if (action == null || !context.mounted) return;
  if (action == tr.exportRelative) {
    try {
      final folder = await FilePicker.getDirectoryPath(dialogTitle: tr.exportRelative);
      if (folder == null) return;
      final base = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
      var target = File(p.join(folder, '$base.m3u8'));
      for (var n = 2; await target.exists(); n++) {
        target = File(p.join(folder, '$base ($n).m3u8'));
      }
      await target.create(exclusive: true);
      final lines = [
        '#EXTM3U',
        for (final t in tracks)
          if ((c.downloadedCopy(t) ?? t).path case final file?) p.relative(file, from: folder),
      ];
      await target.writeAsString('${lines.join('\n')}\n');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.songsPlural(lines.length - 1))));
      }
    } catch (_) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.couldntSaveBackup)));
    }
    return;
  }
  if (action == tr.compareLists) {
    final other = await pickListItem(
      context,
      tr.compareLists,
      c.playlists.where((pl) => pl.id != id).toList(),
      (pl) => pl.name,
    );
    if (other == null || !context.mounted) return;
    final ours = tracks.map((t) => t.id).toSet(), theirs = other.tracks.map((t) => t.id).toSet();
    await showDialog<void>(
      context: context,
      builder: (dialog) => AppDialog(
        title: tr.compareLists,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final group in [
              (tr.inBoth, tracks.where((t) => theirs.contains(t.id))),
              (name, tracks.where((t) => !theirs.contains(t.id))),
              (other.name, other.tracks.where((t) => !ours.contains(t.id))),
            ]) ...[
              Text('${group.$1} (${group.$2.length})', style: Theme.of(dialog).textTheme.titleMedium),
              SelectableText(group.$2.map((t) => '${t.artist} — ${t.title}').join('\n')),
            ],
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: Text(tr.close))],
      ),
    );
    return;
  }
  final t = await pickListItem(context, action, tracks, (t) => t.title, subtitle: (t) => t.artist);
  if (t == null || !context.mounted) return;
  if (action == tr.copyThrough) {
    final title = await _input(context, tr.saveAsPlaylist, '$name · ${t.title}');
    if (title != null && title.isNotEmpty) c.createPlaylist(title, tracks: tracks.sublist(0, tracks.indexOf(t) + 1));
  } else {
    final prefs = await SharedPreferences.getInstance();
    final key = 'playlist.note.${jsonEncode([id, t.id])}';
    if (!context.mounted) return;
    final note = await _input(context, tr.trackNote, prefs.getString(key) ?? '');
    if (note != null) {
      if (note.isEmpty) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, note);
      }
    }
  }
}

Future<void> songBookmarks(BuildContext context, PlayerController c, Track t) async {
  final prefs = await SharedPreferences.getInstance();
  final key = 'bookmarks.${t.id}';
  final marks = (jsonDecode(prefs.getString(key) ?? '{}') as Map).cast<String, String>();
  if (!context.mounted || c.currentTrack?.id != t.id) return;
  final position = c.position;
  final picked = await pickListItem(
    context,
    tr.songBookmarks,
    [-1, ...marks.keys.map(int.parse).toList()..sort()],
    (ms) => ms < 0
        ? '${tr.addBookmark} · ${formatDuration(position)}'
        : '${formatDuration(Duration(milliseconds: ms))} · ${marks[ms.toString()]}',
  );
  if (picked == null || !context.mounted || c.currentTrack?.id != t.id) return;
  if (picked >= 0) {
    await c.seek(Duration(milliseconds: picked));
    return;
  }
  final label = await _input(context, tr.addBookmark, '');
  if (label == null || label.isEmpty) return;
  marks[position.inMilliseconds.toString()] = label;
  await prefs.setString(key, jsonEncode(marks));
}

Future<void> copyTrackTime(PlayerController c, Track t) async {
  final id = t.videoId ?? t.onYoutube?.videoId;
  if (id == null || c.currentTrack?.id != t.id) return;
  await Clipboard.setData(
    ClipboardData(
      text: Uri.https('music.youtube.com', '/watch', {'v': id, 't': '${c.position.inSeconds}s'}).toString(),
    ),
  );
}

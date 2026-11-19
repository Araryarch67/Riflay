import 'dart:io';

import 'package:flutter/material.dart';

import '../services/language.dart';
import '../services/download_files.dart';
import '../services/download_prefs.dart';
import '../services/youtube_stream.dart';
import '../services/youtube_importer.dart';
import '../services/player_controller.dart';
import '../models/track.dart';
import 'download_options.dart';
import 'download_source_dialog.dart';
import 'widgets/app_dialog.dart';

Future<int?> _freeSpace() async {
  try {
    final dir = await YoutubeImporter.downloadsDir();
    if (Platform.isWindows) {
      final result = await Process.run(
        'powershell.exe',
        ['-NoProfile', '-NonInteractive', '-Command', r'(Get-Item -LiteralPath $env:RIFLAY_SPACE_PATH).PSDrive.Free'],
        environment: {'RIFLAY_SPACE_PATH': dir.path},
      );
      return int.tryParse(result.stdout.toString().trim());
    }
    final result = await Process.run('df', ['-Pk', dir.path]);
    final cols = result.stdout.toString().trim().split('\n').last.trim().split(RegExp(r'\s+'));
    return int.parse(cols[3]) * 1024;
  } catch (_) {
    return null;
  }
}

Future<void> playlistOffline(BuildContext context, PlayerController c, List<Track> tracks) async {
  final missing = <Track>[];
  var ready = 0;
  for (final t in tracks) {
    final file = (c.downloadedCopy(t) ?? t).path;
    if (file != null && await File(file).exists()) {
      ready++;
      continue;
    }
    if (t.isRemote || t.monochromeId != null || t.extensionId != null) missing.add(t);
  }
  if (!context.mounted) return;
  final prefs = DownloadPrefs.instance;
  await prefs.load();
  final choice = prefs.choice;
  final free = await _freeSpace();
  if (!context.mounted) return;
  int bytes = 0, known = 0;
  bool estimating = false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (inner, update) => AppDialog(
        title: tr.offlineReady,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$ready / ${tracks.length}'),
            if (free != null) Text('${tr.availableSpace}: ${formatFileSize(free)}'),
            if (!choice.isVideo && prefs.source == 'youtube' && missing.any((t) => t.isRemote))
              TextButton(
                onPressed: estimating
                    ? null
                    : () async {
                        update(() {
                          estimating = true;
                          bytes = 0;
                          known = 0;
                        });
                        for (final t in missing) {
                          if (!inner.mounted) return;
                          if (t.videoId == null) continue;
                          try {
                            final value = estimateDownloadBytes(
                              await YoutubeStream.downloadCandidates(t.videoId!),
                              choice,
                              canReencode: YoutubeImporter.canReencode,
                            );
                            if (value != null && inner.mounted) {
                              update(() {
                                bytes += value;
                                known++;
                              });
                            }
                          } catch (_) {
                            continue;
                          }
                        }
                        if (inner.mounted) update(() => estimating = false);
                      },
                child: Text(
                  '${tr.spaceEstimate}: ${known == 0 ? "—" : formatFileSize(bytes)} ($known/${missing.length})',
                ),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: Text(tr.close)),
          if (missing.isNotEmpty)
            FilledButton(onPressed: () => Navigator.pop(dialog, true), child: Text(tr.downloadMissing)),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  final youtube = missing.where((t) => t.isRemote).toList();
  if (youtube.isNotEmpty) {
    if (prefs.source == 'youtube') {
      final format = await chooseDownload(context);
      if (format == null) return;
      c.youtube.enqueueTracks(youtube, choice: format);
    } else {
      for (final t in youtube) {
        if (!context.mounted || !await downloadFromSource(context, c, t)) return;
      }
    }
  }
  c.youtube.enqueueTracks(missing.where((t) => t.monochromeId != null).toList());
  if (context.mounted && missing.any((t) => t.extensionId != null)) {
    await downloadExtensionTracks(context, c, missing.where((t) => t.extensionId != null).toList());
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/track.dart';
import '../platform/features.dart';
import '../services/player_controller.dart';
import '../services/playlist_transfer.dart';
import '../services/monochrome.dart';
import '../services/youtube_music_account.dart';
import 'theme.dart';
import 'widgets/item_picker.dart';
import 'widgets/skeleton.dart';
import '../services/language.dart';
import 'widgets/app_dialog.dart';
import 'widgets/how_to_steps.dart';

Future<({List<Track> tracks, int total})> readLocalM3u(String file) async {
  final data = await _inspectM3u(file, {});
  return (tracks: data.tracks, total: data.total);
}

Future<({List<Track> tracks, int total, List<String> absent, int duplicates})> _inspectM3u(
  String file,
  Map<String, String> folders,
) async {
  final absent = <String>[];
  var duplicates = 0;
  final tracks = <Track>[];
  final seen = <String>{};
  var total = 0;
  final bytes = await File(file).readAsBytes();
  final contents = utf8.decode(bytes, allowMalformed: true);
  if (contents.contains(RegExp(r'^#EXT-X-', multiLine: true))) throw const FormatException();
  for (final raw in const LineSplitter().convert(contents)) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    total++;
    final uri = Uri.tryParse(line);
    final local = path.isAbsolute(line)
        ? line
        : uri?.scheme == 'file'
        ? uri!.toFilePath()
        : uri?.hasScheme == true
        ? null
        : path.join(path.dirname(file), line);
    if (local == null) {
      absent.add(line);
      continue;
    }
    var audio = File(path.normalize(local));
    if (!await audio.exists()) {
      for (final folder in folders.entries) {
        if (path.isWithin(folder.key, audio.path)) {
          audio = File(path.join(folder.value, path.relative(audio.path, from: folder.key)));
          break;
        }
      }
    }
    if (!await audio.exists()) {
      absent.add(local);
      continue;
    }
    if (seen.add(audio.uri.toString())) {
      tracks.add(Track.fromUri(audio.uri));
    } else {
      duplicates++;
    }
  }
  return (tracks: tracks, total: total, absent: absent, duplicates: duplicates);
}

List<ForeignSong> parsePlaylistCsv(String contents) {
  final rows = <List<String>>[];
  var row = <String>[], field = StringBuffer(), quoted = false;
  final first = contents.split('\n').first;
  final separator = first.contains(',') ? ',' : ';';
  for (var i = 0; i < contents.length; i++) {
    final c = contents[i];
    if (c == '"') {
      if (quoted && i + 1 < contents.length && contents[i + 1] == '"') {
        field.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (!quoted && c == separator) {
      row.add(field.toString().trim());
      field = StringBuffer();
    } else if (!quoted && (c == '\n' || c == '\r')) {
      if (c == '\r' && i + 1 < contents.length && contents[i + 1] == '\n') i++;
      row.add(field.toString().trim());
      rows.add(row);
      row = [];
      field = StringBuffer();
    } else {
      field.write(c);
    }
  }
  if (quoted) throw const FormatException();
  row.add(field.toString().trim());
  rows.add(row);
  final header = rows.first.map((s) => s.toLowerCase().replaceAll(RegExp('[^a-z]'), '')).toList();
  final title = header.indexWhere({'title', 'track', 'trackname', 'tracktitle', 'song', 'songname', 'judul'}.contains);
  final artist = header.indexWhere({'artist', 'artists', 'artistname', 'artistnames', 'artis'}.contains);
  if (title < 0 || artist < 0) throw const FormatException();
  final songs = [
    for (final cells in rows.skip(1))
      if (cells.length > title && cells.length > artist && cells[title].isNotEmpty)
        ForeignSong(title: cells[title], artist: cells[artist]),
  ];
  if (songs.isEmpty) throw const FormatException();
  return songs;
}

/// Where an imported playlist was saved.
typedef ImportedPlaylist = ({String title, String? youtubeId, UserPlaylist? local});

/// "Import a playlist": asks for a Spotify, Apple Music or Deezer link, finds
/// its songs in YouTube Music and saves them as a playlist: in the YouTube
/// Music library when signed in, as a Riflay playlist otherwise.
/// Returns the playlist once the user asks to open it.
Future<ImportedPlaylist?> askToImportPlaylist(
  BuildContext context, {
  bool offerOpen = true,
  bool fromFile = false,
}) async {
  final c = PlayerScope.read(context);
  String? file;
  if (fromFile) {
    try {
      file = await _pickPlaylistFile();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(tr.m3uReadFailed)));
      }
      return null;
    }
    if (file == null || !context.mounted) return null;
  }
  final copied = fromFile ? null : (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim();
  if (!context.mounted) return null;
  final transfer = PlaylistTransfer();
  try {
    return await showDialog<ImportedPlaylist>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PlaylistImportDialog(
        initial: copied != null && PlaylistTransfer.looksLikeLink(copied) ? copied : null,
        initialFile: file,
        signedIn: c.ytMusic.canEdit,
        offerOpen: offerOpen,
        player: c,
        read: transfer.read,
        search: c.ytMusic.searchSongs,
        videos: c.ytMusic.searchVideos,
        save: (title, tracks) => saveImportedPlaylist(c, title, tracks),
      ),
    );
  } finally {
    transfer.close();
  }
}

Future<String?> _pickPlaylistFile() async {
  final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['m3u', 'm3u8', 'csv']);
  return picked.firstOrNull?.path;
}

/// Saves matched songs as a playlist. Signed in: a YouTube Music playlist (the
/// songs go in 100 at a time). Otherwise a Riflay playlist of the streamed songs.
/// Shared by the link importer and the Spotify library import.
Future<ImportedPlaylist> saveImportedPlaylist(PlayerController c, String title, List<Track> tracks) async {
  if (!c.ytMusic.canEdit || tracks.any((t) => !t.isRemote)) {
    return (title: title, youtubeId: null, local: c.createPlaylist(title, tracks: tracks));
  }
  final id = await c.ytMusic.createPlaylist(title, tracks: tracks.take(100).toList());
  for (var i = 100; i < tracks.length; i += 100) {
    await c.ytMusic.addToPlaylist(id, tracks.skip(i).take(100).toList());
  }
  return (title: title, youtubeId: id, local: null);
}

enum _Step { link, reading, matching, review, saving, done }

/// The steps of an import: the link, reading it, finding the songs, the result.
class PlaylistImportDialog extends StatefulWidget {
  const PlaylistImportDialog({
    super.key,
    required this.initial,
    this.initialFile,
    required this.signedIn,
    this.offerOpen = true,
    this.player,
    required this.read,
    required this.search,
    required this.videos,
    required this.save,
  });

  final String? initial;
  final String? initialFile;

  /// Where it's saved: the YouTube Music library, or Riflay playlists.
  final bool signedIn;
  final bool offerOpen;
  final PlayerController? player;
  final Future<ForeignPlaylist> Function(String link) read;
  final Future<List<Track>> Function(String query) search;
  final Future<List<Track>> Function(String query) videos;
  final Future<ImportedPlaylist> Function(String title, List<Track> tracks) save;

  @override
  State<PlaylistImportDialog> createState() => _PlaylistImportDialogState();
}

class _PlaylistImportDialogState extends State<PlaylistImportDialog> {
  late final link = TextEditingController(text: widget.initial);
  var step = _Step.link;
  String? error;
  ForeignPlaylist? playlist;
  var done = 0;

  /// Bumped by every start and cancel; an import whose number is old stops.
  var run = 0;
  List<ForeignSong> missing = const [];
  ImportedPlaylist? result;
  int saved = 0;

  List<Track> staged = [];
  UserPlaylist? target;
  List<Track> inserted = [];
  String? m3u;
  final folders = <String, String>{};
  List<String> absent = [];
  int duplicates = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialFile case final file?) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) importFile(file);
      });
    }
  }

  void review(ForeignPlaylist p, List<Track> songs, List<ForeignSong> failed) {
    setState(() {
      playlist = p;
      staged = songs.toList();
      missing = failed.toList();
      step = _Step.review;
    });
  }

  Future<void> inspectFile(String file) async {
    final data = await _inspectM3u(file, folders);
    if (!mounted || step != _Step.reading) return;
    m3u = file;
    absent = data.absent;
    duplicates = data.duplicates;
    review(
      ForeignPlaylist(title: path.basenameWithoutExtension(file), service: 'M3U', songs: [], total: data.total),
      data.tracks,
      [],
    );
  }

  Future<void> repairFolder() async {
    final roots = absent.where(path.isAbsolute).map(path.dirname).toSet().toList();
    final old = await pickListItem(context, tr.replaceFolder, roots, (p) => p);
    if (old == null) return;
    final newRoot = await FilePicker.getDirectoryPath();
    if (newRoot == null || !mounted) return;
    folders[old] = newRoot;
    setState(() => step = _Step.reading);
    try {
      await inspectFile(m3u!);
    } catch (_) {
      if (mounted) {
        setState(() {
          error = tr.m3uReadFailed;
          step = _Step.review;
        });
      }
    }
  }

  Future<void> retryMissing() async {
    final me = ++run;
    setState(() {
      step = _Step.matching;
      done = 0;
    });
    final retry = await PlaylistTransfer.match(
      missing,
      widget.search,
      videos: widget.videos,
      cancelled: () => !mounted || run != me,
      onProgress: (n) {
        if (mounted && run == me) setState(() => done = n);
      },
    );
    if (!mounted || me != run) return;
    final ids = staged.map((t) => t.id).toSet();
    review(playlist!, [...staged, ...retry.found.where((t) => ids.add(t.id))], retry.missing);
  }

  Future<void> replaceMatch() async {
    final old = await pickListItem(context, tr.replaceMatch, staged, (t) => t.title, subtitle: (t) => t.artist);
    if (old == null || !mounted) return;
    try {
      final hits = await widget.search('${old.title} ${old.artist}');
      if (!mounted) return;
      final pick = await pickListItem(context, tr.replaceMatch, hits, (t) => t.title, subtitle: (t) => t.artist);
      if (pick != null && mounted) setState(() => staged[staged.indexOf(old)] = pick);
    } catch (_) {
      if (mounted) setState(() => error = tr.downloadMatchFailed);
    }
  }

  Future<void> commitReview() async {
    setState(() {
      step = _Step.saving;
      error = null;
    });
    try {
      final player = widget.player;
      final dest = target;
      ImportedPlaylist where;
      if (dest != null && player != null) {
        final live = player.playlists.firstWhere((p) => p.id == dest.id);
        final existing = live.tracks.map((t) => t.id).toSet();
        inserted = staged.where((t) => existing.add(t.id)).toList();
        player.addToPlaylist(dest.id, inserted);
        where = (title: dest.name, youtubeId: null, local: dest);
      } else {
        where = await widget.save(playlist!.title, staged);
        inserted = staged;
      }
      if (mounted) {
        setState(() {
          saved = inserted.length;
          result = where;
          step = _Step.done;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = YoutubeMusicAccount.describe(e);
          step = _Step.review;
        });
      }
    }
  }

  Future<void> undoImport() async {
    final player = widget.player!;
    final where = result!;
    if (!await confirmDialog(context, title: tr.undoImportQuestion, body: where.title, confirmLabel: tr.undo)) return;
    if (!mounted) return;
    setState(() => step = _Step.saving);
    try {
      if (target != null) {
        for (final t in inserted) {
          player.removeFromPlaylist(target!.id, t);
        }
      } else if (where.local != null) {
        player.deletePlaylist(where.local!.id);
      } else {
        await player.ytMusic.deletePlaylist(where.youtubeId!);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = YoutubeMusicAccount.describe(e);
          step = _Step.done;
        });
      }
    }
  }

  bool get valid => PlaylistTransfer.looksLikeLink(link.text);

  @override
  void dispose() {
    run++;
    link.dispose();
    super.dispose();
  }

  Future<void> importFile([String? selected]) async {
    final me = ++run;
    var csv = false;
    setState(() {
      step = _Step.reading;
      error = null;
    });
    try {
      final file = selected ?? await _pickPlaylistFile();
      if (!mounted || me != run) return;
      if (file == null) {
        setState(() => step = _Step.link);
        return;
      }
      csv = path.extension(file).toLowerCase() == '.csv';
      if (csv) {
        final songs = parsePlaylistCsv(await File(file).readAsString());
        if (!mounted || me != run) return;
        final p = ForeignPlaylist(title: path.basenameWithoutExtension(file), service: 'CSV', songs: songs);
        m3u = null;
        setState(() {
          playlist = p;
          step = _Step.matching;
          done = 0;
        });
        final matched = await PlaylistTransfer.match(
          songs,
          widget.search,
          videos: widget.videos,
          cancelled: () => !mounted || me != run,
          onProgress: (n) {
            if (mounted && me == run) setState(() => done = n);
          },
        );
        if (mounted && me == run) review(p, matched.found, matched.missing);
        return;
      }
      folders.clear();
      await inspectFile(file);
    } catch (_) {
      if (mounted && me == run) {
        setState(() {
          error = csv ? tr.csvReadFailed : tr.m3uReadFailed;
          step = _Step.link;
        });
      }
    }
  }

  Future<void> start() async {
    if (!valid) return;
    final me = ++run;
    bool stale() => !mounted || me != run;
    setState(() {
      step = _Step.reading;
      error = null;
      done = 0;
    });
    try {
      final p = await widget.read(link.text);
      if (stale()) return;
      if (p.nativeTracks case final tracks?) {
        if (widget.player != null) {
          review(p, tracks, []);
          return;
        }
        setState(() {
          playlist = p;
          step = _Step.saving;
        });
        final where = await widget.save(p.title, tracks);
        if (stale()) return;
        setState(() {
          result = where;
          saved = tracks.length;
          missing = const [];
          step = _Step.done;
        });
        return;
      }
      setState(() {
        playlist = p;
        step = _Step.matching;
      });
      final r = await PlaylistTransfer.match(
        p.songs,
        widget.search,
        videos: widget.videos,
        cancelled: stale,
        onProgress: (n) {
          if (!stale()) setState(() => done = n);
        },
      );
      if (stale()) return;
      if (widget.player != null) {
        review(p, r.found, r.missing);
        return;
      }
      if (r.found.isEmpty) throw PlaylistTransferError(tr.noneOfItsSongsOnYt);
      setState(() => step = _Step.saving);
      final where = await widget.save(p.title, r.found);
      if (!mounted) return;
      setState(() {
        result = where;
        saved = r.found.length;
        missing = r.missing;
        step = _Step.done;
      });
    } catch (e) {
      if (stale()) return;
      setState(() {
        error = switch (e) {
          PlaylistTransferError(:final message) => message,
          _ => YoutubeMusicAccount.describe(e),
        };
        step = _Step.link;
      });
    }
  }

  /// Stops looking songs up and goes back to the link.
  void cancel() => setState(() {
    run++;
    step = _Step.link;
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final secondary = text.bodySmall?.copyWith(color: AppColors.textSecondary);
    final p = playlist;
    final signedIn = widget.signedIn && MonochromeLink.parse(link.text) == null;
    return AppDialog(
      title: Text(switch (step) {
        _Step.link => tr.importPlaylist,
        _Step.done => tr.importedNamed(result!.title),
        _ => p?.title ?? tr.importPlaylist,
      }),
      width: DialogWidth.regular,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: switch (step) {
          _Step.link => [
            if (Features.playlistFileImport)
              OutlinedButton.icon(
                onPressed: importFile,
                icon: const Icon(Icons.file_open_outlined),
                label: Text(tr.importPlaylistFile),
              ),
            Text(tr.pastePlaylistLink),
            const SizedBox(height: 4),
            Text(signedIn ? tr.becomesYtPlaylist : tr.becomesRiflayPlaylist, style: secondary),
            const SizedBox(height: 16),
            TextField(
              controller: link,
              autofocus: widget.initial == null,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() => error = null),
              onSubmitted: (_) => start(),
              decoration: InputDecoration(
                labelText: tr.playlistLink,
                border: const OutlineInputBorder(),
                errorMaxLines: 3,
                errorText: error ?? (link.text.trim().isNotEmpty && !valid ? tr.notAPlaylistLink : null),
              ),
            ),
            const SizedBox(height: 8),
            HowToSteps(inset: false, steps: [tr.howImport1, tr.howImport2, tr.howImport3]),
          ],
          _Step.review => [
            Text(
              tr.songsPlural(
                staged.map((t) => t.id).where((id) => !(target?.tracks.any((t) => t.id == id) ?? false)).toSet().length,
              ),
            ),
            if (error != null) Text(error!),
            if (m3u != null) ...[
              Text('${tr.duplicatesCount}: $duplicates · ${tr.missingFiles}: ${absent.length}'),
              if (absent.any(path.isAbsolute)) TextButton(onPressed: repairFolder, child: Text(tr.replaceFolder)),
            ] else if (playlist?.nativeTracks == null && staged.isNotEmpty)
              TextButton(onPressed: replaceMatch, child: Text(tr.replaceMatch)),
            if (missing.isNotEmpty) ...[
              Text(tr.songsNotOnYt(missing.length)),
              TextButton(onPressed: retryMissing, child: Text(tr.retryMissing)),
              TextButton(
                onPressed: () => Clipboard.setData(ClipboardData(text: missing.join('\n'))),
                child: Text(tr.copyMissing),
              ),
            ],
            if (widget.player?.playlists.isNotEmpty == true)
              ListTile(
                title: Text(tr.mergePlaylist),
                subtitle: Text(target?.name ?? tr.newPlaylist),
                trailing: target == null
                    ? null
                    : IconButton(onPressed: () => setState(() => target = null), icon: const Icon(Icons.close)),
                onTap: () async {
                  final selected = await pickListItem(
                    context,
                    tr.mergePlaylist,
                    widget.player!.playlists,
                    (p) => p.name,
                  );
                  if (selected != null && mounted) setState(() => target = selected);
                },
              ),
          ],
          _Step.reading => [
            Text(tr.readingPlaylist, style: secondary),
            const SizedBox(height: 16),
            const SkeletonBox(height: 8, radius: 4),
          ],
          _Step.matching || _Step.saving => [
            Text(
              step == _Step.saving ? tr.saving : tr.findingSongsInYt('$done', '${p!.songs.length}'),
              style: secondary,
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: step == _Step.saving || p == null || p.songs.isEmpty ? null : done / p.songs.length,
            ),
          ],
          _Step.done => [
            if (error != null) Text(error!),
            Text(
              result!.youtubeId != null
                  ? tr.songsAddedOfYt('$saved', '${p!.total}')
                  : tr.songsAddedOf('$saved', '${p!.total}'),
            ),
            if (p.service != 'M3U' && p.total > p.songs.length) ...[
              const SizedBox(height: 8),
              Text(tr.firstSongsOnly(p.songs.length, p.service), style: secondary),
            ],
            if (missing.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                missing.length == 1 ? tr.songsNotOnYt(1) : tr.songsNotOnYt(missing.length),
                style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 160),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final s in missing)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text('$s', maxLines: 1, overflow: TextOverflow.ellipsis, style: secondary),
                      ),
                  ],
                ),
              ),
            ],
          ],
        },
      ),
      actions: switch (step) {
        _Step.link => [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr.cancel)),
          FilledButton(onPressed: valid ? start : null, child: Text(tr.import)),
        ],
        _Step.review => [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr.cancel)),
          FilledButton(onPressed: staged.isEmpty ? null : commitReview, child: Text(tr.import)),
        ],
        _Step.saving => const [],
        _Step.done => [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr.close)),
          if (widget.player != null) TextButton(onPressed: undoImport, child: Text(tr.undoImport)),
          if (widget.offerOpen)
            FilledButton(onPressed: () => Navigator.pop(context, result), child: Text(tr.openPlaylist)),
        ],
        _ => [TextButton(onPressed: cancel, child: Text(tr.cancel))],
      },
    );
  }
}

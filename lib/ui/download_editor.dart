import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/track.dart';
import '../services/download_edit.dart';
import '../services/lyrics.dart';
import '../services/player_controller.dart';
import 'theme.dart';
import 'widgets/controls.dart';
import '../services/language.dart';

/// "Edit" for a downloaded song: title, album, cover and the person's own
/// lyrics. The artist is shown but can't be changed. A bottom sheet on phones,
/// a dialog elsewhere.
Future<void> showDownloadEditor(BuildContext context, Track track, {required bool compact}) async {
  final c = PlayerScope.read(context);
  final messenger = ScaffoldMessenger.of(context);
  final mine = await UserLyrics.read(track);
  if (!context.mounted) return;
  Future<String?> save(DownloadEdits edits) async {
    try {
      await DownloadEdit.apply(
        c,
        track,
        title: edits.title,
        album: edits.album,
        cover: edits.cover,
        coverMime: edits.coverMime,
      );
      if (edits.lyrics != null) {
        edits.lyrics!.trim().isEmpty ? await UserLyrics.remove(track) : await UserLyrics.save(track, edits.lyrics!);
      }
      messenger.showSnackBar(SnackBar(content: Text(tr.saved)));
      return null;
    } catch (e) {
      debugPrint('Saving a downloaded song failed: $e');
      return tr.couldntSaveChangesRetry;
    }
  }

  final form = DownloadEditForm(track: track, myLyrics: mine, onSave: save);
  if (compact) {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      backgroundColor: AppColors.elevated,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: form,
      ),
    );
  } else {
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (context) => Dialog(
        backgroundColor: AppColors.elevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: form),
      ),
    );
  }
}

/// What the person changed. [lyrics] is null when the lyrics were left alone,
/// and empty when they were removed.
class DownloadEdits {
  DownloadEdits({required this.title, required this.album, this.cover, this.coverMime = 'image/jpeg', this.lyrics});

  final String title;
  final String album;
  final Uint8List? cover;
  final String coverMime;
  final String? lyrics;
}

/// The form itself. [onSave] returns a sentence to show if it didn't work, null when done.
class DownloadEditForm extends StatefulWidget {
  const DownloadEditForm({super.key, required this.track, required this.onSave, this.myLyrics});

  final Track track;

  /// The lyrics the person saved earlier, if any.
  final String? myLyrics;
  final Future<String?> Function(DownloadEdits edits) onSave;

  @override
  State<DownloadEditForm> createState() => _DownloadEditFormState();
}

class _DownloadEditFormState extends State<DownloadEditForm> {
  late final _title = TextEditingController(text: widget.track.title);
  late final _album = TextEditingController(text: widget.track.album ?? '');
  late final _lyrics = TextEditingController(text: widget.myLyrics ?? '');
  late final _artist = TextEditingController(text: widget.track.artist);
  Uint8List? _cover;
  String _coverMime = 'image/jpeg';
  String? _problem;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _album.dispose();
    _lyrics.dispose();
    _artist.dispose();
    super.dispose();
  }

  Future<void> _pickCover() async {
    final file = (await FilePicker.pickFiles(type: FileType.image, dialogTitle: tr.chooseCoverArt)).firstOrNull;
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _cover = bytes;
      _coverMime = file.extension?.toLowerCase() == 'png' ? 'image/png' : 'image/jpeg';
    });
  }

  Future<void> _pickLyrics() async {
    final file = (await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['lrc', 'txt'],
      dialogTitle: tr.chooseLyricsFile,
    )).firstOrNull;
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    if (bytes.length > 1 << 20) {
      setState(() => _problem = tr.lyricsFileTooBig);
      return;
    }
    setState(() {
      _lyrics.text = utf8.decode(bytes, allowMalformed: true).replaceFirst('\u{feff}', '');
      _problem = null;
    });
  }

  Future<void> _save() async {
    final text = _lyrics.text;
    final changed = text.trim() != (widget.myLyrics ?? '').trim();
    if (changed && text.trim().isNotEmpty) {
      final check = Lyrics.check(text, length: widget.track.duration);
      if (!check.ok) {
        setState(() => _problem = check.problem);
        return;
      }
    }
    setState(() {
      _saving = true;
      _problem = null;
    });
    final problem = await widget.onSave(
      DownloadEdits(
        title: _title.text,
        album: _album.text,
        cover: _cover,
        coverMime: _coverMime,
        lyrics: changed ? text : null,
      ),
    );
    if (!mounted) return;
    if (problem == null) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _saving = false;
        _problem = problem;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: AppColors.textSecondary);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr.editSong, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox.square(
                  dimension: 72,
                  child: _cover != null
                      ? Image.memory(
                          _cover!,
                          key: const ValueKey('new-cover'),
                          fit: BoxFit.cover,
                          cacheWidth: (72 * dpr).round(),
                        )
                      : Artwork(track: widget.track, size: 72),
                ),
              ),
              const SizedBox(width: 16),
              OutlinedButton(onPressed: _pickCover, child: Text(tr.changeCover)),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            decoration: InputDecoration(labelText: tr.title, border: OutlineInputBorder(), isDense: true),
          ),
          const SizedBox(height: 12),
          // Shown, not editable: a download keeps the artist's name as released.
          TextField(
            key: const ValueKey('artist-field'),
            controller: _artist,
            readOnly: true,
            enableInteractiveSelection: false,
            decoration: InputDecoration(
              labelText: tr.artist,
              helperText: tr.artistNamesStay,
              helperStyle: muted,
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: Icon(Icons.lock_outline_rounded, size: 18, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _album,
            decoration: InputDecoration(labelText: tr.album, border: OutlineInputBorder(), isDense: true),
          ),
          const SizedBox(height: 20),
          Text(tr.yourLyrics, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(tr.yourLyricsBody, style: muted),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('lyrics-field'),
            controller: _lyrics,
            minLines: 4,
            maxLines: 8,
            decoration: InputDecoration(hintText: tr.pasteLyricsHere, border: OutlineInputBorder(), isDense: true),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              OutlinedButton(onPressed: _pickLyrics, child: Text(tr.addFromFile)),
              ListenableBuilder(
                listenable: _lyrics,
                builder: (context, _) => TextButton(
                  style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
                  onPressed: _lyrics.text.isEmpty ? null : () => setState(_lyrics.clear),
                  child: Text(tr.removeMyLyrics),
                ),
              ),
            ],
          ),
          if (_problem != null) ...[
            const SizedBox(height: 12),
            Text(_problem!, style: text.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: Text(tr.cancel)),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.inverse, foregroundColor: AppColors.onInverse),
                onPressed: _saving ? null : _save,
                child: Text(tr.save),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

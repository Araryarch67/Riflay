import 'package:flutter/material.dart';

import '../../services/language.dart';
import '../../services/player_controller.dart';
import '../../services/spoken_word.dart';
import '../theme.dart';
import 'controls.dart' show formatDuration;
import 'frosted.dart';

/// Audiobook / podcast, from the player's menu: remember this song's place and speed, jump 15 s back or 30 s on,
/// and keep bookmarks with a note.
Future<void> showAudiobook(BuildContext context) {
  final c = PlayerScope.read(context);
  return showAppSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.elevated,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => SafeArea(child: AudiobookPanel(player: c)),
  );
}

class AudiobookPanel extends StatelessWidget {
  const AudiobookPanel({super.key, required this.player});

  final PlayerController player;

  Future<void> _addBookmark(BuildContext context, String id) async {
    final note = TextEditingController();
    final at = player.position;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('${tr.bookmarkAdd} · ${formatDuration(at)}'),
        content: TextField(
          controller: note,
          autofocus: true,
          decoration: InputDecoration(hintText: tr.bookmarkNote),
          onSubmitted: (_) => Navigator.pop(d, true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr.cancel)),
          TextButton(onPressed: () => Navigator.pop(d, true), child: Text(tr.save)),
        ],
      ),
    );
    if (ok == true) await SpokenWord.instance.addBookmark(id, at, note.text);
    note.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spoken = SpokenWord.instance;
    final text = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: Listenable.merge([spoken, player.audio, player]),
      builder: (context, _) {
        final id = player.currentTrack?.id;
        if (id == null) return const SizedBox.shrink();
        final on = spoken.isBook(id);
        final marks = spoken.bookmarks(id);
        return SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                title: Text(tr.audiobookOn),
                subtitle: Text(tr.audiobookHint),
                value: on,
                onChanged: (v) => spoken.setBook(id, v),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: () => player.seekBy(-SpokenWord.jumpBack),
                    icon: const Icon(Icons.replay_rounded),
                    label: Text(tr.audiobookBack),
                  ),
                  const SizedBox(width: 12),
                  TextButton.icon(
                    onPressed: () => player.seekBy(SpokenWord.jumpForward),
                    icon: const Icon(Icons.forward_rounded),
                    label: Text(tr.audiobookForward),
                  ),
                ],
              ),
              if (on) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                  child: Row(
                    children: [
                      Expanded(child: Text(tr.audiobookSpeed, style: text.titleSmall)),
                      Text('${player.audio.tempo.toStringAsFixed(2)}×', style: text.titleSmall),
                    ],
                  ),
                ),
                // The same 0.5-2× the Tempo & pitch sheet allows; the controller keeps it for this book.
                Slider(
                  value: player.audio.tempo,
                  min: 0.5,
                  max: 2,
                  divisions: 30,
                  label: '${player.audio.tempo.toStringAsFixed(2)}×',
                  onChanged: player.audio.tempoPitchActive ? player.audio.setTempo : null,
                ),
                ListTile(
                  title: Text(tr.bookmarks, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  trailing: TextButton.icon(
                    onPressed: () => _addBookmark(context, id),
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: Text(tr.add),
                  ),
                ),
                if (marks.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                    child: Text(tr.bookmarksEmpty, style: text.bodySmall?.copyWith(color: AppColors.textSecondary)),
                  ),
                for (final m in marks)
                  ListTile(
                    leading: const Icon(Icons.bookmark_rounded),
                    title: Text(formatDuration(m.at)),
                    subtitle: m.note.isEmpty ? null : Text(m.note),
                    onTap: () => player.seek(m.at),
                    trailing: IconButton(
                      tooltip: tr.remove,
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => spoken.removeBookmark(id, m),
                    ),
                  ),
              ],
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/track.dart';
import '../../services/language.dart';
import '../../services/player_controller.dart';
import '../theme.dart';
import '../ytmusic_edit.dart' show addToPlaylist;

/// Songs picked on a page, to add them to a playlist or the queue together. Hold a row (or "Select" in its
/// menu) to start; while anything is picked, a tap on a row picks or unpicks it instead of playing.
class TrackSelection extends ChangeNotifier {
  final _ids = <String>{};

  bool get active => _ids.isNotEmpty;

  bool contains(Track t) => _ids.contains(t.id);

  void toggle(Track t) {
    if (!_ids.remove(t.id)) _ids.add(t.id);
    notifyListeners();
  }

  void selectAll(Iterable<Track> tracks) {
    _ids.addAll(tracks.map((t) => t.id));
    notifyListeners();
  }

  void clear() {
    if (_ids.isEmpty) return;
    _ids.clear();
    notifyListeners();
  }

  /// The picked songs of [tracks], in their order: a song no longer on the page drops out.
  List<Track> of(List<Track> tracks) => [
    for (final t in tracks)
      if (_ids.contains(t.id)) t,
  ];
}

/// Gives the rows below a [TrackSelection]. Rows read it without depending on it, and listen only where
/// they show it, so picking a song doesn't rebuild every row.
class TrackSelectionScope extends InheritedWidget {
  const TrackSelectionScope({super.key, required this.selection, required super.child});

  final TrackSelection selection;

  static TrackSelection? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<TrackSelectionScope>()?.selection;

  @override
  bool updateShouldNotify(TrackSelectionScope old) => selection != old.selection;
}

/// Owns a page's [TrackSelection]: it lives as long as the page, and Escape lets go of it.
class TrackSelectionHost extends StatefulWidget {
  const TrackSelectionHost({super.key, required this.child});

  final Widget child;

  @override
  State<TrackSelectionHost> createState() => _TrackSelectionHostState();
}

class _TrackSelectionHostState extends State<TrackSelectionHost> {
  final _selection = TrackSelection();

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {const SingleActivator(LogicalKeyboardKey.escape): _selection.clear},
    child: TrackSelectionScope(selection: _selection, child: widget.child),
  );
}

/// The round mark at the start of a row while songs are being picked.
class TrackSelectMark extends StatelessWidget {
  const TrackSelectMark({super.key, required this.selection, required this.track});

  final TrackSelection selection;
  final Track track;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: selection,
    builder: (context, _) {
      if (!selection.active) return const SizedBox.shrink();
      final on = selection.contains(track);
      return Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Icon(
          on ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
          size: 22,
          color: on ? AppColors.accent : AppColors.textSecondary,
        ),
      );
    },
  );
}

/// What can be done with the songs picked out of [tracks]: shown at the bottom of the page while any are.
class TrackSelectionBar extends StatelessWidget {
  const TrackSelectionBar({super.key, required this.selection, required this.tracks});

  final TrackSelection selection;
  final List<Track> tracks;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: selection,
    builder: (context, _) {
      final picked = selection.of(tracks);
      if (picked.isEmpty) return const SizedBox.shrink();
      final text = Theme.of(context).textTheme;
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Material(
            color: AppColors.elevated,
            elevation: 8,
            borderRadius: BorderRadius.circular(28),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: tr.cancelSelection,
                    onPressed: selection.clear,
                    icon: const Icon(Icons.close_rounded),
                  ),
                  Expanded(
                    child: Text(
                      tr.selectedCount(picked.length),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (picked.length < tracks.length)
                    IconButton(
                      tooltip: tr.selectAll,
                      onPressed: () => selection.selectAll(tracks),
                      icon: const Icon(Icons.select_all_rounded),
                    ),
                  IconButton(
                    tooltip: tr.addToQueue,
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      selection.clear();
                      await PlayerScope.read(context).addToQueue(picked);
                      messenger.showSnackBar(SnackBar(content: Text(tr.toastAddedToQueue)));
                    },
                    icon: const Icon(Icons.queue_music_rounded),
                  ),
                  IconButton(
                    tooltip: tr.addToPlaylist,
                    onPressed: () async {
                      await addToPlaylist(context, picked);
                      selection.clear();
                    },
                    icon: const Icon(Icons.playlist_add_rounded),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

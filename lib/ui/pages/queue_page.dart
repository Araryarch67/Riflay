import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../../services/language.dart';
import '../../services/listen_together/listen_together.dart';
import '../../services/player_controller.dart';
import '../shell_scope.dart';
import '../theme.dart';
import '../widgets/page_scaffold.dart';
import '../widgets/track_row.dart';
import '../ytmusic_edit.dart' show createPlaylist;

class QueuePage extends StatelessWidget {
  const QueuePage({super.key});

  @override
  Widget build(BuildContext context) => VisiblePlayerBuilder(
    builder: (context, c) =>
        ListenableBuilder(listenable: ListenTogether.of(c), builder: (context, _) => _build(context, c)),
  );

  Widget _build(BuildContext context, PlayerController c) {
    final shell = ShellScope.of(context);
    final text = Theme.of(context).textTheme;
    final session = ListenTogether.of(c);
    final guest = session.role == ListenRole.guest;
    final current = guest ? session.hostTrack?.toTrack() : c.currentTrack;
    final upNext = guest ? [for (final song in session.upNext) song.toTrack()] : c.upNext;
    // Each entry by its place after the current song: a song can be queued twice, so not by its id.
    final entries = [for (final (i, t) in upNext.indexed) (place: i, track: t)];
    final queued = [
      for (final e in entries)
        if (guest || !c.isAutoplayed(e.track)) e,
    ];
    final autoplayed = [
      for (final e in entries)
        if (!guest && c.isAutoplayed(e.track)) e,
    ];
    final place = {for (final e in entries) e: e.place};
    // Keys that follow an entry as it moves: its song and how many times that song came before it.
    final seen = <String, int>{};
    final keys = {
      for (final e in entries) e: ValueKey('${e.track.id}#${seen.update(e.track.id, (n) => n + 1, ifAbsent: () => 0)}'),
    };
    final pad = shell.compact ? 16.0 : 24.0;
    final hPad = EdgeInsets.symmetric(horizontal: shell.compact ? 12 : 16);

    return PageScaffold(
      title: tr.queue,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(pad, 0, pad, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(tr.queue, style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                ),
                if (current != null || upNext.isNotEmpty)
                  // The song playing and everything after it, autoplay included: what the page shows.
                  TextButton.icon(
                    onPressed: () => createPlaylist(context, tracks: [?current, ...upNext]),
                    icon: const Icon(Icons.playlist_add_rounded),
                    label: Text(tr.saveAsPlaylist),
                  ),
              ],
            ),
          ),
        ),
        if (current == null && upNext.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(pad),
              child: Text(
                guest ? tr.waitingForHost(session.hostName ?? tr.theHost) : tr.queueEmpty,
                style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
              ),
            ),
          )
        else ...[
          if (current != null) ...[
            SliverToBoxAdapter(child: SectionTitle(tr.nowPlaying)),
            SliverPadding(
              padding: hPad,
              sliver: SliverToBoxAdapter(
                child: TrackRow(track: current, index: 1, onTap: guest ? null : c.togglePlay),
              ),
            ),
          ],
          if (queued.isNotEmpty) ...[
            SectionTitleSliver(
              title: guest
                  ? tr.listeningWith(session.hostName ?? tr.theHost)
                  : c.playingFrom == null
                  ? tr.nextUp
                  : tr.nextFrom(c.playingFrom!),
            ),
            SliverPadding(
              padding: hPad,
              // Dragged by the handle (or a long press) to play sooner or later; ✕ or a swipe takes one out.
              sliver: guest
                  ? SliverList.builder(
                      itemCount: queued.length,
                      itemBuilder: (context, i) =>
                          TrackRow(key: keys[queued[i]], track: queued[i].track, index: i + 2, onTap: null),
                    )
                  : SliverReorderableList(
                      itemCount: queued.length,
                      onReorderItem: (from, to) => c.moveInQueue(place[queued[from]]!, place[queued[to]]!),
                      // Phone Queue is scoped inside a root route. The drag overlay
                      // sits above that scope, so carry the row's layout with it.
                      proxyDecorator: (child, _, _) =>
                          shell.wrap(Material(color: AppColors.of(context).elevated, elevation: 6, child: child)),
                      itemBuilder: (context, i) => _QueueRow(
                        key: keys[queued[i]],
                        track: queued[i].track,
                        index: i + 2,
                        dragIndex: i,
                        onTap: () => c.playQueueItem(queued[i].track),
                        onRemove: () => c.removeFromQueue(place[queued[i]]!),
                      ),
                    ),
            ),
          ],
          if (!guest)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(pad - 16, 16, pad - 16, 0),
                child: SwitchListTile(
                  title: Text(tr.autoplay),
                  subtitle: Text(tr.autoplaySubtitle, style: text.bodySmall?.copyWith(color: AppColors.textSecondary)),
                  value: c.autoplay,
                  onChanged: c.setAutoplay,
                ),
              ),
            ),
          if (autoplayed.isNotEmpty) ...[
            SectionTitleSliver(title: tr.autoplaySimilar),
            SliverPadding(
              padding: hPad,
              sliver: SliverList.builder(
                itemCount: autoplayed.length,
                itemBuilder: (context, i) => _QueueRow(
                  key: keys[autoplayed[i]],
                  track: autoplayed[i].track,
                  index: queued.length + i + 2,
                  onTap: () => c.playQueueItem(autoplayed[i].track),
                  onRemove: () => c.removeFromQueue(place[autoplayed[i]]!),
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class SectionTitleSliver extends StatelessWidget {
  const SectionTitleSliver({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(child: SectionTitle(title));
}

/// A song in the queue: tap to play it now, ✕ or a swipe to take it out, and (in Next up) a handle to drag it.
class _QueueRow extends StatelessWidget {
  const _QueueRow({
    super.key,
    required this.track,
    required this.index,
    required this.onTap,
    required this.onRemove,
    this.dragIndex,
  });

  final Track track;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  /// Its place in a reorderable list; null where songs can't be moved.
  final int? dragIndex;

  @override
  Widget build(BuildContext context) {
    final muted = AppColors.of(context).textSecondary;
    final row = Row(
      children: [
        Expanded(
          child: TrackRow(track: track, index: index, onTap: onTap),
        ),
        IconButton(
          tooltip: tr.removeFromQueue,
          color: muted,
          onPressed: onRemove,
          icon: const Icon(Icons.close_rounded, size: 20),
        ),
        if (dragIndex case final i?)
          ReorderableDragStartListener(
            index: i,
            child: Tooltip(
              message: tr.dragToMove,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                child: Icon(Icons.drag_handle_rounded, color: muted),
              ),
            ),
          ),
      ],
    );
    return Dismissible(
      key: ValueKey('dismiss-${key.hashCode}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onRemove(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: Theme.of(context).colorScheme.error.withValues(alpha: 0.25),
        child: const Icon(Icons.delete_outline_rounded),
      ),
      child: Material(type: MaterialType.transparency, child: row),
    );
  }
}

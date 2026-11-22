import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../../services/language.dart';
import '../../services/layout_prefs.dart';
import '../../services/listen_together/listen_together.dart';
import '../../services/player_controller.dart';
import '../shell_scope.dart';
import '../theme.dart';
import '../widgets/app_dialog.dart';
import '../widgets/item_picker.dart';
import '../widgets/menus.dart';
import '../widgets/page_scaffold.dart';
import '../widgets/track_row.dart';
import '../ytmusic_edit.dart' show createPlaylist;

class QueuePage extends StatefulWidget {
  const QueuePage({super.key});

  @override
  State<QueuePage> createState() => _QueuePageState();
}

class _QueuePageState extends State<QueuePage> {
  final _playingRow = GlobalKey();

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
    final sequence = c.player.sequenceState;
    final sources = sequence.sequence.skip((sequence.currentIndex ?? -1) + 1).toList();
    final eta = <String?>[];
    var time = !guest && c.isPlaying && !c.player.shuffleModeEnabled && c.duration != null
        ? DateTime.now().add((c.duration! - c.position) * (1 / c.player.speed))
        : null;
    for (var i = 0; i < upNext.length; i++) {
      eta.add(time == null ? null : TimeOfDay.fromDateTime(time).format(context));
      if (time != null && i < sources.length && !c.skipping(sources[i])) {
        final length = upNext[i].duration;
        time = length == null || c.stopping(sources[i]) ? null : time.add(length * (1 / c.player.speed));
      }
    }
    Future<void> remove(int i) async {
      if (!ExtraFeature.undoRemoval.enabled) {
        await c.removeFromQueue(i);
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      final undo = await c.removeUpcomingWithUndo((c.queueIndex ?? -1) + 1 + i);
      if (undo == null || !context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(tr.removedFrom(tr.queue)),
          action: SnackBarAction(label: tr.undo, onPressed: undo),
        ),
      );
    }

    Widget actions(int i) {
      if (i >= sources.length) return const SizedBox.shrink();
      final source = sources[i];
      return PopupMenuButton<String>(
        tooltip: tr.queue,
        icon: Icon(
          c.skipping(source)
              ? Icons.skip_next
              : c.stopping(source)
              ? Icons.stop_circle
              : Icons.more_vert,
        ),
        onSelected: (value) async {
          if (value == 'skip') {
            c.toggleSkip(source);
            return;
          }
          if (value == 'stop') {
            c.toggleStop(source);
            return;
          }
          final targets = sources.where((s) => s != source).toList();
          final target = await pickListItem(context, tr.insertAfter, targets, (s) => (s.tag as Track).title);
          if (target == null) return;
          final seq = c.player.sequenceState;
          final offset = (seq.currentIndex ?? -1) + 1;
          final from = seq.sequence.indexOf(source) - offset, after = seq.sequence.indexOf(target) - offset;
          if (from >= 0 && after >= 0) await c.moveInQueue(from, from < after ? after : after + 1);
        },
        itemBuilder: (_) => [
          for (final (value, label, icon, checked) in [
            ('skip', tr.skipOnce, Icons.skip_next_rounded, c.skipping(source)),
            ('stop', tr.stopAfter, Icons.stop_circle_outlined, c.stopping(source)),
            if (sources.length > 1) ('move', tr.insertAfter, Icons.low_priority_rounded, null),
          ])
            PopupMenuItem(
              value: value,
              child: Semantics(
                checked: checked,
                child: MenuRow(leading: Icon(checked == true ? Icons.check_rounded : icon), title: Text(label)),
              ),
            ),
        ],
      );
    }

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
      actions: [
        if (ExtraFeature.jumpToPlaying.enabled && current != null)
          IconButton(
            tooltip: tr.jumpToPlaying,
            icon: const Icon(Icons.my_location_rounded),
            onPressed: () {
              if (_playingRow.currentContext case final row?) {
                Scrollable.ensureVisible(row, duration: LayoutPrefs.dur(const Duration(milliseconds: 260)));
              }
            },
          ),
      ],
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(pad, 0, pad, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(tr.queue, style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                ),
                if (!guest && current != null)
                  IconButton(
                    tooltip: tr.regenerateQueue,
                    icon: const Icon(Icons.refresh),
                    onPressed: c.regenerating
                        ? null
                        : () async {
                            final ok = await c.regenerateQueue();
                            if (!ok && context.mounted) {
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(content: Text(tr.queueRefreshFailed)));
                            }
                          },
                  ),
                if (!guest && upNext.isNotEmpty)
                  IconButton(
                    tooltip: tr.clearUpcomingQueue,
                    icon: const Icon(Icons.playlist_remove_rounded),
                    onPressed: () async {
                      final clear = await confirmDialog(
                        context,
                        title: tr.clearUpcomingQueue,
                        body: tr.clearUpcomingQueueBody,
                        confirmLabel: tr.clear,
                        destructive: true,
                      );
                      if (!clear || !context.mounted) return;
                      try {
                        await c.clearUpcomingQueue();
                      } catch (e) {
                        debugPrint('Clear upcoming queue: $e');
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.clearQueueFailed)));
                        }
                      }
                    },
                  ),
                if (current != null || upNext.isNotEmpty)
                  // The song playing and everything after it, autoplay included: what the page shows.
                  if (shell.compact)
                    IconButton(
                      tooltip: tr.saveAsPlaylist,
                      onPressed: () => createPlaylist(context, tracks: [?current, ...upNext]),
                      icon: const Icon(Icons.playlist_add_rounded),
                    )
                  else
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
                child: TrackRow(
                  key: _playingRow,
                  track: current,
                  index: 1,
                  currentOccurrence: true,
                  onTap: guest ? null : c.togglePlay,
                ),
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
                      itemBuilder: (context, i) => TrackRow(
                        key: keys[queued[i]],
                        track: queued[i].track,
                        index: i + 2,
                        currentOccurrence: false,
                        onTap: null,
                      ),
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
                        actions: actions(queued[i].place),
                        eta: eta[queued[i].place],
                        onTap: () => c.playQueueItem(queued[i].track),
                        onRemove: () => remove(queued[i].place),
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
                  actions: actions(autoplayed[i].place),
                  eta: eta[autoplayed[i].place],
                  onTap: () => c.playQueueItem(autoplayed[i].track),
                  onRemove: () => remove(autoplayed[i].place),
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
    required this.actions,
    this.eta,
  });

  final Track track;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  /// Its place in a reorderable list; null where songs can't be moved.
  final int? dragIndex;
  final Widget actions;
  final String? eta;

  @override
  Widget build(BuildContext context) {
    final muted = AppColors.of(context).textSecondary;
    final row = Row(
      children: [
        Expanded(
          child: TrackRow(track: track, index: index, currentOccurrence: false, onTap: onTap),
        ),
        // When it starts, in a slot of its own width even when unknown, so the buttons after it line up row to row.
        SizedBox(
          width: 60,
          child: eta == null
              ? null
              : FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    eta!,
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
        ),
        actions,
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

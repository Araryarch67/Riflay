import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/connect/connect_share.dart';
import '../../services/language.dart';
import '../player_scope.dart';
import '../shell_scope.dart';
import '../theme.dart';
import '../widgets/menus.dart';
import '../widgets/page_scaffold.dart';
import 'sound_settings.dart' show SettingsCard;

/// Riflay Connect › Shared music: pick which albums, artists and playlists to share, look at what a paired device
/// shares, and keep copies. [share] is only for tests.
class ConnectSharePage extends StatefulWidget {
  const ConnectSharePage({super.key, this.share});

  final ConnectShare? share;

  @override
  State<ConnectSharePage> createState() => _ConnectSharePageState();
}

class _ConnectSharePageState extends State<ConnectSharePage> {
  ConnectShare? _share;
  List<ShareCollection> _candidates = const [];
  ShareKind? _kind;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_share != null) return;
    final s = _share = widget.share ?? ConnectShare.of(PlayerScope.read(context));
    unawaited(s.load());
    // Worked out once: a library can hold thousands of songs.
    _candidates = s.candidates();
  }

  @override
  Widget build(BuildContext context) {
    final compact = context.dependOnInheritedWidgetOfExactType<ShellScope>()?.compact ?? false;
    final pad = compact ? 16.0 : 24.0;
    final share = _share!;
    return ListenableBuilder(
      listenable: share,
      builder: (context, _) {
        final text = Theme.of(context).textTheme;
        final shown = [
          for (final c in _candidates)
            if (_kind == null || c.entry.kind == _kind) c,
        ];
        Widget box(Widget child) => Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: pad),
              child: child,
            ),
          ),
        );
        return PageScaffold(
          title: tr.connectShareTitle,
          slivers: [
            SliverToBoxAdapter(
              child: box(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr.connectShareTitle, style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text(tr.connectShareIntro, style: _muted(context)),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(child: Text(tr.connectShareByYou, style: _heading(context))),
                        OptionPicker<ShareKind?>(
                          value: _kind,
                          options: [
                            (null, tr.all),
                            (ShareKind.album, tr.albums),
                            (ShareKind.artist, tr.artists),
                            (ShareKind.playlist, tr.playlists),
                          ],
                          onChanged: (k) => setState(() => _kind = k),
                          maxWidth: 160,
                        ),
                      ],
                    ),
                    if (_candidates.isEmpty) ...[
                      const SizedBox(height: 8),
                      Text(tr.connectShareNoneOnDevice, style: _muted(context)),
                    ],
                  ],
                ),
              ),
            ),
            // Built as it scrolls: a library can have thousands of albums.
            SliverList.builder(
              itemCount: shown.length,
              itemBuilder: (context, i) {
                final c = shown[i];
                return box(
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.trailing,
                    value: share.selected.contains(c.id),
                    onChanged: share.loaded ? (on) => unawaited(share.setShared(c.id, on ?? false)) : null,
                    title: Text(c.entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(_meta(c.entry), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                );
              },
            ),
            SliverToBoxAdapter(
              child: box(
                Padding(
                  padding: const EdgeInsets.only(top: 32, bottom: 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr.connectShareWithYou, style: _heading(context)),
                      const SizedBox(height: 8),
                      if (share.peers.every((p) => p.viewer.entries.isEmpty))
                        Text(tr.connectShareNothingYet, style: _muted(context)),
                      for (final peer in share.peers) _PeerShares(share: share, peer: peer),
                      if (share.copies.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Text(tr.connectShareCopies, style: _heading(context)),
                        const SizedBox(height: 4),
                        Text(tr.connectShareCopiesHint, style: _muted(context)),
                        const SizedBox(height: 8),
                        SettingsCard(
                          children: [
                            for (final c in share.copies)
                              ListTile(
                                leading: Icon(_icon(c.entry.kind)),
                                title: Text(c.entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Text(_meta(c.entry), maxLines: 1, overflow: TextOverflow.ellipsis),
                                onTap: () => _show(context, share, null, c.id),
                                trailing: IconButton(
                                  tooltip: tr.remove,
                                  icon: const Icon(Icons.delete_outline_rounded),
                                  onPressed: () => unawaited(share.removeCopy(c.id)),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

TextStyle? _muted(BuildContext context) =>
    Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary);

TextStyle? _heading(BuildContext context) =>
    Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800);

IconData _icon(ShareKind k) => switch (k) {
  ShareKind.album => Icons.album_rounded,
  ShareKind.artist => Icons.person_rounded,
  ShareKind.playlist => Icons.queue_music_rounded,
};

String _kindName(ShareKind k) => switch (k) {
  ShareKind.album => tr.album,
  ShareKind.artist => tr.artist,
  ShareKind.playlist => tr.playlist,
};

/// "Album • Artist • 1999 • 12 songs".
String _meta(ShareEntry e) => [
  _kindName(e.kind),
  if (e.artist != null) e.artist!,
  if (e.year != null) '${e.year}',
  tr.songsCount(e.count),
].join(' • ');

/// Opens the songs of [id] in a route of its own, still inside the shell's scope.
void _show(BuildContext context, ConnectShare share, String? peerId, String id) {
  final shell = ShellScope.of(context);
  unawaited(
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => shell.wrap(_CollectionPage(share: share, peerId: peerId, id: id)),
      ),
    ),
  );
}

/// One paired device's shares: read-only rows that open the songs.
class _PeerShares extends StatelessWidget {
  const _PeerShares({required this.share, required this.peer});

  final ConnectShare share;
  final ({String id, String name, bool connected, ShareViewer viewer}) peer;

  @override
  Widget build(BuildContext context) {
    final entries = peer.viewer.entries;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(peer.name, style: Theme.of(context).textTheme.titleMedium)),
            IconButton(
              tooltip: tr.refresh,
              onPressed: peer.connected ? () => share.requestList(peer.id) : null,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        if (!peer.connected) Text(tr.connectShareOffline, style: _muted(context)),
        if (entries.isNotEmpty)
          SettingsCard(
            children: [
              for (final e in entries)
                ListTile(
                  leading: Icon(_icon(e.kind)),
                  title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(_meta(e), maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () {
                    share.open(peer.id, e.id);
                    _show(context, share, peer.id, e.id);
                  },
                ),
            ],
          ),
      ],
    );
  }
}

/// The songs of one shared collection (read-only) or of a local copy (which can be renamed or removed).
class _CollectionPage extends StatelessWidget {
  const _CollectionPage({required this.share, required this.peerId, required this.id});

  final ConnectShare share;

  /// Null for a local copy.
  final String? peerId;
  final String id;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: share,
    builder: (context, _) {
      final peer = share.peers.where((p) => p.id == peerId).firstOrNull;
      final copy = share.copies.where((c) => c.id == id).firstOrNull;
      final c = peerId == null ? copy : peer?.viewer.loaded(id);
      final entry = c?.entry ?? peer?.viewer.entries.where((e) => e.id == id).firstOrNull;
      final text = Theme.of(context).textTheme;
      return PageScaffold(
        title: entry?.name ?? '',
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (entry != null) ...[
                    Text(entry.name, style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                    Text(_meta(entry), style: _muted(context)),
                  ],
                  const SizedBox(height: 8),
                  if (peerId != null && peer != null) Text(tr.connectShareReadOnly(peer.name), style: _muted(context)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    children: [
                      if (peerId != null && c != null)
                        FilledButton(
                          onPressed: () => unawaited(share.saveCopy(c)),
                          child: Text(tr.connectShareSaveCopy),
                        ),
                      if (peerId == null && copy != null)
                        OutlinedButton(onPressed: () => unawaited(_rename(context, copy)), child: Text(tr.rename)),
                    ],
                  ),
                  if (c == null && peerId != null) ...[
                    const SizedBox(height: 16),
                    Text(tr.connectShareLoading, style: _muted(context)),
                  ],
                ],
              ),
            ),
          ),
          if (c != null)
            SliverList.builder(
              itemCount: c.tracks.length,
              itemBuilder: (context, i) => ListTile(
                dense: true,
                title: Text(c.tracks[i].title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(c.tracks[i].artist, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
        ],
      );
    },
  );

  Future<void> _rename(BuildContext context, ShareCollection copy) async {
    final controller = TextEditingController(text: copy.entry.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        content: TextField(controller: controller, autofocus: true, maxLength: 200),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(tr.rename)),
        ],
      ),
    );
    controller.dispose();
    if (name != null) await share.renameCopy(copy.id, name);
  }
}

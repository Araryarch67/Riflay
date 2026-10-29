import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../models/track.dart';
import '../../services/download_files.dart';
import '../../services/duplicate_finder.dart';
import '../../services/player_controller.dart';
import '../../services/youtube_importer.dart';
import '../shell_scope.dart';
import '../theme.dart';
import '../widgets/page_scaffold.dart';

/// Songs that are in the library more than once, in different files, formats or sources: shows each copy,
/// picks the best to keep, and removes the others when asked.
class DuplicatesPage extends StatefulWidget {
  const DuplicatesPage({super.key});

  @override
  State<DuplicatesPage> createState() => _DuplicatesPageState();
}

class _DuplicatesPageState extends State<DuplicatesPage> {
  PlayerController? _c;
  List<DuplicateGroup>? _groups;
  final Map<DuplicateGroup, String> _keep = {};
  final Set<DuplicateGroup> _keepAll = {};
  bool _working = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c == null) {
      _c = PlayerScope.read(context);
      unawaited(_scan());
    }
  }

  Future<void> _scan() async {
    final c = _c!;
    final songs = [
      for (final t in c.library)
        if (canCompare(t)) t,
    ];
    String? downloads;
    try {
      downloads = (await YoutubeImporter.downloadsDir()).path;
    } catch (_) {
      // without it, a song with a source link still counts as a download
    }
    final sizes = await readFileSizes([for (final t in songs) t.path!]);
    final groups = findDuplicates([
      for (final t in songs) DuplicateItem.of(t, bytes: sizes[t.path], downloadsDir: downloads),
    ]);
    if (!mounted) return;
    setState(() {
      _groups = groups;
      _keep
        ..clear()
        ..addEntries([for (final g in groups) MapEntry(g, g.best.track.id)]);
      _keepAll.clear();
    });
  }

  List<RemovalChoice> get _choices => [
    for (final g in _groups ?? const <DuplicateGroup>[])
      if (!_keepAll.contains(g)) RemovalChoice(g, _keep[g] ?? g.best.track.id),
  ];

  Future<void> _remove() async {
    final c = _c!;
    final choices = _choices;
    final library = c.library;
    final result = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (_) => _RemoveDialog(choices: choices, library: library),
    );
    if (result == null || !mounted) return;
    final plan = planRemoval(choices, deleteFiles: result, library: library);
    if (plan.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _working = true);
    var failed = 0;
    var deleted = 0;
    if (result) {
      final r = await deletePlannedFiles(plan);
      failed = r.failed;
      deleted = r.deleted;
    }
    await c.swapTrackRefs(plan.keptInstead);
    await c.removeTracks(plan.removeFromLibrary);
    if (!mounted) return;
    setState(() => _working = false);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          failed > 0
              ? 'Removed ${plan.removeFromLibrary.length} copies. $failed files couldn\'t be deleted.'
              : result
              ? 'Removed ${plan.removeFromLibrary.length} copies and deleted $deleted files, freeing ${formatFileSize(plan.bytesFreed)}.'
              : 'Removed ${plan.removeFromLibrary.length} copies from your library.',
        ),
      ),
    );
    unawaited(_scan());
  }

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.of(context);
    final text = Theme.of(context).textTheme;
    final pad = shell.compact ? 16.0 : 24.0;
    final groups = _groups;
    final choices = _choices;
    final extra = choices.fold<int>(0, (n, c) => n + c.group.items.length - 1);
    final freeable = planRemoval(choices, deleteFiles: true, library: _c?.library ?? const []).bytesFreed;
    return PageScaffold(
      title: 'Songs you have twice',
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(pad, 0, pad, 16),
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Songs you have twice', style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text(
                      groups == null
                          ? 'Looking through your library...'
                          : groups.isEmpty
                          ? 'No song is in your library twice.'
                          : 'These are the same song in more than one file. The best copy is chosen for each; '
                                'pick another if you like, then remove the rest.',
                      style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
                    ),
                    if (groups != null && groups.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.inverse,
                              foregroundColor: AppColors.onInverse,
                            ),
                            onPressed: extra == 0 || _working ? null : _remove,
                            child: Text(
                              extra == 0
                                  ? 'Nothing to remove'
                                  : 'Remove $extra extra ${extra == 1 ? 'copy' : 'copies'}',
                            ),
                          ),
                          if (extra > 0 && freeable > 0)
                            Text(
                              'Up to ${formatFileSize(freeable)} can be freed.',
                              style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        if (groups == null)
          const SliverToBoxAdapter(
            child: Center(
              child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad, 0, pad, 28),
            sliver: SliverList.separated(
              itemCount: groups.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final g = groups[i];
                return Align(
                  alignment: Alignment.topLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: _GroupCard(
                      group: g,
                      keepId: _keep[g] ?? g.best.track.id,
                      keepAll: _keepAll.contains(g),
                      onKeep: (id) => setState(() => _keep[g] = id),
                      onKeepAll: (all) => setState(() => all ? _keepAll.add(g) : _keepAll.remove(g)),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.group,
    required this.keepId,
    required this.keepAll,
    required this.onKeep,
    required this.onKeepAll,
  });

  final DuplicateGroup group;
  final String keepId;
  final bool keepAll;
  final ValueChanged<String> onKeep;
  final ValueChanged<bool> onKeepAll;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: AppColors.textSecondary);
    return Material(
      color: AppColors.elevated,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(group.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
                      ],
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
                    onPressed: () => onKeepAll(!keepAll),
                    child: Text(keepAll ? 'Choose one' : 'Keep all'),
                  ),
                ],
              ),
            ),
            for (final item in group.items)
              InkWell(
                onTap: keepAll ? null : () => onKeep(item.track.id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2, right: 12),
                        child: Icon(
                          keepAll
                              ? Icons.check_circle_rounded
                              : item.track.id == keepId
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_unchecked_rounded,
                          size: 20,
                          color: keepAll || item.track.id == keepId ? AppColors.textPrimary : AppColors.textMuted,
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              [
                                item.qualityLabel,
                                if (item.bytes != null) formatFileSize(item.bytes!),
                                if (item == group.best) 'best quality',
                              ].join('  ·  '),
                              style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              '${item.madeByRiflay ? 'Downloaded by Riflay' : 'Your file'}  ·  ${p.basename(item.path)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: muted,
                            ),
                            Text(p.dirname(item.path), maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
                          ],
                        ),
                      ),
                      if (!keepAll && item.track.id == keepId)
                        Padding(
                          padding: const EdgeInsets.only(left: 8, top: 2),
                          child: Text('Keep', style: muted?.copyWith(fontWeight: FontWeight.w700)),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// "Remove N copies?" with the choice of deleting the files too; pops true (delete files) or false (library only).
class _RemoveDialog extends StatefulWidget {
  const _RemoveDialog({required this.choices, required this.library});

  final List<RemovalChoice> choices;
  final List<Track> library;

  @override
  State<_RemoveDialog> createState() => _RemoveDialogState();
}

class _RemoveDialogState extends State<_RemoveDialog> {
  bool _delete = false;

  @override
  Widget build(BuildContext context) {
    final plan = planRemoval(widget.choices, deleteFiles: _delete, library: widget.library);
    final withFiles = planRemoval(widget.choices, deleteFiles: true, library: widget.library);
    final n = plan.removeFromLibrary.length;
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary);
    return AlertDialog(
      title: Text('Remove $n ${n == 1 ? 'copy' : 'copies'}?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'They are taken out of your library, and the copy you keep stays. Playlists that had a removed copy '
              'use the one you keep.',
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _delete,
              onChanged: (v) => setState(() => _delete = v ?? false),
              title: const Text('Also delete the files from this device'),
              subtitle: Text(
                'Frees ${formatFileSize(withFiles.bytesFreed)}. Deleted files can\'t be brought back.',
                style: muted,
              ),
            ),
            if (_delete && plan.filesToDelete.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                [
                  if (plan.ownFilesToDelete > 0) '${plan.ownFilesToDelete} of your own files',
                  if (plan.downloadsToDelete > 0) '${plan.downloadsToDelete} downloads Riflay saved',
                ].join(' and '),
                style: muted,
              ),
            ],
            if (_delete && plan.skippedFiles > 0)
              Text('${plan.skippedFiles} files are used by other songs and stay.', style: muted),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context, rootNavigator: true).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(_delete),
          child: Text(_delete ? 'Delete files' : 'Remove from library'),
        ),
      ],
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../../services/download_files.dart';
import '../../services/player_controller.dart';
import '../../services/youtube_importer.dart';
import '../shell_scope.dart';
import '../theme.dart';
import '../widgets/controls.dart';
import '../widgets/page_scaffold.dart';

/// Progress and history of YouTube imports.
class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Only the downloads matter here, not every change of what's playing.
    final c = PlayerScope.read(context);
    final shell = ShellScope.of(context);
    final text = Theme.of(context).textTheme;
    final pad = shell.compact ? 16.0 : 24.0;
    return ListenableBuilder(
      listenable: c.youtube,
      builder: (context, _) {
        final jobs = c.youtube.jobs;
        final hasFinished = jobs.any((j) => !j.isActive);
        return PageScaffold(
          title: 'Downloads',
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(pad, 0, pad, 16),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    Text('Downloads', style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.inverse,
                        foregroundColor: AppColors.onInverse,
                      ),
                      onPressed: shell.importFromYoutube,
                      icon: const Icon(Icons.add_link_rounded),
                      label: const Text('Import from YouTube'),
                    ),
                    if (hasFinished)
                      TextButton(
                        style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
                        onPressed: c.youtube.clearFinished,
                        child: const Text('Clear finished'),
                      ),
                  ],
                ),
              ),
            ),
            const _DownloadedFiles(),
            if (jobs.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: pad, vertical: 8),
                  child: Text(
                    'Nothing downloading. Paste a YouTube video or playlist link to add its audio to your library.',
                    style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: shell.compact ? 8 : 16),
                sliver: SliverList.builder(
                  itemCount: jobs.length,
                  itemBuilder: (context, i) => _JobRow(job: jobs[i]),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// How much room the downloads take, and the songs whose file has gone missing.
class _DownloadedFiles extends StatefulWidget {
  const _DownloadedFiles();

  @override
  State<_DownloadedFiles> createState() => _DownloadedFilesState();
}

class _DownloadedFilesState extends State<_DownloadedFiles> {
  PlayerController? _c;
  DownloadScan? _scan;
  int _scans = 0;
  int _active = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = PlayerScope.read(context);
    if (identical(c, _c)) return;
    _c?.libraryRevision.removeListener(_refresh);
    _c?.youtube.removeListener(_onJobs);
    _c = c
      ..libraryRevision.addListener(_refresh)
      ..youtube.addListener(_onJobs);
    _active = c.youtube.activeCount;
    _refresh();
  }

  @override
  void dispose() {
    _c?.libraryRevision.removeListener(_refresh);
    _c?.youtube.removeListener(_onJobs);
    super.dispose();
  }

  /// A finished download can put back a file the library already lists, which
  /// doesn't change the library: look again whenever a job starts or ends, not
  /// on every progress tick.
  void _onJobs() {
    final active = _c!.youtube.activeCount;
    if (active == _active) return;
    _active = active;
    _refresh();
  }

  Future<void> _refresh() async {
    final c = _c;
    if (c == null) return;
    final mine = ++_scans;
    final scan = await scanDownloads(downloadedFrom(c.library));
    // A newer look is under way, or the page is gone.
    if (!mounted || mine != _scans) return;
    setState(() => _scan = scan);
  }

  void _downloadAgain(List<Track> songs) {
    final c = _c!;
    for (final t in songs) {
      final id = youtubeVideoIdOf(t.sourceUrl);
      if (id == null) continue;
      // A finished job of this song would make the importer skip it.
      if (c.youtube.jobFor(id)?.status == DownloadStatus.done) c.youtube.clearFinished();
      c.youtube.enqueueTracks([Track.youtube(videoId: id, title: t.title, artist: t.artist)]);
    }
  }

  void _remove(List<Track> songs) {
    for (final t in songs) {
      unawaited(_c!.removeTrack(t));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scan = _scan;
    if (scan == null) return const SliverToBoxAdapter(child: SizedBox.shrink());
    final shell = ShellScope.of(context);
    final text = Theme.of(context).textTheme;
    final pad = shell.compact ? 16.0 : 24.0;
    final missing = scan.missing;
    return SliverMainAxisGroup(
      slivers: [
        if (scan.bytes > 0)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(pad, 0, pad, 16),
              child: Text(
                'Downloads use ${formatFileSize(scan.bytes)}',
                style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
              ),
            ),
          ),
        if (missing.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(pad, 8, pad, 4),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text('Missing files', style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  TextButton(onPressed: () => _downloadAgain(missing), child: const Text('Download all again')),
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
                    onPressed: () => _remove(missing),
                    child: const Text('Remove all from library'),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(pad, 0, pad, 8),
              child: Text(
                "These songs are in your library, but their files aren't on this device any more.",
                style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(shell.compact ? 8 : 16, 0, shell.compact ? 8 : 16, 16),
            sliver: SliverList.builder(
              itemCount: missing.length,
              itemBuilder: (context, i) => _MissingRow(
                track: missing[i],
                onDownload: () => _downloadAgain([missing[i]]),
                onRemove: () => _remove([missing[i]]),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _MissingRow extends StatelessWidget {
  const _MissingRow({required this.track, required this.onDownload, required this.onRemove});

  final Track track;
  final VoidCallback onDownload;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(tooltip: 'Download again', onPressed: onDownload, icon: const Icon(Icons.refresh_rounded)),
          IconButton(
            tooltip: 'Remove from library',
            onPressed: onRemove,
            icon: const Icon(Icons.remove_circle_outline_rounded),
          ),
        ],
      ),
    );
  }
}

class _JobRow extends StatelessWidget {
  const _JobRow({required this.job});

  final DownloadJob job;

  @override
  Widget build(BuildContext context) {
    final c = PlayerScope.read(context);
    final text = Theme.of(context).textTheme;
    final status = switch (job.status) {
      DownloadStatus.queued => 'Waiting…',
      DownloadStatus.downloading =>
        job.quality == null
            ? 'Preparing…'
            : job.phase != DownloadPhase.downloading
            ? [job.phase.label, job.quality].join(' • ')
            : [
                job.quality,
                if (job.totalBytes != null) '${formatBytes(job.receivedBytes)} of ${formatBytes(job.totalBytes!)}',
                if (job.bytesPerSecond != null) '${formatBytes(job.bytesPerSecond!)}/s',
                if (job.eta case final eta?) formatEta(eta),
              ].join(' • '),
      DownloadStatus.done => [
        'Added to library',
        ?job.quality,
        if (job.totalBytes != null) formatBytes(job.totalBytes!),
      ].join(' • '),
      DownloadStatus.failed => job.error ?? 'Failed',
      DownloadStatus.cancelled => 'Cancelled',
    };
    final statusColor = switch (job.status) {
      DownloadStatus.failed => Theme.of(context).colorScheme.error,
      DownloadStatus.done => AppColors.accent,
      _ => AppColors.textSecondary,
    };
    final track = job.track;

    return InkWell(
      borderRadius: BorderRadius.circular(6),
      hoverColor: AppColors.tile,
      onTap: track == null ? null : () => c.playList([track], 0, from: 'From YouTube'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: 96,
                height: 54,
                child: Image.network(
                  job.thumbnailUrl,
                  // Decoded at the size shown, not YouTube's 480 or 1280 px.
                  cacheWidth: (96 * MediaQuery.devicePixelRatioOf(context)).round(),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => ColoredBox(color: AppColors.hover),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    job.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    status,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(color: statusColor),
                  ),
                  if (job.status == DownloadStatus.downloading) ...[
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: job.quality == null || job.phase != DownloadPhase.downloading ? null : job.progress,
                      minHeight: 3,
                      color: AppColors.textPrimary,
                      backgroundColor: AppColors.hover,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            switch (job.status) {
              DownloadStatus.queued || DownloadStatus.downloading => IconButton(
                tooltip: 'Cancel',
                onPressed: () => c.youtube.cancel(job),
                icon: const Icon(Icons.close_rounded),
              ),
              DownloadStatus.failed || DownloadStatus.cancelled => IconButton(
                tooltip: 'Retry',
                onPressed: () => c.youtube.retry(job),
                icon: const Icon(Icons.refresh_rounded),
              ),
              DownloadStatus.done => IconButton(
                tooltip: 'Play',
                onPressed: () => c.playList([track!], 0, from: 'From YouTube'),
                icon: const Icon(Icons.play_arrow_rounded),
              ),
            },
          ],
        ),
      ),
    );
  }
}

/// Toolbar button that shows a progress ring while imports are running.
class DownloadsButton extends StatelessWidget {
  const DownloadsButton({super.key});

  @override
  Widget build(BuildContext context) {
    final c = PlayerScope.read(context);
    final shell = ShellScope.of(context);
    return ListenableBuilder(
      listenable: c.youtube,
      builder: (context, _) {
        final progress = c.youtube.activeProgress;
        return IconButton(
          tooltip: progress == null ? 'Downloads' : 'Downloading ${c.youtube.activeCount}',
          onPressed: shell.openDownloads,
          icon: progress == null
              ? const Icon(Icons.download_rounded)
              : SizedBox.square(
                  dimension: 22,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: progress == 0 ? null : progress,
                        strokeWidth: 2.2,
                        color: AppColors.accent,
                        backgroundColor: AppColors.hover,
                      ),
                      Icon(Icons.arrow_downward_rounded, size: 13, color: AppColors.textPrimary),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

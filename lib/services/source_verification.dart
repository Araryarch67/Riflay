import 'dart:async';

import 'package:flutter/foundation.dart';

import 'spotiflac.dart';
import 'youtube_importer.dart';

/// One interactive verification per failed batch. Cancellation never loops a browser open.
class SourceVerificationQueue {
  SourceVerificationQueue(this.downloads, {required this.verify, Spotiflac? engine})
    : engine = engine ?? Spotiflac.instance {
    downloads.addListener(_check);
    scheduleMicrotask(_check);
  }
  final YoutubeImporter downloads;
  final Spotiflac engine;
  final Future<bool> Function(DownloadJob job, String provider) verify;
  final _handled = <DownloadJob>{};
  bool _busy = false, _disposed = false;

  String _provider(DownloadJob job) => job.extensionDownloader ?? engine.downloadProviderOf(job.extensionTrack!);

  void _check() {
    if (_busy || _disposed) return;
    _handled.retainAll(downloads.jobs);
    final job = downloads.jobs
        .where(
          (job) =>
              job.status == DownloadStatus.failed &&
              job.verificationRequired &&
              job.extensionTrack != null &&
              !_handled.contains(job),
        )
        .firstOrNull;
    if (job == null) return;
    _handled.add(job);
    _busy = true;
    unawaited(_open(job));
  }

  Future<void> _open(DownloadJob job) async {
    try {
      final provider = _provider(job);
      final verified = await verify(job, provider);
      if (_disposed) return;
      for (final waiting in List<DownloadJob>.of(downloads.jobs)) {
        if (waiting.extensionTrack == null) continue;
        // Share the grant across the batch, including jobs still in flight.
        if (_provider(waiting) != provider) continue;
        _handled.add(waiting);
        if (verified && waiting.status == DownloadStatus.failed && waiting.verificationRequired) {
          downloads.retry(waiting);
        }
      }
    } catch (e) {
      debugPrint('Source verification: ${e.runtimeType}');
    } finally {
      _busy = false;
      if (!_disposed) _check();
    }
  }

  void dispose() {
    _disposed = true;
    downloads.removeListener(_check);
    _handled.clear();
  }
}

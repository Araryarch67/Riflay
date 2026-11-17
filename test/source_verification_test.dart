import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/spotiflac.dart';
import 'package:riflay/services/source_verification.dart';
import 'package:riflay/services/youtube_importer.dart';

class _Downloads extends YoutubeImporter {
  _Downloads() : super(onTrackReady: (_) async {});
  final pending = <DownloadJob>[];
  final retried = <DownloadJob>[];
  @override
  List<DownloadJob> get jobs => List.of(pending);
  void changed() => notifyListeners();
  @override
  void retry(DownloadJob job) {
    retried.add(job);
    job
      ..status = DownloadStatus.queued
      ..verificationRequired = false;
    notifyListeners();
  }
}

DownloadJob _job(String id) {
  final source = Spotiflac.track('tidal-web', {'id': id, 'name': 'Song'})!;
  return DownloadJob(
      videoId: Spotiflac.jobId(source),
      title: source.title,
      channel: source.artist,
      thumbnailUrl: '',
      extensionTrack: source,
      extensionDownloader: 'tidal-web',
    )
    ..status = DownloadStatus.failed
    ..verificationRequired = true;
}

void main() {
  test('one verification retries all waiting songs from the same provider', () async {
    final downloads = _Downloads();
    final one = _job('1'), two = _job('2');
    downloads.pending.addAll([one, two]);
    final grant = Completer<bool>();
    final providers = <String>[];
    final queue = SourceVerificationQueue(
      downloads,
      verify: (job, provider) {
        providers.add(provider);
        return grant.future;
      },
    );
    await Future<void>.delayed(Duration.zero);
    downloads.changed();
    downloads.changed();
    expect(providers, ['tidal-web']);
    grant.complete(true);
    await Future<void>.delayed(Duration.zero);
    expect(downloads.retried, [one, two]);
    expect(one.verificationRequired, isFalse);
    queue.dispose();
    downloads.dispose();
  });

  test('cancelled verification is not reopened by download progress notifications', () async {
    final downloads = _Downloads()..pending.addAll([_job('1'), _job('2')]);
    var opened = 0;
    final queue = SourceVerificationQueue(
      downloads,
      verify: (_, _) async {
        opened++;
        return false;
      },
    );
    await Future<void>.delayed(Duration.zero);
    for (var i = 0; i < 4; i++) {
      downloads.changed();
      await Future<void>.delayed(Duration.zero);
    }
    expect(opened, 1);
    expect(downloads.retried, isEmpty);
    queue.dispose();
    downloads.dispose();
  });

  test('disposing while verification is open never retries against a closed importer', () async {
    final downloads = _Downloads()..pending.add(_job('1'));
    final grant = Completer<bool>();
    final queue = SourceVerificationQueue(downloads, verify: (_, _) => grant.future);
    await Future<void>.delayed(Duration.zero);
    queue.dispose();
    grant.complete(true);
    await Future<void>.delayed(Duration.zero);
    expect(downloads.retried, isEmpty);
    downloads.dispose();
  });

  test('verification state survives restart without relying on translated error text', () {
    final job = _job('1')..error = 'Anything in any language';
    final restored = DownloadJob.fromJson(job.toJson())!;
    expect(restored.verificationRequired, isTrue);
    expect(restored.extensionDownloader, 'tidal-web');
    final ordinary = _job('2')..verificationRequired = false;
    expect(DownloadJob.fromJson(ordinary.toJson())!.verificationRequired, isFalse);
  });
}

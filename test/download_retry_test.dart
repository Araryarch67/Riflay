import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/download_prefs.dart';
import 'package:riflay/services/spotiflac.dart';
import 'package:riflay/services/youtube_importer.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Flaky extends Spotiflac {
  _Flaky(this.failures, {this.verification = false});
  final int failures;
  final bool verification;
  int calls = 0;

  @override
  Future<Track> download(
    Track source,
    Directory destination, {
    String? quality,
    String? providerOverride,
    bool Function()? cancelled,
    void Function(double)? progress,
  }) async {
    calls++;
    if (verification) throw const SpotiflacError(verificationRequired: true);
    if (calls <= failures) throw const SocketException('temporary outage');
    final file = await File('${destination.path}/test.flac').writeAsBytes([1, 2, 3]);
    return Track(id: file.uri.toString(), uri: file.uri, title: source.title, artist: source.artist);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late List<Duration> previousDelays;
  final source = Spotiflac.track('test', {'id': '1', 'name': 'Test'})!;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('riflay-download-retry-');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => root.path,
    );
    await DownloadPrefs.instance.setFolder(root.path);
    previousDelays = YoutubeImporter.retryDelays;
    YoutubeImporter.retryDelays = List.filled(8, Duration.zero);
  });
  tearDown(() async {
    YoutubeImporter.retryDelays = previousDelays;
    await root.delete(recursive: true);
  });

  Future<DownloadJob> run(_Flaky provider, {bool cancel = false}) async {
    final finished = Completer<DownloadJob>();
    var indexed = 0;
    final importer = YoutubeImporter(
      extensionRuntime: provider,
      onTrackReady: (_) async {
        indexed++;
      },
    );
    addTearDown(importer.dispose);
    importer.addListener(() {
      if (importer.jobs.isEmpty) return;
      final job = importer.jobs.single;
      if (cancel && job.phase == DownloadPhase.retrying && job.status == DownloadStatus.downloading) {
        importer.cancel(job);
      }
      if (!job.isActive && !finished.isCompleted) finished.complete(job);
    });
    importer.enqueueTracks([source]);
    final job = await finished.future.timeout(const Duration(seconds: 3));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(indexed, job.status == DownloadStatus.done ? 1 : 0);
    return job;
  }

  test('an extension recovers after five failures without manual retry', () async {
    final provider = _Flaky(5);
    final job = await run(provider);
    expect(job.status, DownloadStatus.done);
    expect(provider.calls, 6);
  });

  test('persistent failure stops after the shared eight retry budget', () async {
    final provider = _Flaky(100);
    expect((await run(provider)).status, DownloadStatus.failed);
    expect(provider.calls, 9);
  });

  test('verification requires user action and is not retried blindly', () async {
    final provider = _Flaky(0, verification: true);
    expect((await run(provider)).status, DownloadStatus.failed);
    expect(provider.calls, 1);
  });

  test('cancelling during a long backoff prevents another request', () async {
    YoutubeImporter.retryDelays = [const Duration(hours: 1)];
    final provider = _Flaky(100);
    expect((await run(provider, cancel: true)).status, DownloadStatus.cancelled);
    expect(provider.calls, 1);
  });
}

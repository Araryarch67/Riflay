import 'dart:io';
import 'dart:async';

import 'package:riflay/models/track.dart';
import 'package:riflay/services/youtube_importer.dart';
import 'package:riflay/services/download_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/monochrome.dart';
import 'package:riflay/services/ytmusic_web.dart';
import 'package:riflay/services/library_views.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'downloads and fully decodes the reported failing Monochrome song',
    () async {
      final previousHttpOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      final source = Monochrome.track({
        'trackId': '165781419838844928',
        'title': 'I I I',
        'artistNames': ['宝鐘マリン', 'Kobo Kanaeru'],
      }, native: true)!;
      final directory = await Directory.systemTemp.createTemp('riflay-monochrome-live-');
      SharedPreferences.setMockInitialValues({'downloads.folder': directory.path});
      await DownloadPrefs.instance.load();
      final ready = Completer<Track>();
      final importer = YoutubeImporter(
        onTrackReady: (track) async {
          ready.complete(track);
        },
      );
      importer.addListener(() {
        for (final job in importer.jobs) {
          if (job.status == DownloadStatus.failed && !ready.isCompleted) {
            ready.completeError(StateError(job.error ?? 'Download failed'));
          }
        }
      });
      try {
        final results = await YtMusicWeb.anonymous().search('I I I Houshou Marine Kobo Kanaeru');
        expect(results.songs, isNotEmpty);
        final hit = results.songs.firstWhere((song) => song.title.replaceAll(' ', '').toUpperCase() == 'III');
        final origin = Track.youtube(
          videoId: hit.videoId,
          title: hit.title,
          artist: hit.artist,
          duration: hit.duration,
        );
        expect(importer.enqueueTracks([source], youtubeOrigin: origin), 1);
        final saved = await ready.future.timeout(const Duration(minutes: 4));
        expect(await File(saved.path!).length(), greaterThan(1024 * 1024));
        expect(saved.youtubeId, origin.videoId);
        expect(saved.streams, isFalse);
        final restored = Track.fromJson(saved.toJson());
        final views = LibraryViews([restored], 1);
        expect(views.downloads[origin.offlineId]?.id, restored.id);
        expect(views.downloads[source.offlineId]?.id, restored.id);
        final decoded = await Process.run('ffmpeg', ['-v', 'error', '-i', saved.path!, '-f', 'null', '-']);
        expect(decoded.exitCode, 0, reason: '${decoded.stderr}');
        expect('${decoded.stderr}'.trim(), isEmpty);
      } finally {
        HttpOverrides.global = previousHttpOverrides;
        importer.dispose();
        await directory.delete(recursive: true);
      }
    },
    skip: !const bool.fromEnvironment('RIFLAY_TEST_MONOCHROME_DOWNLOAD'),
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
